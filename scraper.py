"""
RLC Watch - scrapes job boards for Residence Life Coordinator/Manager postings
and emails/texts you ONLY when a new matching posting appears.

How it works:
  1. Fetches each board listed in boards.json
  2. Extracts link text + surrounding text, scans for title matches
  3. Fingerprints each match (board + normalized title + link)
  4. Diffs against state/seen.json; anything new -> email + SMS + saved to state

Runs locally only (no cloud/CI). Two ways to use it:
  One-shot:  python scraper.py
  Dry run:   python scraper.py --dry-run       (prints matches, no email/SMS/state write)
  Loop:      python scraper.py --loop --interval 30   (checks every 30 min, forever)

Credentials (Gmail app password, SMS gateway address) go in local_settings.json,
copied from local_settings.example.json. That file is gitignored - never commit it.
"""

import argparse
import hashlib
import json
import os
import re
import smtplib
import sys
import time
from datetime import datetime, timezone
from email.mime.text import MIMEText
from pathlib import Path
from urllib.parse import urljoin

import requests
from bs4 import BeautifulSoup

ROOT = Path(__file__).parent
STATE_FILE = ROOT / "state" / "seen.json"
BOARDS_FILE = ROOT / "boards.json"
LOCAL_SETTINGS_FILE = ROOT / "local_settings.json"

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 Safari/537.36"
}

# ---- matching rules -------------------------------------------------------
# A posting title matches if it contains a RESIDENCE term AND a ROLE term,
# and does NOT contain any EXCLUDE term.
RESIDENCE_TERMS = [r"residence", r"housing", r"res\s*life"]
ROLE_TERMS = [r"coordinator", r"co-ordinator", r"manager", r"supervisor"]
EXCLUDE_TERMS = [
    r"resident assistant", r"residence assistant", r"\bra\b", r"\bdon\b",
    r"student staff", r"attendant", r"front desk", r"desk assistant",
    r"custod", r"housekeep", r"maintenance", r"cook", r"chef", r"security guard",
    r"admission", r"nurse", r"physician", r"medical", r"psychiatr",
]


def title_matches(text: str) -> bool:
    t = " ".join(text.lower().split())
    if not any(re.search(p, t) for p in RESIDENCE_TERMS):
        return False
    if not any(re.search(p, t) for p in ROLE_TERMS):
        return False
    if any(re.search(p, t) for p in EXCLUDE_TERMS):
        return False
    return True


# ---- scraping -------------------------------------------------------------

def fetch(url: str) -> str | None:
    try:
        r = requests.get(url, headers=HEADERS, timeout=30)
        r.raise_for_status()
        return r.text
    except Exception as e:
        print(f"  [warn] fetch failed for {url}: {e}", file=sys.stderr)
        return None


def fetch_js(url: str, wait_ms: int = 6000) -> str | None:
    """Render a JavaScript-built page with headless Chromium (Playwright).
    Needed for Workday, Oracle, MacEwan-style portals."""
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        print("  [warn] playwright not installed; skipping JS board", file=sys.stderr)
        return None
    try:
        with sync_playwright() as pw:
            browser = pw.chromium.launch()
            page = browser.new_page(user_agent=HEADERS["User-Agent"])
            page.goto(url, wait_until="domcontentloaded", timeout=45000)
            page.wait_for_timeout(wait_ms)
            html = page.content()
            browser.close()
            return html
    except Exception as e:
        print(f"  [warn] JS fetch failed for {url}: {e}", file=sys.stderr)
        return None


def scan_workday(board: dict) -> list[dict]:
    """Workday exposes a JSON search API - far more reliable than rendering.
    Requires host, tenant, site in board config. Verify per-school with --dry-run."""
    api = f"https://{board['host']}/wday/cxs/{board['tenant']}/{board['site']}/jobs"
    jobs_base = f"https://{board['host']}/en-US/{board['site']}"
    payload = {"appliedFacets": {}, "limit": 20, "offset": 0,
               "searchText": board.get("search_text", "residence")}
    matches = []
    try:
        r = requests.post(api, json=payload, headers={**HEADERS, "Content-Type": "application/json"}, timeout=30)
        r.raise_for_status()
        for posting in r.json().get("jobPostings", []):
            title = posting.get("title", "")
            if title_matches(title):
                link = jobs_base + posting.get("externalPath", "")
                matches.append({"board": board["name"], "title": title, "link": link})
    except Exception as e:
        print(f"  [warn] workday api failed for {board['name']}: {e}", file=sys.stderr)
    return matches


def scan_board(board: dict) -> list[dict]:
    """Scan one board. mode: 'html' (default), 'js' (Playwright render),
    or 'workday' (JSON API)."""
    mode = board.get("mode", "html")
    if mode == "workday":
        return scan_workday(board)
    html = fetch_js(board["url"]) if mode == "js" else fetch(board["url"])
    if html is None:
        return []
    soup = BeautifulSoup(html, "html.parser")
    matches = []

    for a in soup.find_all("a", href=True):
        text = a.get_text(" ", strip=True)
        if not text or len(text) > 140:
            continue
        if title_matches(text):
            link = urljoin(board["url"], a["href"])
            matches.append({"board": board["name"], "title": text, "link": link})

    # Fallback: some boards render titles in headings/rows without direct links
    if not matches:
        for tag in soup.find_all(["h1", "h2", "h3", "h4", "td", "li", "span", "div"]):
            text = tag.get_text(" ", strip=True)
            if text and len(text) <= 140 and title_matches(text):
                matches.append({"board": board["name"], "title": text, "link": board["url"]})

    # de-dupe within the page
    unique = {}
    for m in matches:
        unique[fingerprint(m)] = m
    return list(unique.values())


def fingerprint(m: dict) -> str:
    norm_title = " ".join(m["title"].lower().split())
    return hashlib.sha256(f'{m["board"]}|{norm_title}'.encode()).hexdigest()[:16]


# ---- state ----------------------------------------------------------------

def load_state() -> dict:
    if STATE_FILE.exists():
        return json.loads(STATE_FILE.read_text())
    return {"seen": {}}


def save_state(state: dict) -> None:
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(state, indent=2, sort_keys=True))


# ---- local settings --------------------------------------------------------

def load_local_settings() -> None:
    """Merge local_settings.json (gitignored) into the environment, without
    overwriting real env vars if they're already set."""
    if not LOCAL_SETTINGS_FILE.exists():
        return
    settings = json.loads(LOCAL_SETTINGS_FILE.read_text())
    for k, v in settings.items():
        value = str(v).strip()
        placeholder = value.lower()
        if (
            k.startswith("_")
            or not value
            or "replace_with" in placeholder
            or "youraddress@" in placeholder
            or "your gmail app password" in placeholder
        ):
            continue
        os.environ.setdefault(k, value)


# ---- email / SMS ------------------------------------------------------------

def send_email(new_jobs: list[dict]) -> None:
    user = os.environ.get("ALERT_EMAIL_USER")
    pw = os.environ.get("ALERT_EMAIL_APP_PASSWORD")
    to = os.environ.get("ALERT_EMAIL_TO", user)
    if not user or not pw:
        print("[warn] ALERT_EMAIL_USER / ALERT_EMAIL_APP_PASSWORD not set; printing instead.")
        for j in new_jobs:
            print(f'  NEW: {j["title"]} - {j["board"]} - {j["link"]}')
        return

    lines = [f'* {j["title"]}\n  {j["board"]}\n  {j["link"]}\n' for j in new_jobs]
    body = "New residence life posting(s) found:\n\n" + "\n".join(lines)
    subject = f"[RLC Watch] {len(new_jobs)} new posting{'s' if len(new_jobs) > 1 else ''}"

    msg = MIMEText(body)
    msg["Subject"] = subject
    msg["From"] = user
    msg["To"] = to

    with smtplib.SMTP_SSL("smtp.gmail.com", 465) as s:
        s.login(user, pw)
        s.sendmail(user, [to], msg.as_string())
    print(f"[ok] emailed {len(new_jobs)} new posting(s) to {to}")


def send_sms(new_jobs: list[dict]) -> None:
    """Text via email-to-SMS gateway (e.g. 5551234567@txt.bell.ca in ALERT_SMS_TO).
    Short body only - full details go out via send_email instead."""
    user = os.environ.get("ALERT_EMAIL_USER")
    pw = os.environ.get("ALERT_EMAIL_APP_PASSWORD")
    sms_to = os.environ.get("ALERT_SMS_TO")
    if not sms_to or not user or not pw:
        return

    titles = ", ".join(j["title"] for j in new_jobs[:3])
    body = f"RLC Watch: {len(new_jobs)} new posting(s) - {titles}. Check email for links."

    msg = MIMEText(body)
    msg["Subject"] = ""
    msg["From"] = user
    msg["To"] = sms_to

    try:
        with smtplib.SMTP_SSL("smtp.gmail.com", 465) as s:
            s.login(user, pw)
            s.sendmail(user, [sms_to], msg.as_string())
        print(f"[ok] texted {sms_to}")
    except Exception as e:
        print(f"  [warn] SMS send failed: {e}", file=sys.stderr)


# ---- main -----------------------------------------------------------------

def run_once(dry_run: bool) -> None:
    boards = json.loads(BOARDS_FILE.read_text())
    state = load_state()
    now = datetime.now(timezone.utc).isoformat()

    all_new = []
    for board in boards:
        if not board.get("enabled", True):
            continue
        print(f"[scan] {board['name']}")
        for m in scan_board(board):
            fp = fingerprint(m)
            if dry_run:
                print(f"  match: {m['title']} -> {m['link']}")
            elif fp not in state["seen"]:
                state["seen"][fp] = {**m, "first_seen": now}
                all_new.append(m)

    if dry_run:
        return
    if all_new:
        send_email(all_new)
        send_sms(all_new)
    else:
        print("[ok] no new postings")
    save_state(state)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true", help="print matches, no email/SMS/state")
    parser.add_argument("--loop", action="store_true", help="run continuously instead of once")
    parser.add_argument("--interval", type=int, default=30, help="minutes between checks in --loop mode (default 30)")
    args = parser.parse_args()

    load_local_settings()

    if not args.loop:
        run_once(args.dry_run)
        return

    print(f"[loop] checking every {args.interval} min - Ctrl+C to stop")
    try:
        while True:
            ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            print(f"\n[loop] cycle starting at {ts}")
            try:
                run_once(args.dry_run)
            except Exception as e:
                print(f"  [error] scan cycle failed: {e}", file=sys.stderr)
            time.sleep(args.interval * 60)
    except KeyboardInterrupt:
        print("\n[loop] stopped")


if __name__ == "__main__":
    main()
