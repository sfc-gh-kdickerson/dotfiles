---
name: weekly-review
description: >
  Compile and log a record of what the user actually did over a time window (default: the current
  week) by gathering their activity across GitHub, Slack, Google Drive, Jira/Confluence, Google
  Calendar, and Gmail, then producing an impact-framed Highlights section plus a full Activity Log
  and appending a dated entry to a running "Weekly Work Log" Google Doc. Use whenever the user wants
  to review, summarize, or keep a record of what they got done — Friday wrap-ups, "what did I get
  done this week", standup or status-update prep, 1:1 notes, or assembling the raw evidence for a
  perf/promo case — even if they don't say "weekly review". Also rolls the accumulated log up into a
  themed summary for a longer period on request (e.g. "what did I do this quarter"). This skill
  GATHERS and LOGS the material; it does not write the promo narrative or self-assessment prose
  itself — that's the natural-writing skill's job. Invoked manually as /weekly-review; the user
  re-auths any stale sources at run time.
user_invocable: true
arguments:
  - name: period
    description: "Time window: 'this week' (default), 'last week', an explicit range like '2026-07-06..2026-07-12', or 'quarter'/'rollup' to synthesize the existing log instead of pulling sources."
    required: false
  - name: sources
    description: "Comma-separated override of which sources to pull (default: github,slack,drive,jira,calendar,gmail)."
    required: false
---

# Weekly Review

Gather everything the user did over a week from the systems where their work actually lives, then
turn raw activity into a record they can use: a short, impact-framed **Highlights** section for
status updates and perf/promo, on top of a comprehensive **Activity Log** for reference. The result
is appended to one running Google Doc so the record accumulates over time.

The point is to convert *activity* ("opened 3 PRs") into *accomplishment* ("shipped X, which did
Y"). A raw dump of API results is not the deliverable — the synthesis is.

This skill is run manually in a live session (there is no unattended scheduler), which is
deliberate: several source MCPs need periodic OAuth, and running live means you can re-auth a stale
source on the spot instead of silently missing data.

## Configuration & state

State lives at `~/.claude/weekly-review/config.json`:

```json
{
  "googleDocId": "1AbC...",
  "docTitle": "Weekly Work Log — Kaleb Dickerson",
  "githubLogin": "kaleb-dickerson_snow",
  "slackUserId": "U093HAAA338",
  "sources": ["github", "slack", "drive", "jira", "calendar", "gmail"],
  "lastWindowEnd": "2026-07-19"
}
```

Read it at the start of every run. If it doesn't exist yet, this is a **first run** — you'll create
the Google Doc and write the config during Step 5. Resolve `githubLogin` at runtime rather than
trusting a stale value (see Step 2).

## Step 1 — Resolve the time window

Default to the current week, Monday 00:00 local through now. Compute concrete dates with `date`
(macOS/BSD) so every downstream query uses the same window:

```bash
# Monday 00:00 of the current week
WEEK_START=$(date -v-$(($(date +%u)-1))d +%Y-%m-%d)
NOW=$(date +%Y-%m-%dT%H:%M:%S)
```

- `period=last week` → shift the window back 7 days (start = previous Monday, end = the Sunday before this Monday).
- `period=YYYY-MM-DD..YYYY-MM-DD` → use those bounds verbatim.
- If `config.lastWindowEnd` exists and predates this window's start by more than a day, mention that there's an uncovered gap and offer to widen the window — the goal is a record with no holes.

State the resolved window in one line, then proceed. Only **stop for confirmation** when the window is non-default — an explicit range, `last week`, or the gap-widen case above — since that's where a wrong range costs a wasted run. Re-confirming the obvious "this week" default every Friday is just friction.

If `period` is `quarter` or `rollup`, skip Steps 2–3 entirely and go to the **Rollup mode** section below.

## Step 2 — Preflight: identity & auth (main session, before any subagents)

Subagents share the session's MCP auth, but they **cannot** complete an interactive OAuth flow — the
auth handshake returns a URL a human must open. If you discover a stale source *mid-fan-out*, the user
authorizes it but that subagent has already given up, so the source stays a hole until next week. Avoid
that by resolving auth up front, in one batch:

1. **GitHub identity:** `gh api user -q .login` → `githubLogin`. (Multiple `gh` accounts may exist;
   `@me` and `gh api user` resolve to the active one — fine.)
2. **Probe each selected MCP source cheaply** — one tiny call apiece (a 1-item fetch, not a full pull):
   e.g. Slack search with `limit 1`, Drive `list_files` `maxResults 1`, `list_events` `maxResults 1`,
   `getAccessibleAtlassianResources`, Gmail `list_messages` `maxResults 1`. Note every source that comes
   back needing auth.
3. **If any need auth, present them once, batched:** "N sources need re-auth before I can pull them:
   [links/steps]. Authorize these, then say 'go'." Wait, re-probe the stale ones, and only then fan out
   in Step 3 — this guarantees a re-authed source actually gets pulled *this* run instead of leaving a gap.
4. If the user would rather skip a source than re-auth it, that's their call — drop it and record it as
   `(skipped)` in the log. Never fabricate data for a source you couldn't reach.

The probes are cheap and read-only; the point is to turn what would be N mid-run dead-ends into one gate.

## Step 3 — Gather activity (parallel subagents, one per source)

Dispatch one `general-purpose` subagent per selected source, **all in a single message so they run
concurrently**. Each subagent's job is to pull its slice of the window and return a **compact
markdown summary with links — never a raw dump**. Keeping raw API results out of the main context is
the whole reason to use subagents; the main session only ever sees the summaries.

Give every subagent: the resolved `WEEK_START`/`NOW`, the user's `githubLogin` and `slackUserId`, and
an instruction to report `(unavailable — needs re-auth)` if its source errors on auth.

### GitHub — Bash `gh`
```bash
gh search prs    --author "@me"      --updated ">=$WEEK_START" --limit 100 --json number,title,url,state,repository,createdAt,updatedAt,closedAt
gh search prs    --reviewed-by "@me" --updated ">=$WEEK_START" --limit 100 --json number,title,url,state,repository,updatedAt
gh search issues --author "@me"      --updated ">=$WEEK_START" --limit 100 --json number,title,url,state,repository,createdAt,closedAt
```
Classify by repo: PRs **opened** this week (createdAt in window), **merged** (state merged, closedAt in
window), still **in progress**; PRs **reviewed** for others; issues opened/closed. Cross-repo commit
history isn't reliably queryable via `gh` — treat PRs as the proxy and don't claim per-commit counts.
Return a per-repo summary with linked PR/issue titles.

### Slack — MCP `slack_natoma`
Use `slack_search_public_and_private` with `query: "from:<@{slackUserId}> after:{day before WEEK_START}"`
(Slack's `after:` is exclusive, so use the prior day). Group by channel and summarize *substance* —
decisions made, help given, questions answered, announcements — not every one-liner. Include
permalinks for the few genuinely notable messages/threads. Skip reactions and trivia.

### Google Drive — MCP `gdrive_natoma`
`list_files` with `q: "modifiedTime > '{WEEK_START}T00:00:00' and 'me' in writers and trashed = false"`,
`orderBy: "modifiedTime desc"`. Report each doc/sheet/slide with its link, and flag which were
**created** this week (createdTime in window) vs. merely edited.

### Jira / Confluence — MCP `atlassian_natoma`
Resolve `cloudId` first via `getAccessibleAtlassianResources`. Then:
- Issues: `searchJiraIssuesUsingJql` with `jql: "assignee = currentUser() AND updated >= '{WEEK_START}' ORDER BY updated DESC"`. Also catch issues you moved but don't own: `"status changed BY currentUser() AFTER '{WEEK_START}'"`.
- Confluence: `searchConfluenceUsingCql` with `cql: "contributor = currentUser() and lastmodified >= '{WEEK_START}'"`.
Summarize issues (key, summary, status, what changed) and pages authored/edited, with links.

### Google Calendar — MCP `gcal_natoma`
`list_events` (calendarId `primary`, `singleEvents: true`, `orderBy: "startTime"`) with `timeMin: WEEK_START`,
`timeMax: NOW`. Drop events the user declined. This is supporting texture, not accomplishment evidence:
**cap it at ≤2 lines** (meeting count, rough total hours, at most one genuinely notable meeting/1:1), keep
it **Activity-Log only, never a Highlight**, and if there's nothing worth noting, omit it silently rather
than announcing a gap. "Attended 14 meetings" is the opposite of the activity→impact conversion this skill
exists to do.

### Gmail — MCP `gmail_natoma`
`list_messages` with `q: "in:sent after:{YYYY/MM/DD of WEEK_START}"` (Gmail dates use slashes). Lowest-signal
source: report **only** genuinely substantive sent threads (recipient, subject, one-line gist), **cap at
≤2 lines, Activity-Log only, never a Highlight**, and omit silently if there's nothing but logistics and
scheduling. Don't let sent-mail volume pad a light week.

## Step 4 — Synthesize

Merge the subagent summaries into two sections. **Highlights** is the hard part and where the value
is: read across sources and collapse related activity into single accomplishments (a PR + its Jira
ticket + the Slack announcement are *one* highlight, not three). Frame each by outcome/impact, lead
with the result, and keep it to ~5–10 bullets. Cut filler — if a week was light, a short honest list
beats padding.

```markdown
## Week of {Mon D}–{Fri D}, {YYYY}
_Generated {YYYY-MM-DD}_

### 🔦 Highlights
- **{Project / theme}:** {what shipped or moved and why it mattered} ([#PR]({url}), [TICKET]({url}))
- ...

### 📋 Activity Log
**GitHub** — {N opened · N merged · N reviewed · N issues}
- {repo}: [#123 Title]({url}) — merged
- ...
**Slack** — {themes; notable threads linked}
**Drive** — {files created/edited, linked}
**Jira / Confluence** — {issues by status; pages}
**Calendar** — {N meetings · ~X hrs; anything notable}
**Gmail** — {notable sent threads}
```

Handle a missing source by which kind it is. If a source was **unreachable** (`unavailable — needs
re-auth` or `skipped`), say so plainly in its Activity Log line — a visible gap is honest; a silent one
looks like you didn't work. But if a **capped low-signal source** (Calendar, Gmail) simply had nothing
worth noting, omit it — nobody needs a line announcing you sent no notable email.

## Step 5 — Write to the running Google Doc

**First run (no `googleDocId` in config):**
1. `create_doc` with `title: "Weekly Work Log — {name}"`.
2. Write an H1 title/intro line at the top.
3. Save `googleDocId`, `docTitle`, resolved `githubLogin`, `slackUserId`, `sources`, and `lastWindowEnd`
   to `~/.claude/weekly-review/config.json`.

**Every run — prepend the new section (newest on top):**
Newest-first keeps the doc scannable without endless scrolling.
1. `get_doc_content` to read the current structure.
2. **Duplicate guard:** if a section already exists for this exact window (a re-run, or a half-finished
   earlier attempt), don't blindly prepend a second copy — ask the user whether to **replace** the existing
   section or **skip** the write. Silently producing two "Week of Jul 14" entries is worse than either.
3. Insert the new section at the index just past the H1 title: `batch_update_doc` with an `insertText`
   request there, then optionally `updateParagraphStyle` to set the "Week of…" line to HEADING_2 and the
   subheads to HEADING_3.

The Docs API's index math is finicky, and a wrong index on a doc with many weeks of history can splice the
new text into the *middle* of an old entry. Don't burn the run fighting styling — if it proves fragile,
insert clean text with bold labels and a divider (`modify_doc_text` is a fine fallback). Readability beats
perfect heading styles.

**Verify, then report:** re-read the doc (`get_doc_content`) and confirm **both** that the new section
landed at the top **and** that the previously-top section is still intact directly below it — i.e. you
inserted, not overwrote or spliced. Then update `config.lastWindowEnd` to the window's end date and, in
chat, give the user (1) the rendered **Highlights** section and (2) the doc link (`webViewLink` from
`get_file`/`create_doc`). The chat Highlights are the immediately-useful bit; the doc is the durable record.

## Rollup mode (`period=quarter` or `rollup`)

A stack of 13 weekly entries is raw material, not a perf/promo case — at review time the user still has to
collapse it into themes. This mode does that collapsing *from the doc itself*, without re-hitting any API:

1. Read the running doc (`get_doc_content`) and extract the **Highlights** bullets from every weekly section
   within the requested range (default: the current quarter).
2. Cluster them by project/theme and synthesize a themed summary — the throughline of each theme, the
   handful of highest-impact items, the outcomes — framed as evidence, not a week-by-week replay.
3. Output it in chat for the user to lift into their own writing. **Do not** write it back into the Weekly
   Work Log (that doc stays the weekly record), and **do not** write the actual promo/self-assessment prose —
   hand organized evidence to the natural-writing skill for that.

## Important

- **Read-only everywhere except the Weekly Work Log doc.** Never post to Slack, transition a Jira
  issue, send email, or modify a calendar event. The only thing this skill writes is that one Google
  Doc, which it owns.
- **Summarize, don't dump.** Subagents return distilled summaries with links; raw API payloads must
  not reach the main context.
- **Never fabricate activity.** An empty or unreachable source is reported as such. A slow week is a
  slow week — don't invent work to fill the page.
- **Honest framing.** Highlights should be impact-oriented but truthful; no inflating a drive-by
  review into a headline accomplishment.
- **Confirm the window** with the user before gathering, and surface auth steps as they arise rather
  than working around them.
