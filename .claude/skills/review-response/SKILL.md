---
name: review-response
description: Respond to PR review comments. Fetches new feedback, filters bots, tracks addressed state, and interactively triages each comment before entering plan mode.
user_invocable: true
arguments:
  - name: target
    description: "Optional PR number or branch name. Defaults to the current branch's PR."
    required: false
---

# Review Response Skill

Fetch PR review comments, filter noise, identify what's new, interactively triage each comment, and enter plan mode only for comments that need code changes.

## Workflow

### 1. Resolve PR

Run in parallel:
- `git rev-parse --abbrev-ref HEAD` — current branch
- `git remote get-url origin` — extract owner/repo from remote URL
- `gh api user -q .login` — current authenticated GitHub user login

Parse `owner` and `repo` from the remote URL. Handles both formats:
- `git@github.com:owner/repo.git`
- `https://github.com/owner/repo.git`

Then resolve the PR:
- If `target` arg is a number, use it directly: `gh pr view <number> --json number,state,title,url,headRefName`
- If `target` arg is a branch name: `gh pr view <target> --json number,state,title,url,headRefName`
- If no `target`: `gh pr view --json number,state,title,url,headRefName` (uses current branch)

**Stop conditions:**
- No PR found — report it and stop
- PR state is `MERGED` or `CLOSED` — report it and stop

### 2. Fetch Comments

Run three `gh api` calls **in parallel**:

```bash
# Inline code review comments
gh api --paginate "repos/{owner}/{repo}/pulls/{number}/comments"

# Formal reviews (APPROVED, CHANGES_REQUESTED, COMMENTED, DISMISSED)
gh api --paginate "repos/{owner}/{repo}/pulls/{number}/reviews"

# General PR conversation comments
gh api --paginate "repos/{owner}/{repo}/issues/{number}/comments"
```

### 3. Filter Bots

Remove comments where:
- `user.type == "Bot"`
- `user.login` ends with `[bot]`

This is mandatory — never present bot comments as review feedback.

### 4. Load State & Identify New

State file path: `~/.claude/review-state/{owner}-{repo}-{number}.md`

- Read the state file if it exists
- Extract all comment IDs from the `## Addressed Comments`, `## Addressed Reviews`, and `## Addressed General Comments` sections
- A comment is "handled" if its `id` is in the state file — skip these immediately

**Reaction-based skip check:** For each remaining comment NOT in the state file, fetch its reactions to see if the current user already reacted with `+1`:

- Inline comments: `gh api repos/{owner}/{repo}/pulls/comments/{id}/reactions`
- Issue comments: `gh api repos/{owner}/{repo}/issues/comments/{id}/reactions`
- Review comments: reviews don't have a reactions API — skip this check for formal reviews

A comment is also "handled" if it has a `+1` reaction from the current user (the login fetched in phase 1). These comments should be recorded into the state file so future runs skip them without re-fetching reactions.

**Batch the reaction checks** — run them in parallel where possible to avoid N sequential API calls.

- If nothing is new after both state-file and reaction checks, report "No new review comments" and stop.

### 5. Interactive Triage

Present each new comment one at a time for the user to decide how to handle it.

**Ordering** — present in priority order:
1. Comments from `CHANGES_REQUESTED` reviews (blocking)
2. Inline review comments (actionable)
3. General PR comments (discussion)

**Formal reviews filtering before presentation:**
- `APPROVED` and `DISMISSED` reviews: skip unless they have substantive body text (non-empty after trimming whitespace)
- `COMMENTED` reviews with no body: skip entirely (they're just containers for inline comments which are handled separately)
- `CHANGES_REQUESTED` with no body: present as informational (see options below)

**For each comment, use `AskUserQuestion`:**

Show a progress indicator as the question header: `Comment N of M`

Present context in the question body:
- **Inline comments:** show author, `path:line`, diff hunk excerpt (last ~5 lines of `diff_hunk`), comment body. If threaded (has `in_reply_to_id` chain), show the full thread for context.
- **Formal reviews:** show author, review state, body
- **General comments:** show author, body

**Threading:** Present threaded inline comments as a single unit. Show the full thread for context, keyed by the newest unhandled comment in the thread. Ask for action on the thread as a whole.

**Options:**

For inline comments and general comments — three options:
1. **Add to plan** — description: "Address this with code changes"
2. **React +1** — description: "Acknowledge with thumbs up on GitHub"
3. **Reply** — description: "Write a response on GitHub"

For formal reviews with body text — four options:
1. **Add to plan** — description: "Address this with code changes"
2. **React +1** — description: "Acknowledge with thumbs up on GitHub" (only if the review type supports reactions)
3. **Reply** — description: "Write a response on GitHub"
4. **Skip** — description: "No action needed"

For `CHANGES_REQUESTED` reviews with no body — two options:
1. **Acknowledged** — description: "Note this and continue"
2. **Reply** — description: "Write a response on GitHub"

**Handling each choice:**

- **Add to plan**: Record the comment in an in-memory plan list (comment ID, path, line, body, thread context). Record the comment ID as handled. Continue to the next comment.
- **React +1**: Immediately post the reaction via the GitHub API:
  - Inline comments: `gh api repos/{owner}/{repo}/pulls/comments/{id}/reactions -f content="+1"`
  - Issue comments: `gh api repos/{owner}/{repo}/issues/comments/{id}/reactions -f content="+1"`
  Record the comment ID as handled. Continue.
- **Reply**: Present a follow-up `AskUserQuestion`:
  - Question: "What would you like to reply?" with header "Reply"
  - Two options: a placeholder like "Sounds good, will fix" and another like "I think the current approach is correct because..."
  - The user types their actual reply via the "Other" free-text option (or selects a template to start from)
  - Post the reply via `gh api`:
    - Inline comments: `gh api repos/{owner}/{repo}/pulls/{number}/comments -f body="..." -f in_reply_to={id}`
    - General/review comments: `gh api repos/{owner}/{repo}/issues/{number}/comments -f body="..."`
  Record the comment ID as handled. Continue.
- **Skip** / **Acknowledged**: Record the comment ID as handled. Continue to the next comment.

### 6. Enter Plan Mode — Conditional

- If no comments were added to the plan list: report "All comments handled. No code changes needed." Skip directly to phase 7 (state file update).
- If comments were added to the plan list: use the `EnterPlanMode` tool. In plan mode:
  - For each comment in the plan list:
    - Read the referenced files
    - Analyze what the reviewer is asking for
    - Propose concrete changes to address the feedback
    - If the feedback seems wrong or a misunderstanding, flag it for potential pushback and explain why
  - Organize the plan by priority:
    1. `CHANGES_REQUESTED` reviews — these block merging
    2. Inline comments on code — specific and actionable
    3. General comments — often discussion, may not need code changes
  - For items where pushback is appropriate, draft a suggested reply the user could post (but never post it — see rules below)

Wait for user approval before making any changes.

### 7. After Execution

Once the user has approved and changes have been made (or if no plan was needed):

**Update state file:**
- Create `~/.claude/review-state/` directory if it doesn't exist (`mkdir -p`)
- Write/update `~/.claude/review-state/{owner}-{repo}-{number}.md` with ALL triaged comment IDs regardless of action taken (plan, react, reply, skip, acknowledged)

State file format:

```markdown
# Review State: {owner}/{repo} #{number}

Last updated: {YYYY-MM-DD}

## Addressed Comments
- {id} <!-- @{login}, {path}:{line}, {YYYY-MM-DD}, {action} -->

## Addressed Reviews
- {id} <!-- @{login}, {state}, {YYYY-MM-DD}, {action} -->

## Addressed General Comments
- {id} <!-- @{login}, {YYYY-MM-DD}, {action} -->
```

- IDs are the source of truth (immutable, unlike timestamps)
- HTML comments are human-readable context only — the `{action}` field (e.g. `planned`, `reacted`, `replied`, `skipped`, `acknowledged`) is informational
- Both "addressed" and "skipped" comments go into state so they don't resurface
- Preserve existing entries when appending new ones
- Include any comments that were detected as handled via reaction checking (record them so future runs don't need to re-check reactions)

**Offer to reply to additional threads:**
- Ask the user: "Would you like to reply to any additional threads?"
- If yes, show the proposed reply and get confirmation before posting
- Use `gh api` to post replies

## Important

- **Always** present one comment at a time during triage — never batch-present
- **Always** execute React/Reply actions immediately during triage — don't defer them
- **Always** enter plan mode before making any code changes (but only if comments were added to the plan)
- **Never** auto-react or auto-reply — every action requires explicit user choice via `AskUserQuestion`
- **Never** dismiss or resolve review threads — that's the reviewer's prerogative
- **Never** silently skip feedback — explain why something is being skipped and record it in state
- **Never** invoke the commit skill automatically — the user decides when to commit
- **Never** present `APPROVED` or `DISMISSED` reviews unless they have substantive body text
- Bot filtering is mandatory — no exceptions
- Reaction checking uses `+1` content only — ignore other reaction types
- If a thread has both old and new comments, show the full thread for context but only triage the new ones
- Prefer `gh` CLI for all GitHub API calls — it handles auth automatically
