# RLC Watch — Project Context

## What this is

Job-alert scraper for Residence Life Coordinator/Manager postings across Canadian
post-secondary job boards plus Indeed/LinkedIn/Glassdoor. Owner: Trinity (Shrishty
Gnanasekaran), an RLC at a Campus Living Centres property (Okanagan College
Residence, Vernon BC) targeting university-employed RLC roles. Goal: an email
(and optional text) the moment any RLC-tier posting appears, title-only
detection (she checks details herself).

## Architecture (decided, don't redesign without asking)

- Runs LOCALLY only — no GitHub Actions/cloud CI. Deliberate choice: keeps her
  real LinkedIn/Glassdoor browsing off shared cloud IPs (lower bot-detection
  risk) and avoids managing cloud secrets for a personal tool.
- `scraper.py` — single script, three fetch modes per board:
  - `html`: requests + BeautifulSoup (plain HTML boards)
  - `js`: Playwright headless Chromium (Oracle/SuccessFactors/PeopleSoft/Workday-UI
    -style portals, plus Indeed/LinkedIn/Glassdoor search pages)
  - `workday`: Workday's JSON search API `POST /wday/cxs/{tenant}/{site}/jobs`
    (more reliable than rendering — prefer this for any Workday school)
- Indeed/LinkedIn/Glassdoor are scraped LOGGED OUT — verified their public
  search-results pages render real postings without any login. Deliberately NOT
  using credentials/session cookies for these: LinkedIn in particular aggressively
  flags automated logins, and doing that repeatedly would put her real account
  at risk. If logged-out results ever dry up, re-verify manually before assuming
  it's a bug.
- Matching: title must contain a RESIDENCE term AND a ROLE term
  (coordinator/manager/supervisor), must NOT contain EXCLUDE terms (RA, don,
  attendant, custodial, front desk, admissions, etc.). Lists at top of scraper.py.
  Aggregator boards (Indeed/LinkedIn/Glassdoor) will surface non-university noise
  (group homes, youth services, hospitality) — same filter applies, she reviews
  details herself.
- State: `state/seen.json`, fingerprint = sha256(board + normalized title +
  canonical posting link). New fingerprint => alert. Link-aware fingerprints are
  required because CLC can post multiple distinct jobs with the same title, such
  as two separate "Residence Life Coordinator" postings.
- Alerts: Gmail SMTP (SSL 465) for email, plus optional SMS via email-to-SMS
  carrier gateway (e.g. `5551234567@txt.bell.ca`). SMS body is a short summary
  only; full details/links go out by email. Both are best-effort — if
  `ALERT_SMS_TO` isn't set, SMS is silently skipped. Optional routine "still
  alive" texts are controlled by `ALERT_STATUS_SMS_HOURS`; routine status
  emails are controlled by `ALERT_STATUS_EMAIL_HOURS`.
- Virgin Plus email-to-SMS did not deliver locally in July 2026 (`@vmobile.ca`
  and `@txt.virginplus.ca` failed silently), so local settings currently use
  Gmail push notifications/status email rather than SMS gateway delivery.
- Optional Telegram push notifications can be configured with
  `ALERT_TELEGRAM_BOT_TOKEN` and `ALERT_TELEGRAM_CHAT_ID`. Telegram messages are
  short "new hits found, check email" pings only; email remains the source for
  full links/details.
- Credentials/config: `local_settings.json` (gitignored — never commit it),
  copied from `local_settings.example.json`. Loaded into the environment at
  startup without overriding real env vars if already set.
- General job boards (Indeed/LinkedIn/Glassdoor) are tagged as
  `category: "general_job_board"` and can be toggled with
  `INCLUDE_GENERAL_JOB_BOARDS`. When enabled, general boards get an extra
  university/post-secondary context filter so "Residence Coordinator" social
  service/case-manager roles are rejected.
- Two run modes:
  - One-shot: `python scraper.py` (intended for Windows Task Scheduler or a
    manual run).
  - Loop: `python scraper.py --loop --interval 30` — runs forever, checking
    every N minutes, alerting immediately when it finds something new. This is
    the "constantly pings me" mode — leave a terminal open, or launch it at
    login.
- `--dry-run` prints matches, no email/SMS/state write. Use it after any
  boards.json edit, and combine with `--loop`-less single runs when testing.

## Current status / known gaps (the actual TODO)

- 47 enabled boards in `boards.json`, verified/re-verified against live pages:
  every Canadian university career portal plus CACUSS, OACUHO, Indeed, LinkedIn,
  Glassdoor, and the CLC board (covers every CLC property in one request).
- Recently re-enabled after manual verification:
  - Trent University now uses the production `https://employment.trentu.ca/default`
    external recruitment site linked from Trent HR.
  - Saint Mary's University (Halifax) uses the official staff employment page,
    which injects CareerBeacon job links and therefore needs `js` mode.
  - University of Winnipeg uses `https://www.northstarats.com/University-of-Winnipeg`,
    confirmed through official UWinnipeg pages and plain HTML fetches.
- U of T college-specific coverage has been added for Victoria, Trinity,
  St. Mike's, Woodsworth, New, Innis, and University College. Some of these
  pages mainly post student-staff roles; the existing title filter excludes
  Don/front-desk noise while preserving RLC-tier titles.
- Indeed/LinkedIn/Glassdoor remain configured and locally enabled with the
  university-context filter. Turn `INCLUDE_GENERAL_JOB_BOARDS` to `false` in
  `local_settings.json` if aggregator boards get too noisy again.
- Several `js`-mode boards rely on scanning the FULL rendered listing rather
  than a server-side keyword filter (confirmed true for U of A Oracle — its
  `?keyword=` param doesn't actually filter). This is fine because
  `title_matches` re-filters everything client-side regardless of what the
  portal claims to have searched.

## Constraints & preferences

- Keep it simple: single script + JSON config. No frameworks, no database, no
  new dependencies for SMS (reuses the same Gmail SMTP connection as email).
- She's a CS grad (U of A) — comfortable with Python; prefers simple multi-line
  code over dense one-liners.
- Local execution only, free (no paid services — ruled out Twilio for this
  reason; email-to-SMS gateway chosen instead).
- False negatives are worse than false positives, but don't let attendant/RA-level
  postings through — those are the noise she's specifically avoiding.
- JS-locked top targets (U of A Oracle, UBC Workday) also have native portal
  alerts set as backup.
- Never wire real LinkedIn/Glassdoor login credentials into this scraper —
  logged-out scraping already works and is lower-risk; revisit only if
  logged-out access breaks and she explicitly asks to reconsider.
