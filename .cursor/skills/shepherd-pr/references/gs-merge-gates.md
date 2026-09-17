# GS pull-request gates and merge lifecycle

Use this reference only for `snowflake-eng/snowflake`. Treat live GitHub and
SnowCI state as authoritative when names or behavior evolve.

## Gate layers

### Pull-request basic

`Buildkite - pull-request-basic` runs automatically after a PR-head push. It is
fast feedback for build, lint, static checks, pre-commit hooks, and selected
tests. It does not validate the exact latest-main merge result and does not
replace a qualifying precommit.

Rulesets such as BPR, code ownership, or Precommit-Enforcer can be derived
gates. When one is red, inspect its check-run summary and identify the concrete
upstream failure instead of treating the ruleset as a build job.

### Precommit-Enforcer

`SnowCI: Precommit-Enforcer (New)` is an independent merge prerequisite.
Inspect its check-run `output.summary`. Useful fields include:

- reason/message;
- precommit pipeline, build number, branch, commit, and completion time;
- association kind (`self`, ancestor, or descendant);
- whether the stack cleared the gate;
- whether a stale green was accepted;
- `NO_PRECOMMIT_RUN` or acknowledgement-override presence.

A green enforcer is authoritative even when the qualifying run came from a
descendant stack PR or says `stale green accepted`. Do not spend resources
starting another precommit merely because its build SHA differs from this PR.

If the enforcer reports no qualifying terminal build, start a default
precommit on the PR branch:

```bash
sf ci build start default-precommit -o json
```

The legacy `sf precommit` command is removed. A PR Basic URL is not precommit
evidence. Do not automatically add `NO_PRECOMMIT_RUN` or
`ACK_AND_OVERRIDE_PRECOMMIT_FINDING`; both are explicit policy decisions.

### Human review

Require a current GitHub human approval and no unresolved change request.
Ownership and AI review checks can be additional required checks, but an AI
signoff is not the human approval. A push can dismiss approvals, so inspect
`reviewDecision` after every submitted fix.

### Merge validation

`ready_for_merge` is an active command to SnowCI, not a descriptive label.
After it is added:

1. SnowCI checks approvals, change requests, required checks, and conflicts.
2. If blocked, it adds `merge_awaiting_prereqs` and waits.
3. It creates a temporary branch with latest base plus the PR.
4. It adds `merge_running_validation`.
5. It runs `snowflake--pull-request-merge`.
6. On success it merges to the protected base and removes merge labels.

Removing `ready_for_merge` cancels an active merge request. Any PR-head push
after adding it invalidates that run. Cancel first when possible, push the
verified fix, then start the prerequisite/label sequence again.

On failed validation, SnowCI normally removes merge labels. If
`ready_for_merge` remains, remove it before re-adding it; adding an already
present label does not create a fresh transition.

## Required-check discovery

Do not maintain a hard-coded global list: changed components can introduce
additional required checks. Use live GitHub state:

```bash
gh pr checks <PR> --repo snowflake-eng/snowflake --required \
  --json name,state,bucket,link,workflow
```

Also inspect all failing checks because an important non-required check can
block a derived gate:

```bash
gh pr checks <PR> --repo snowflake-eng/snowflake \
  --json name,state,bucket,link,workflow
```

For rich summaries:

```bash
SHA=$(gh pr view <PR> --repo snowflake-eng/snowflake --json headRefOid -q .headRefOid)
gh api "repos/snowflake-eng/snowflake/commits/$SHA/check-runs?per_page=100"
```

`gh pr checks --watch` exits `0` when current checks pass, `1` when they fail,
and `8` while checks are pending outside watch mode. It watches checks only; it
does not watch comments, labels, approvals, head changes, or PR merge state.

## Failure triage contract

For one concrete Buildkite build, issue the first three SnowCI reads in
parallel:

1. query the build's default failing/new-failure tests;
2. list jobs filtered to `failed,broken`;
3. list build annotations.

Then use job-scoped log search. Do not load full build logs unless targeted
search is insufficient.

Classify before editing:

| Evidence | Verdict | Action |
|---|---|---|
| Failing behavior has a causal path from this PR; baseline passes | PR-caused | Fix, verify, commit, submit |
| Retry/baseline and unrelated-history evidence show intermittent behavior | Flaky | Do not edit PR; establish recovery |
| Same deterministic failure exists on base/main | Broken main | Do not copy unrelated fix into PR |
| Worker, SUT, auth, network, service, or fleet-wide failure | Infrastructure/incident | Stop retries; follow recovery |
| Causality remains plausible both ways | Unclear | Gather focused evidence or ask |

A `new_failure=true` signal is strong evidence, not permission to update an
expected file blindly. Decide whether production behavior or the test
expectation is wrong from the PR's intent and feature-gating invariants.

## G5 validation case

PR `#507604` demonstrated the complete recovery loop:

- `ready_for_merge` moved through awaiting prerequisites and running
  validation.
- Merge build `snowflake--pull-request-merge #121034` found one deterministic
  GS unit-test new failure while baseline retry passed.
- Updating the expected model-garden output made that assertion agree with the
  implementation, but AI review then identified that emitting the environment
  key while the flag was off violated parameter protection.
- The correct final change restored key absence when disabled, updated the
  affected expectations accordingly, pushed a new head, and restarted merge.
- Precommit-Enforcer passed from a descendant G6 default-precommit and
  explicitly accepted stale green, so rerunning precommit for G5 was
  unnecessary.
- An outdated AI blocker thread remained unresolved after its code issue became
  inactive. The shepherd must reply/resolve addressed threads and verify
  `isResolved=true`, including stale threads.

The lesson is to optimize for correct causality and state transitions, not for
turning the first red assertion green as quickly as possible.

## Incident and flake escalation

Primary evidence is SnowCI/Buildkite plus Snowhouse test history. Use Glean or
Slack only after a concrete signature exists. Search narrowly for the test,
step, service, or error signature in:

- `#help-ci`;
- `#es-incident-announce`;
- `#es-incident-discuss`;
- `#snowci-prod-alerts`;
- SnowCI health reports/current canary discussions.

Repeated identical failures across unrelated branches, active PagerDuty/Slack
incident evidence, or broad worker/SUT degradation outweigh a speculative
local code edit. Do not hammer an unhealthy service with retriggers.

## Graphite and worktree constraints

- Use the existing worktree for the PR branch.
- Commit every fix.
- Submit only that PR with `gt submit --no-stack`.
- Do not run `gt restack`, `gt sync`, or a whole-stack submit unless explicitly
  requested.
- Never force-push as part of routine shepherding.
