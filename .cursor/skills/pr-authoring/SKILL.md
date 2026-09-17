---
name: pr-authoring
description: >
  Draft or update a pull request's title and description from the branch diff.
  Use whenever a PR needs a title/description written or refreshed — "write the
  PR description", "open a PR for this", "draft a PR", "update the PR body", or
  right after finishing a branch's worth of changes and moving to open one. Not
  for reviewing incoming feedback (see review-response) and not for writing
  commit messages (see the git commit workflow) — this is specifically the PR's
  own title and body. Prefer concrete examples in the description when they
  help a reviewer understand the change.
user_invocable: true
---

# PR Authoring

Write a title and description that help a reviewer understand the change. Cover
what shipped and why it shipped. When an example would make that faster to grasp
(new SQL, API, flag, layout, before/after behavior), include one. There is no
required section layout.

## Step 1 — Gather the diff

This skill only composes the title/description. It does not pick the base
branch. Use whatever base is already in play:

- **Existing PR on this branch:** `gh pr view --json number,title,body,url,baseRefName`,
  then `gh pr diff` against that PR's real base. This is the usual case when
  refreshing a description.
- **No PR yet:** diff against wherever the branch already tracks/forked from —
  e.g. `git merge-base @{u} HEAD` if there's an upstream, otherwise whatever the
  branch was created from — and `git log` / `git diff` from that point to
  `HEAD`. Don't hardcode a branch name.

Read the full diff, not just commit messages. Commit messages describe intent at
the time; the diff is what is actually shipping.

When updating an existing PR, read the current body first. Keep anything that
still helps (especially examples) unless it is now wrong. Don't rewrite a good
description into a thinner template.

## Step 2 — Title

Default to a conventional-commit title: `type(scope): concise summary`. Omit
`(scope)` if it wouldn't add information. Imperative mood, lowercase after the
colon, no trailing period.

| Type | When |
|---|---|
| `feat` | New user-facing capability or behavior |
| `fix` | Bug fix |
| `refactor` | Internal restructuring, no behavior change |
| `perf` | Performance improvement, no behavior change |
| `docs` | Documentation only |
| `test` | Tests only |
| `build` | Build system, dependencies, packaging |
| `ci` | CI/CD config |
| `chore` | Tooling/config with no production-code impact |
| `style` | Formatting only |
| `revert` | Reverts a previous change |

Pick the type that matches the PR's primary intent. If the repo already uses a
different title style (ticket IDs, no conventional-commit prefix, etc.), follow
that instead.

If the diff mixes unrelated kinds of change badly enough that no single type is
fair, say so and suggest splitting rather than forcing a label.

## Step 3 — Description

Write for a reviewer who has not been in the conversation. Aim for:

- **What changed**, named specifically (files, functions, behaviors) rather than
  a restatement of the title.
- **Why**, from conversation context, a linked ticket, or what the diff itself
  implies. If you cannot recover a real motivation, ask instead of inventing one.
- **Examples** when they apply: a short SQL snippet, API call, config/flag,
  input/output, or before/after that shows how the new path is used. Skip them
  when the change is obvious from the bullets (typo, rename, pure test wiring).

Shape the body to the change. Headings like What / Why / Examples are fine when
they help; they are not required, and empty sections should not be invented.
A one-line PR can be one or two sentences. A behavior change usually wants an
example.

Leave out a Test plan section unless the repo template requires one or there is
something a reviewer would actually run that isn't already obvious from the
diff. Don't pad with a generic checklist.

## Step 4 — Create or update the PR

Apply it directly:

- **No existing PR:** push the branch if it has no upstream yet, then
  `gh pr create --title "..." --body "$(cat <<'EOF' ... EOF)"`.
- **Existing PR:** `gh pr edit <number> --title "..." --body "..."` to replace
  the description.

Report the title used and the PR URL.

Base branch selection is not this skill's concern — compose against the diff
already in scope from Step 1.
