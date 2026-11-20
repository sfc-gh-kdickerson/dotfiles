# SnowML pull-request gates and merge lifecycle

Use this reference only for `snowflake-eng/snowml`. Treat live GitHub state as
authoritative when names or behavior evolve.

## How merge works

This is ordinary GitHub squash-merge, not SnowCI `ready_for_merge`.

- Required reviews: 1, CODEOWNERS required. Pushes do **not** dismiss approvals.
- Required status checks are **not** strict (behind main is allowed).
- Allowed merge method: squash only. Squash commit title = PR title; body blank.
- Auto-merge is enabled on the repo. Delete the branch on merge.
- Jenkins PR builds abort the previous run on a new push.

Discover required checks live:

```bash
gh pr checks <PR> --repo snowflake-eng/snowml --required \
  --json name,state,bucket,link,workflow
```

On `main` these are the required contexts: `Build Test`, `SnowML Type Check`,
`SnowML Test`. Also inspect all failing checks; a parent `Jenkins` / `SnowML CI`
status is a pointer to those two jobs, not a fourth required name.

Not required unless GitHub says otherwise: Get affected targets, semgrep, Snyk,
AI Code Review.

## Jenkins

Controller:

`https://snow-ml-001.jenkinsdev1.us-west-2.aws-dev.app.snowflake.com`

Typical jobs linked from GitHub statuses:

| GitHub context | Jenkins job | What it is |
|---|---|---|
| SnowML Test | `SnowMLRunTestsPipeline` | `mode=merge_gate` affected `short_regress` tests on prod3 |
| SnowML Type Check | `SnowMLTypeCheck` | mypy / bazel `--config=typecheck` |
| Jenkins / SnowML CI | `SnowML/snowml/PR-<N>` | parent; fans out to the two jobs above |

Parse a check `link` into MCP arguments by stripping `/job/` segments. Examples:

```text
https://snow-ml-001.jenkinsdev1.us-west-2.aws-dev.app.snowflake.com/job/SnowMLRunTestsPipeline/220560/
  controller_url: https://snow-ml-001.jenkinsdev1.us-west-2.aws-dev.app.snowflake.com
  job_path: SnowMLRunTestsPipeline
  build_number: 220560

https://snow-ml-001.jenkinsdev1.us-west-2.aws-dev.app.snowflake.com/job/SnowML/job/snowml/job/PR-6827/12/
  job_path: SnowML/snowml/PR-6827
  build_number: 12

https://snow-ml-001.jenkinsdev1.us-west-2.aws-dev.app.snowflake.com/job/SnowMLTypeCheck/211371/
  job_path: SnowMLTypeCheck
  build_number: 211371
```

First `GetDynamicTools` with `namespace: jenkins`. Then this parallel
`CallDynamicTool` batch for one failed build:

```text
namespace: jenkins
1. toolName: jenkins_get_build_details
   arguments: { controller_url, job_path, build_number }
2. toolName: jenkins_get_build_artifacts
   arguments: { controller_url, job_path, build_number }
```

Then `jenkins_get_build_stage_logs` for failed stage IDs, or
`jenkins_get_build_console_log` with a tight `search_text` (e.g. `FAILED|Error`)
and read the returned `log_file_path` rather than pasting the whole log.

There is no Jenkins rebuild tool. Do not empty-commit to bounce the PR job.
Feature-area JUnit check names like `Tests / Run Tests in Parallel / feature_model_registry`
are children of `SnowML Test`; diagnose the pipeline build, not the GitHub
wrapper name.

## GitHub Actions

`Build Test` is `.github/workflows/build_test.yml` (wheel/build on the PR).

```bash
gh run list --repo snowflake-eng/snowml --branch <headRefName> --limit 10
gh run view <run_id> --repo snowflake-eng/snowml --log-failed
```

Rerun a failed Actions run with `gh run rerun <run_id> --failed` only when the
verdict is infrastructure and the same SHA should be retried. Do not rerun a
deterministic PR-caused failure hoping it will pass.

## Local reproduce

Pre-commit runs on `git commit` (pyupgrade, isort, black line-length 120,
flake8, darglint, buildifier, typos). If a hook rewrites files and the commit
fails, fix and make a new commit.

```bash
# Type check (matches SnowML Type Check)
bazel build --config=typecheck <target>

# Unit tests — pick the config the target needs (core vs ml/torch/llm)
bazel test --config=core //snowflake/ml/model/_client/model:batch_inference_job_specs_test
bazel test --config=ml //snowflake/ml/model/_client/ops:service_ops_test

# Merge-gate subset
./ci/RunBazelAction.sh test -m merge_gate
```

`py_test` targets need a `feature:` tag. Add `short_regress` only when the test
belongs in the merge gate (fast, stable, high-signal).

## Failure triage

| Evidence | Verdict | Action |
|---|---|---|
| Failing behavior has a causal path from this PR; baseline passes | PR-caused | Fix, verify, commit, push |
| Retry/unrelated-history evidence shows intermittent behavior | Flaky | Do not edit PR; establish recovery |
| Same deterministic failure exists on main | Broken main | Do not copy an unrelated fix into PR |
| Worker, auth, network, prod3, or fleet-wide failure | Infrastructure/incident | Stop retries; follow recovery |
| Causality remains plausible both ways | Unclear | Gather focused evidence or ask |

Search flakes in `#snowml-alert-notifications` after you have a test signature.
Quarantine files live under `ci/targets/quarantine/`; do not add this PR's test
there as a merge shortcut.

## Public-repo constraints

SnowML ships as public `snowflake-ml-python`. Keep GS parameter names, planner
internals, Snowflake-only types, and internal host/Jenkins URLs out of code,
comments, tests, and changelog.

## Merge command

When section 6 of the skill says merge:

```bash
gh pr merge <PR> --repo snowflake-eng/snowml --squash --auto --delete-branch
```

Do not use `ready_for_merge`, `gh pr merge --admin`, merge commits, or rebase
merge. Container diffs may still want a manual image-override run on
`BuildSnowML`; call that out, do not invent a Jenkins trigger.
