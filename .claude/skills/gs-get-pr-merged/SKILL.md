---
name: gs-get-pr-merged
description: >
  Drive a snowflake-eng/snowflake PR through merge gates to merged. Polls
  `gh pr checks`, diagnoses failures, and applies real fixes (never hacky
  workarounds) until required checks are green. Gates blocked only on a
  pending human action (e.g. review/approval) are left alone and re-polled
  periodically rather than treated as failures. Adds the `ready_for_merge`
  label, then monitors the SnowCI merge run to completion — if that run
  fails, diagnoses and fixes the real cause and reapplies the label. Exits
  and reports only if a failure can't be legitimately fixed or waited out.
  Use when the user says "get this PR merged", "shepherd this through the
  merge gates", "babysit this PR to merge", or similar, for a
  snowflake-eng/snowflake PR.
user_invocable: true
arguments:
  - name: pr
    description: "PR number or URL. Defaults to the PR for the current branch."
    required: false
  - name: interval
    description: "Minutes between polls while waiting on CI or the SnowCI merge run. Default: 10."
    required: false
---

# Get PR Merged (snowflake-eng/snowflake)

Two phases: **(A)** get merge gates green, **(B)** get through the SnowCI
`ready_for_merge` validation run. Loop A→label→B, and if B fails for a
fixable reason, go back to A without ever leaving the `ready_for_merge`
label on the PR while you push.

This skill takes real actions on a shared PR — pushing commits and
changing labels — autonomously and repeatedly. Before starting the loop,
state the plan and the PR to the user in one line so they have a chance
to stop you, then proceed without asking again at each iteration.

## Step 0 — Resolve context

```bash
gh repo view --json nameWithOwner --jq .nameWithOwner
```

If this isn't `snowflake-eng/snowflake`, tell the user this skill is
built for that repo's merge-gate/SnowCI conventions and confirm before
continuing — the gate list and label semantics below won't apply
elsewhere.

Resolve the PR:

```bash
PR=<from $ARGUMENTS.pr, or:>
gh pr view --json number,url,headRefName,baseRefName -q '.number'
```

If no PR is found, tell the user and stop. Record `BRANCH` (headRefName)
and `INTERVAL` (`$ARGUMENTS.interval`, default 10 minutes).

State to the user: "Shepherding PR #$PR ($BRANCH) to merge — will fix
failing gates, apply `ready_for_merge`, and monitor the merge run."

## Phase A — Get merge gates green

Merge gates = every required check surfaced by `gh pr checks`, plus the
prerequisites in `.buildkite/pipelines/pull-request-merge/pull-request-merge-instructions.md`
if present in this checkout (approvals, resolved review threads, no
merge conflicts).

Loop:

1. **Check status:**
   ```bash
   gh pr checks $PR
   gh pr view $PR --json reviewDecision,mergeable,mergeStateStatus
   ```

2. **All required checks passing, reviewDecision not REVIEW_REQUIRED/CHANGES_REQUESTED, mergeable != CONFLICTING?**
   → done with Phase A, go to Phase B.

3. **Otherwise, diagnose each failure.** If this checkout has
   `.claude/skills/debug-merge-gate/SKILL.md`, follow that skill's method
   (drill from `gh pr checks` → `gh api .../check-runs` → the failing
   step's driver script) to name the specific failing step and root
   cause — don't stop at the aggregate check name. Otherwise, inline the
   same approach:
   ```bash
   SHA=$(gh pr view $PR --json headRefOid -q .headRefOid)
   gh api "repos/snowflake-eng/snowflake/commits/$SHA/check-runs?per_page=100" \
     | jq -r '.check_runs[] | select(.conclusion=="failure" or .conclusion=="cancelled" or .conclusion=="timed_out") | "\(.name): \(.output.summary // "" | .[0:300])"'
   ```

4. **Classify each failure into one of three buckets:**

   - **Fixable by you** — formatting/lint, a build break, a failing test
     in your diff, a too-short PR description, a missing/incorrect
     CODEOWNERS reviewer request you can make, a merge conflict you can
     rebase and resolve. → Apply the real fix (see Guardrails below),
     commit, push:
     ```bash
     git add -A && git commit -m "<describes the actual fix>"
     git push
     ```
     Then wait `INTERVAL` minutes for CI to restart and complete, and go
     back to step 1.

   - **Blocked on someone else's pending action, nothing to fix** — the
     gate isn't red because of an error, it's just waiting on a human:
     an outstanding review/approval request, a required reviewer who
     hasn't looked yet, a check queued but not yet started, a
     prerequisite that just hasn't been satisfied yet. This is the
     common case for a reviewer/approval gate. → **Do nothing to it.**
     Don't ping anyone, don't re-request review, don't treat it as a
     failure. Wait `INTERVAL` minutes and go back to step 1. Once it
     clears (approval lands, check starts and passes), the loop
     naturally proceeds — that's the point of leaving it alone instead
     of exiting: you're already watching, so the label goes on the
     moment everything is actually green.

   - **Actually broken, and waiting won't fix it** — a check failing
     outside your diff (scope contrast shows the wide-scope variant red
     and narrow-scope green — signals a main-branch regression), a
     flaky/infra failure, a security or ownership finding that needs a
     judgment call rather than a code change, or a reviewer who has
     explicitly requested changes (not just "hasn't approved yet"). →
     **Stop here.** Report exactly what's blocking, why it's not just a
     matter of time, and why you won't force it, then exit the skill.

   Only the third bucket ends the skill. The first two both loop back to
   step 1 — one after acting, one after doing nothing.

5. Use `CronCreate` for the `INTERVAL`-minute waits in both looping
   buckets above rather than blocking silently — see "Waiting" below.
   When re-polling a pending-approval gate, keep status updates quiet
   (no repeated "still waiting" noise) until something actually changes.

## Phase B — Label and monitor the SnowCI merge run

1. **Apply the label** (only once Phase A confirms every gate is green):
   ```bash
   gh pr edit $PR --add-label ready_for_merge
   ```
   Tell the user this was done.

2. **Do not push any commit while `ready_for_merge` is present.** Per
   SnowCI's own docs, a new commit after labeling silently breaks the
   merge run — it has to be restarted instead. If you need to push a
   fix during monitoring, remove the label first (step 5 below), push,
   confirm gates are green again (Phase A), then reapply the label.

3. **Poll** every `INTERVAL` minutes:
   ```bash
   gh pr view $PR --json state,mergedAt,labels -q '{state, mergedAt, labels: [.labels[].name]}'
   ```

4. **Interpret:**
   - `state == "MERGED"` → success. Report and exit.
   - `state == "CLOSED"` and not merged → report the PR was closed and exit.
   - `labels` still contains `ready_for_merge`, and either
     `merge_awaiting_prereqs` or `merge_running_validation` is present →
     still in flight, keep polling.
   - `ready_for_merge` label is **gone** and the PR is **not merged** →
     the merge run failed validation. Go to step 5.
   - `merge_awaiting_prereqs` persists for multiple polls with no other
     label progress → recheck prerequisites (step 1 of Phase A) and run
     them through the same three-way classification as Phase A step 4.
     If it's still simply awaiting a pending approval/review, keep
     polling and do nothing. If something regressed (e.g. an approval
     got dismissed by a rebase), fix it if fixable. If it's genuinely
     broken and won't resolve by waiting, stop and report.

5. **Merge run failed — diagnose the real cause, don't just retry:**
   ```bash
   gh pr view $PR --json comments -q '.comments[] | select(.author.login=="jenkins-snowci") | {body, createdAt}' | tail -1
   ```
   This comment names the failing gate and links the SnowCI report for
   the merge-validation branch (which is your PR rebased onto fresh
   `main` — failures here can be a real regression that only surfaces
   post-rebase, not necessarily the same as what Phase A saw). Apply the
   same diagnose method as Phase A step 3 against this build.

   - **Fixable:** remove the label if SnowCI hasn't already
     (`gh pr edit $PR --remove-label ready_for_merge`), apply the real
     fix, commit, push, confirm gates are green (back through Phase A),
     then reapply `ready_for_merge` (step 1) and resume polling.
   - **Not fixable:** report the diagnosis and exit. Do not keep
     reapplying the label hoping it clears on its own — that's exactly
     the kind of blind retry this skill should avoid.

## Guardrails — what "not hacky" means

A fix is legitimate when it changes the actual thing the gate is
checking about your diff. It is **not** legitimate, and must not be
done even under time pressure, to:

- Skip, quarantine, `@Ignore`/`@Disable`, or narrow a failing test just
  to turn it green.
- Use `--no-verify`, `SKIP=<hook>`, or otherwise bypass pre-commit/CI
  locally in a way that doesn't reflect what actually runs in CI.
- Edit `.buildkite/**`, `.github/workflows/**`, ruleset configs, or
  ownership files to relax or route around a gate.
- Add suppress/ignore annotations (lint, semgrep, snyk) whose only
  purpose is silencing the finding rather than fixing the underlying
  issue.
- Force-push in a way that rewrites commits you didn't author, or
  discard someone else's in-flight work on the branch.
- Approve your own PR, dismiss a required review, or otherwise touch
  the review/approval state to manufacture a passing prerequisite.
- Retry a genuinely broken check repeatedly hoping it passes by luck —
  if it's flaky/infra and unrelated to the diff, say so and stop; a
  human can decide whether to request a rerun.

If applying a real fix would require a decision outside pure
code-correctness (architecture choice, a security exception, which
team's ownership rule should apply), that counts as "cannot fix" —
report it and exit rather than guessing.

## Waiting

Prefer `CronCreate` over blocking when the wait exceeds a couple of
minutes: schedule a recurring prompt (interval = `$ARGUMENTS.interval`
or 10 minutes) that re-runs the relevant poll step above for PR `$PR`,
and delete the job (`CronDelete`) once the loop reaches a terminal state
(merged, closed, or an unfixable stop).

`CronCreate` jobs auto-expire after 7 days. A pending-approval wait can
easily outlast that — if the job fires for its last scheduled run and
the gate is still just pending (not broken), recreate the job rather
than treating expiry as a stop condition.
