---
name: snowbox-project
description: >-
  Manage snowbox projects under snowbox-kdickerson/projects: create, add a
  stack, relink after CWS restart/handoff, snapshot Graphite HEAD, doctor
  symlinks, list, archive, and unarchive. Use when starting a project or
  bugfix, adding a repo/worktree, running sf wt create, wiring
  snowml-client/snowml-container aliases, restoring stacks on a new CWS,
  tearing a project down, or bringing an archived project back. Also use when
  the workspace is a snowbox project and the user asks to create a PR, land a
  one-off fix, or make an isolated change — always add a new worktree in that
  project first.
---

# Snowbox projects

A **project** is notes + `project.json` + gitignored symlinks into `sf`
overlay worktrees. Cursor workspace is `projects/<slug>`, not `projects/`.

Do not clone, and do not edit `/home/repo/<repo>` (that's main). Do not invent
`sf wt` lines or rewrite stack tables in `AGENTS.md`. The CLI is the inventory.

```
~/scripts/project <subcommand>
```

`sf wt create` overlay can take minutes (`block_until_ms` ≥ 180000).

## Command map

| Intent | Command |
| ------ | ------- |
| new project / one-shot | `project new [--title T] <slug>` (empty) then fill stacks with `add`; or pass specs on `new` if you already know them |
| add a repo or second checkout | `project add <slug> <link>=<repo>[:branch]` — unique `link`; overlay is `<slug>-<link>`. Omit `:branch` unless they named one. Unaliased `repo` only while the shared `<slug>` tree does not exist; `--wt-name` only to attach an existing tree |
| one-off PR / isolated change in this project | Always `project add` a new aliased worktree here first, then work only in that symlink. Never reuse an existing stack. |
| CWS restart leftovers / new CWS | `project relink` |
| `gt checkout` moved HEAD | `project snapshot` |
| links look wrong | `project doctor` |
| done, keep notes | `project archive <slug>` |
| resurrect notes | `project unarchive <slug>` then `project relink <slug>` if stacks are needed |
| picker / inventory | `project list --json`; archived: `project list --archived --json` |
| picker: type a new kebab slug on C-p | `project new <slug>` (empty), then connect. Agent in that workspace adds stacks. |
| picker: C-n | `project new <typed slug>` (empty), stay in the list. Use this when the slug fuzzy-matches an existing project or branch. |
| picker: type an archived slug on C-p | `project unarchive <slug>` then connect. Relink stacks separately. |
| picker: C-a | live: `project archive <slug>` then kill the tmux session; archived: `project unarchive <slug>`, create the tmux session, stay in the list |
| picker: C-u on C-p | toggle archived rows in the same list; Enter on one unarchives and connects |

Specs:

- `repo[:branch]` — symlink `<repo>`, shares worktree `<slug>` with other unaliased repos
- `link=repo[:branch]` — symlink `<link>`, own worktree `<slug>-<link>` (required for a second checkout of the same repo)

`:branch` is a git checkout after create, not an `sf -r` flag. `--wt-name` only to attach an existing tree name (`lora-gs`). Same-repo checkouts need distinct link names (`snowml-client`, `snowml-container`). Combined unaliased sharing only works while the shared worktree does not exist yet (`new` with several repos, or the first `add` of unaliased repos). You cannot join an existing overlay later.

**One-off PR / isolated change in this project.** Workspace is `projects/<slug>` and the user asks to create a PR, land a one-off fix, or do any other isolated change that is not the next card on an existing Graphite stack: **always `project add` a new worktree here first**. Do not reuse client, container, GS, or an older sidecar. Do not edit `/home/repo/<repo>`.

1. Read `project.json` for `slug` and which `repo` the change belongs to.
2. Pick a unique kebab `link` that describes the work (`snowml-it-2`, `snowflake-hotfix-foo`).
3. `project add <slug> <link>=<repo>` (omit `:branch` unless they named one). Overlay is `<slug>-<link>`.
4. Do the work, commit, and PR in that new tree only. Report the new symlink, overlay, and branch.

```bash
project add lora snowml-it-2=snowml
```

Adding the tree is the whole setup. Do not read `~/scripts/project`, AGENTS.md, sibling stacks' git, or PRs just to add it. Continuing a named Graphite card (`do G10`, next client card) stays in that stack's tree. Everything else that would produce a PR gets a sidecar.

```bash
project new --title "Customer-facing GPU SM saturation" \
  gpu-saturation-customer-facing snowflake snapps snowtel-collector

project new --title "LoRA Adapter Support" lora snowflake \
  snowml-client=snowml:kaleb/lora-client/main \
  snowml-container=snowml:kaleb/lora-container/main
```

If `/home/repo/<repo>` is missing, stop and say to clone it there first.

## Overlay lifecycle

`sf wt create <name>` always mounts at `/src/<name>/<org>/<repo>`. Upperdir +
`state.json` live under `/home/sfwt` (home volume). You cannot put the tree in
the project folder — keep the symlink.

| Event | What happens |
| ----- | ------------ |
| CWS restart | `/src` mounts die and are remounted from `/home/sfwt`. Symlinks keep working. |
| New CWS (no `--from`) | `/home/sfwt` is gone. Run `project relink`. Only **pushed** branches + snowbox git survive. |
| `sf wt destroy` / `project archive` | Uncommitted overlay dirt is discarded. |
| `project unarchive` | Notes move back to `projects/<slug>`. Overlays stay gone until `project relink`. |

`/src/<name>/AGENTS.md` is generated by `sf` and rewritten on restart. Project
notes stay in `projects/<slug>/`.

## Graphite

One `sf wt` per Graphite stack. Cards switch with `gt checkout` inside that
tree. Do not split one Graphite stack across worktrees. Unrelated same-repo
work (another IT fix, a second snowml PR) is an aliased sidecar, not a new
project and not a Graphite card. Do not wrap `gt create` / `restack` /
`submit` — those stay in the checkout (`gt submit --no-stack` for a single PR).

`project.json` records `graphite.trunk` / `graphite.stack` plus the last
snapshotted `branch`. Relink checks out that branch. `project snapshot` updates
it after you `gt checkout`. Graphite's local parent graph does not survive
handoff; do not try to persist `.git/.graphite_metadata.db`.

## AGENTS.md

`project new` always writes **Setup → Scope**. Empty creates also get
**Setup → Worktrees** (`project add`). Delete the whole Setup section when that
is done. Inventory is `project.json`. No stack table. Do not leave the stub.

Do not rewrite `AGENTS.md` on unarchive. Many archives start with “Archived.
Notes only…” — drop that banner by hand if the project is live again.

## Guardrails

- Edit via `projects/<slug>/<link>/...`. Git uses `git -C` on the symlink.
- Ignore symlink names and `.cursor/` in the project `.gitignore`. Track
  `AGENTS.md` and `project.json`.
- No large artifacts in the project folder.
- `sf worktree rebase <wt-name>` updates an existing tree; rebase each sidecar
  separately.
- Destroy is the only dangerous step. `project archive` is what runs it.
- `project relink` does not run as part of `new` or `unarchive`. Do not create
  overlays as a side effect of reading this skill.
