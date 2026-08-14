---
name: find-prs-to-review
description: >
  Finds 1-2 open PRs authored by other people in snowflake-eng/snowml or snowflake-eng/snowflake
  that are strong candidates for Kaleb Dickerson (gh: kaleb-dickerson_snow) to review next.
  Prioritizes PRs where he's already an explicitly requested reviewer, then PRs whose changed
  paths or title tags overlap his recent commit/review history (e.g. batch inference, inference
  server, model registry, model container services), using tight diff scope only as a tiebreaker.
  Use when the user asks "what should I review", "find me a PR to review", "any reviews for me",
  "what's in my review queue", "find something to review", or similar. Not for responding to
  comments on the user's own open PR (that's review-response) — this finds *other people's* PRs
  for the user to review.
user_invocable: true
arguments:
  - name: repo
    description: "Optional repo filter: 'snowml', 'snowflake', or 'both' (default 'both')."
    required: false
  - name: count
    description: "Optional number of PRs to recommend, 1-3 (default 2)."
    required: false
---

# Find PRs to Review

Surface the open PRs in snowflake-eng/snowml and/or snowflake-eng/snowflake that Kaleb is best
positioned to review right now — because he's already been asked, or because the change lands in
territory he's actively working in. Every recommendation must be traceable to a concrete signal:
an explicit review request, a specific overlapping path, or a specific overlapping title tag from
his own recent PRs. Diff size/scope is used only to break ties between otherwise-equal candidates
and is never the stated reason for a pick.

## Step 1 — Build the "context areas" signal

### snowml

Check whether a local checkout is usable:

```bash
SNOWML_DIR=~/repos/snowml
if [ -d "$SNOWML_DIR/.git" ] && git -C "$SNOWML_DIR" remote get-url origin 2>/dev/null | grep -qi "snowflake-eng/snowml"; then
  LOCAL_SNOWML=1
fi
```

**If `LOCAL_SNOWML=1`** — analyze recent authored commits directly (fast, precise):

```bash
# Top touched directories (2 levels deep), last ~120 days
git -C "$SNOWML_DIR" log --since="120 days ago" \
  --author="Kaleb Dickerson" --author="kaleb.dickerson@snowflake.com" \
  --name-only --pretty=format: \
  | sed '/^$/d' \
  | awk -F/ '{ if (NF>=2) print $1"/"$2; else print $1 }' \
  | sort | uniq -c | sort -rn | head -15

# Title bracket-tags he actually uses (matches the [Batch Inference]/[SNOW-XXXXX] convention)
git -C "$SNOWML_DIR" log --since="120 days ago" \
  --author="Kaleb Dickerson" --author="kaleb.dickerson@snowflake.com" \
  --pretty=format:'%s' | grep -oE '^\[[A-Za-z0-9 _-]+\]' | sort | uniq -c | sort -rn
```

Keep the top ~8 directory prefixes as `CONTEXT_DIRS` and the top ~5 tags (lowercased, brackets
stripped) as `CONTEXT_TAGS`.

**If no local checkout (or origin doesn't match)** — build the same signal from the API:

```bash
gh search prs --repo snowflake-eng/snowml --author kaleb-dickerson_snow \
  --state all --limit 30 --json number,title,url,updatedAt

gh search prs --repo snowflake-eng/snowml --reviewed-by kaleb-dickerson_snow \
  --state all --limit 30 --json number,title,url,updatedAt
```

Extract `CONTEXT_TAGS` from the titles the same way (`grep -oE '^\[[A-Za-z0-9 _-]+\]'`). Then, on a
**bounded sample only** (the 8 most recent PRs across both lists — never the full set, to avoid
hammering the API), fetch touched paths:

```bash
gh pr view <number> --repo snowflake-eng/snowml --json files --jq '.files[].path'
```

Reduce those paths to top-level/second-level prefixes the same way as the local case to get
`CONTEXT_DIRS`.

### snowflake (monolith) — API only

```bash
gh search prs --repo snowflake-eng/snowflake --author kaleb-dickerson_snow \
  --state all --limit 30 --json number,title,url,updatedAt

gh search prs --repo snowflake-eng/snowflake --reviewed-by kaleb-dickerson_snow \
  --state all --limit 30 --json number,title,url,updatedAt
```

If the combined result count is **≥ 3**, treat it the same way as snowml: extract any recognizable
title tags/keywords and sample a few `gh pr view --json files` for path prefixes.

If the combined result count is **< 3** (expected — he likely has little footprint here), skip
building a history-derived signal and instead use a fixed keyword fallback list when scanning
candidates in this repo: `spcs`, `container`, `modelserving`, `model serving`, `cortex`,
`inference`, `snowpark container`, `batch inference`, `image builder`, `kaniko`, `vllm`, `ray
orchestrator`. Matching is case-insensitive substring match against candidate PR titles (and body
if quick to fetch). **It is an explicitly acceptable outcome for this repo to contribute zero
candidates** — do not force a pick here.

## Step 2 — Gather open candidates

For each repo in scope (respect the `repo` argument if given):

```bash
gh pr list --repo snowflake-eng/snowml --state open \
  --json number,title,url,author,isDraft,labels,additions,deletions,changedFiles,\
reviewRequests,reviews,createdAt,updatedAt,headRefName,baseRefName,mergeable,statusCheckRollup \
  --limit 100

gh pr list --repo snowflake-eng/snowflake --state open \
  --json number,title,url,author,isDraft,labels,additions,deletions,changedFiles,\
reviewRequests,reviews,createdAt,updatedAt,headRefName,baseRefName,mergeable,statusCheckRollup \
  --limit 100
```

Apply this filter chain, in order, dropping any PR that fails a check:

1. **Draft** — `isDraft == true` → drop.
2. **Bot author** — `author.login` ends with `[bot]`, or is `dependabot`, `renovate`,
   `github-actions`, or any other recognized automation login → drop.
3. **Self-authored** — `author.login == "kaleb-dickerson_snow"` → drop (he can't review his own).
4. **Already reviewed by him** — any entry in `reviews[]` where `author.login ==
   "kaleb-dickerson_snow"` → drop. (He's already looked at it; a fresh open ask that he hasn't
   touched yet is what this skill is for. If it needs a *response* to feedback he already gave,
   that's `review-response`'s job, not this one.)
5. **WIP / do-not-merge markers** — title matches `(?i)\bwip\b|do[- ]not[- ]merge|\[hold\]`, or a
   label named `WIP`/`do-not-merge`/`on-hold` → drop.
6. **Failing CI** — any entry in `statusCheckRollup[]` with `conclusion == "FAILURE"` (or
   equivalent `state == "FAILURE"`) → drop. (Not ready for review regardless of anything else.)
7. **Merge conflicts** — `mergeable == "CONFLICTING"` → drop.

Everything surviving this chain is a candidate.

## Step 3 — Score and rank

Compute, per candidate, three independent signals (used only for ordering — never printed as a
"score"):

- **`requested`** — `1` if any entry in `reviewRequests[]` is a user-type request for
  `kaleb-dickerson_snow`, else `0`. Team-only requests (e.g. `@snowflake-eng/ml-platform`) don't
  count here — this bucket is specifically "asked of *him*."
- **`area_matches`** — count of independent hits: each `CONTEXT_DIRS` prefix that appears among
  the PR's changed file paths (fetch via a small number of targeted `gh pr view --json files`
  calls, not `gh pr list`, since `files` isn't list-safe), plus each `CONTEXT_TAGS`/keyword hit in
  the PR title. Higher count = stronger, more specific overlap.
- **`focused`** — `1` if `changedFiles <= 15` **and** the changed paths concentrate in a single
  top-level directory, else `0`. This is a genuine review-quality signal (a reviewer can hold the
  whole diff in their head and reason about it end to end) — not a difficulty rating, and it never
  appears in the final write-up.

Sort candidates by, in priority order: `requested` (desc) → `area_matches` (desc) → `focused`
(desc, tiebreak only) → `updatedAt` (desc, final tiebreak). Take the top `count` (default 2)
across all in-scope repos combined.

**If nothing survives Step 2 at all** — say so plainly ("no open PRs currently clear the review
readiness bar") rather than relaxing the readiness filters (drafts/bots/failing-CI/conflicts stay
hard filters). **If candidates exist but none has `area_matches > 0` or `requested == 1`** — it's
fine to surface the closest scope-focused ones, but say explicitly that no requested-review or
area-overlap signal was found for them, rather than implying a false connection.

## Step 4 — Present the picks

For each of the top `count` candidates, in rank order:

```
1. **#<number> — <title>** (<repo>)
   <url>
   <one-to-two sentence rationale built only from concrete facts>
```

Rationale rules:
- If `requested == 1`: lead with that fact, then name the specific overlapping area if one
  exists. Example: "You're already requested as a reviewer on this one. It's in
  `model_container_services_deployment/batch_inference`, the area of your last few PRs
  (#4790, #4756)."
- If `requested == 0` but `area_matches > 0`: name the specific path or tag overlap and, if
  useful, the concentration of the diff as a factual scope statement (not an effort statement).
  Example: "This PR is scoped to `model_container_services_deployment/proxy`, overlapping your
  recent `[Inference Server]`-tagged work, and its changes are contained to that one component."
- Never mention time, effort, or difficulty in any form.

## Important

- **Never use the words or near-synonyms:** "easy", "easier", "quick", "quick win", "low effort",
  "low-effort", "simple", "no-brainer", "light lift", "small ask", "shouldn't take long" —
  anywhere in reasoning shown to the user or in the final output. If a draft response contains any
  of these, rewrite it before presenting.
- Diff size/file-count/`focused` is an internal tiebreak signal only. It may inform *which* PR
  gets picked, but the stated reason for a pick must always be requested-reviewer status or area
  overlap — never size or effort.
- Rank by, in order: explicit review request > context-area overlap > scope focus (tiebreak only).
- The failing-CI, conflict, draft, and already-reviewed-by-him filters are hard gates, not scoring
  inputs — never let a strong area-overlap or a requested-reviewer status override them.
- It is a valid, expected outcome for `snowflake` (the monolith) to contribute zero candidates.
  Don't force a pick there just to fill a quota.
- Use `gh` for everything — it's already authenticated as `kaleb-dickerson_snow`. Never suggest or
  fall back to `sfc-gh-kdickerson` (not SSO-authorized for snowflake-eng).
- Bound API usage: `gh pr view --json files` is only for a small, explicit sample of PRs (context
  history sampling in Step 1, and per-candidate area-match checks in Step 3) — never loop it over
  every open PR in a repo.
