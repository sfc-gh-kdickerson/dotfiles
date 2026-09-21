---
name: setup-snowbox-project
description: >-
  Creates a snowbox project under snowbox-kdickerson/projects by making sf
  worktrees from /home/repo clones and symlinking them into a named folder with
  AGENTS.md. Supports several checkouts of the same repo (LoRA-style
  snowml-client / snowml-container) via named links. Use when setting up a
  project, creating a snowbox project, adding a worktree, running sf wt create,
  or wiring a multi-repo or multi-checkout working directory.
---

# Set up a snowbox project

A **project** is a named folder of notes plus symlinks into `sf` overlayfs
worktrees. The Cursor workspace is `snowbox-kdickerson/projects/`, so agents
edit through those symlinks.

Do not clone, and do not edit `/home/repo/<repo>` (that's main).

## Layout

```
/home/repo/<repo>                          # source clones (leave on main)
/src/<wt>/.worktree/                       # sf overlayfs metadata
/src/<wt>/<repo>                           # isolated checkout
~/.../snowbox-kdickerson/projects/<slug>/
  AGENTS.md
  .gitignore                               # symlink names + .cursor/
  <link> -> /src/<wt>/<repo>
~/.../snowbox-kdickerson/projects/archive/<slug>/
  AGENTS.md                                # finished work; no live worktrees
```

`<link>` is the repo directory (`snowflake`) unless the project needs more than
one checkout of that repo. Then the link is an alias (`snowml-client`) and
lives in its own worktree. One `sf wt` mount is `/src/<name>/<repo>` — it cannot
hold two snowmls.

| Need | Worktrees |
| ---- | --------- |
| Distinct repos | One combined tree: `sf wt create <slug> -r snowflake -r snapps` |
| Same repo twice (LoRA) | Combined tree for unique repos + one sidecar per alias: `sf wt create <slug>-snowml-client -r snowml:branch` |

Older trees may differ (`/home/repo/wt-lora-*`, nested git worktrees, per-repo
`gpu-sat-snowflake` names). Leave them. LoRA notes live in `projects/lora/`.

## Inputs

From the user (infer, then confirm only if a repo, slug, or alias is ambiguous):

1. **slug** — kebab-case folder name
2. **stacks** — each stack is a `/home/repo` clone, optional branch, and a
   **link name** if that clone is used more than once
3. Optional **wt-name** if the slug is long; default is the slug

Same-repo checkouts must get distinct link names. LoRA is the template:
`snowml-client` and `snowml-container`, not two links both called `snowml`.

If `/home/repo/<repo>` is missing, stop and say to clone it there first.

## Create

1. List what already exists: `ls` on `projects/` and `sf worktree list`. Reuse a
   matching worktree; do not duplicate.
2. Run the helper (snowflake overlay create can take a few minutes;
   `block_until_ms` ≥ 180000):

```bash
~/.cursor/skills/setup-snowbox-project/scripts/setup-project.sh \
  [--wt-name NAME] <slug> <spec> [<spec> ...]
```

Specs:

- `repo[:branch]` — symlink `<repo>`, shares the combined worktree `<slug>`
- `link=repo[:branch]` — symlink `<link>`, own worktree `<slug>-<link>`

```bash
# gpu-sat: three different repos
setup-project.sh gpu-saturation-customer-facing snowflake snapps snowtel-collector

# lora: GS plus two SnowML branches
setup-project.sh lora snowflake \
  snowml-client=snowml:kaleb/lora-client/main \
  snowml-container=snowml:kaleb/lora-container/main
```

3. Rewrite `AGENTS.md` with a real one-liner, scope, and stack table. Do not
   leave the TODO stub. Use the link names, not the underlying repo, when they
   differ (gpu-sat is the one-checkout model; lora is the multi-checkout model):

```markdown
# <short title>

Working directory for <one sentence>.

Edit through the symlinks, not `/home/repo/<repo>`.

## Stacks

| Stack | Symlink | Backing |
| ----- | ------- | ------- |
| GS | [`snowflake`](snowflake) | `/src/<slug>/snowflake` (`sf wt create <slug>`) |
| Client | [`snowml-client`](snowml-client) | `/src/<slug>-snowml-client/snowml` (`sf wt create <slug>-snowml-client`) |

## Where to change

- path — why

## Do not touch

- out of scope

## Keep this file high-level

Durable investigation notes stay out of this file.
```

4. After wiring, `git -C <symlink> status` and
   `git -C <symlink> branch --show-current` on each link. Create a feature
   branch **inside that worktree** if the user wants a new one. Never branch or
   commit in `/home/repo/<repo>`.
5. Stage `AGENTS.md` and `.gitignore` in snowbox if that repo is in play. Do not
   commit unless asked. Do not add the symlink targets, zips, or other blobs.

## Add a stack later

Re-run the helper with the new spec (alias if it is a second checkout of a repo
already in the project):

```bash
setup-project.sh <slug> snowml-extra=snowml:branch
```

That creates `<slug>-snowml-extra` and does not disturb existing links. Update
the stack table. `sf wt create` still cannot attach a repo onto an existing
tree.

## Tear down

Only when the user asks to remove a project.

If the notes are worth keeping, move the folder to `projects/archive/<slug>/`,
drop the worktree symlinks, then destroy the trees. Do not `rm -rf` the notes.

```bash
mv /home/repo/snowbox-kdickerson/projects/<slug> \
   /home/repo/snowbox-kdickerson/projects/archive/<slug>
# unlink <link> names inside the archived folder
sf worktree destroy <wt-name>
sf worktree destroy <wt-name>-snowml-client
# ...
```

Delete only when there is nothing to keep (`AGENTS.md` stub, stray zip).

Leftover `/src/*` trees still hold Bazel caches; point at the bazel-cache-clean
skill if disk is the follow-up.

## Guardrails

- Edit via `projects/<slug>/<link>/...`. Git commands use `git -C` on the
  symlink. For LoRA-style stacks that is `snowml-client`, not `snowml`.
- Ignore symlink names and `.cursor/` in the project `.gitignore`. Track
  `AGENTS.md`.
- No large artifacts in the project folder.
- `sf worktree rebase <wt-name>` updates an existing tree onto latest origin;
  rebase each sidecar separately; do not recreate to pull.
- Destroy is the only dangerous step; do not `sf wt destroy` as part of setup.
