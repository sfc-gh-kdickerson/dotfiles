---
name: cws-handoff
description: >-
  Stands up a new Snowflake cloud workspace and copies Cursor agent sessions
  plus tmux resurrect state from an old one. Use when creating a new CWS,
  running sf ws create, migrating a cloud workspace, handing off from b823,
  or copying Cursor CLI sessions / tmux resurrect to a new workspace.
---

# CWS handoff

Move from an old Cloud Workspace to a new one. Env comes from published
dev-config + `~/setup.sh`. Session blobs go through `cws-handoff`. Do not
use `sf ws create --from`. Do not rsync `$HOME`. Do not copy `auth.json`.

Script: `~/.local/bin/cws-handoff`. Facts in
[reference.md](reference.md).

## Workflow

Copy this checklist:

```
- [ ] Preflight old box
- [ ] Create (no --from) if needed
- [ ] ~/setup.sh on the new box
- [ ] ~/.snowflake/connections.toml + config.toml
- [ ] Stop agents on the old box
- [ ] cws-handoff OLD NEW
- [ ] leftovers + connect
```

### 1. Preflight

`sf ws ls`. Default old workspace is the running one (b823 was the
source for the first live handoff; 1549 is the destination).

`cws-handoff --dry-run <old>` first. It checks declared repos, extra git
worktrees, and `/src` / `wt-*` checkouts from tmux `last`. **Stop** if any
row is `problem` (dirty, no upstream, or ahead of upstream). Do not create
the new workspace. Do not commit or push unless the user asks. Show the
paths and wait.

Without `--from`, uncommitted or unpushed work dies with the old volume.
`--force-dirty` is an explicit user override, not a default.

Confirm published `configs/kdickerson/cloud-workspaces/default/config.star`
declares the repos you need. A clean create is supposed to clone that
list, not whatever sits on the old disk. Verify dests after create;
personal GitHub repos have been skipped.

### 2. Create

If no destination exists, match the old box. `sf ws create` defaults are
`arm64` and `us-west-1`, not what b823 was:

```bash
sf ws create --arch amd64 --region us-west-2 --customization default
```

Wait until `sf ws list` shows RUNNING. Never pass `--from`. Do not parse
`sf ws show -o json` as a nested object (it is a category/key/value list).
Do not name a zsh variable `status`.

After RUNNING, check that `config.star` dests actually exist. Personal
repos (`~/dotfiles`, `~/.tmux/plugins/tpm`) have been skipped on a clean
create even when declared. Clone them yourself (`/home/repo/<name>` +
symlink, same layout as the old box) before setup.

### 3. Setup

Customization drops `~/setup.sh`; it does not run it. Non-TTY
`sf ws ssh <new> -c '~/setup.sh'` hangs on the trailing `exec zsh -l`.
Either use a TTY or:

```bash
ssh <new> 'sed "\$d" ~/setup.sh | sh'
```

It does home-manager, `git checkout work` + stow, cargo tools, TPM
`install_plugins`, MCP registration. `mdfried` and remote MCP servers
can fail; the rest should still finish.

Before copying, confirm on the new box:

- `~/dotfiles` exists and is on `work`
- `~/.tmux.conf` is a symlink into `dotfiles/.tmux.conf`
- `~/.tmux/plugins/tmux-resurrect` exists
- `~/.tmux/plugins/tmux-mem-cpu-load/tmux-mem-cpu-load` is a built
  binary, not just the cloned repo. TPM's cmake hook fails because
  cmake is not on PATH. The status-right resources pill
  (`scripts/tmux-mem-cpu-pills`) then exits 0 with no output. Build:

```bash
nix shell nixpkgs#cmake nixpkgs#gnumake --command \
  sh -c 'cd ~/.tmux/plugins/tmux-mem-cpu-load && cmake -DCMAKE_BUILD_TYPE=Release . && cmake --build .'
```

If you pushed commits after `sf ws create` started, `git pull --ff-only`
those remotes on the new box. The create clone is a snapshot.

Create drops a stub `~/.snowflake/connections.toml` and no
`config.toml`. Copy both from the old box. Hop through a Mac temp
file; `chmod 600`. Do not print the contents. Do not commit them. Do
not copy `pats.txt` or `logs/` unless asked.

```bash
for f in connections.toml config.toml; do
  scp OLD:~/.snowflake/$f /tmp/cws-$f
  scp /tmp/cws-$f NEW:~/.snowflake/$f
  ssh NEW "chmod 600 ~/.snowflake/$f"
  rm /tmp/cws-$f
done
```

### 4. Handoff

Tell the user to stop `agent` processes on the old box (live SQLite). Then:

```bash
cws-handoff <old> <new>
```

`--all-chats` copies the full chats tree. `--force` copies with agents still
running. `--force-dirty` copies despite dirty/unpushed git. The script
refuses a live copy without those flags. The skill does not pass them unless
the user asked.

Do not implement rsync yourself. The script hops through a Mac temp dir
because macOS openrsync cannot do remote-to-remote and rejects
`--info=stats1`. Do not copy `~/.config/cursor/auth.json`. If the new box
is logged out: `sfid -l cursor` on the Mac.

If the user says copy dirt instead of committing: do that **after** setup,
only the files they care about, then hash-compare against the old tree.
Skip `results/`, zips, `.venv`, watch logs, and huge mixed dirty trees
(ray-upgrade was 404 files). Restow after overlay. Setup/TPM will have
written different bytes for some of the same paths; a copy done before
setup drifts. The new checkout will also grow setup-only dirt (`.claude/`,
`mcp.json`, `cli-config.json`) — that is not a failed copy.

CWS-only **commits** that are not on Mac `origin/work`: push to a side
branch (`work-cws-<oldid>`). Do not force-push `origin/work`.

Remote shells are zsh. `====` is a glob. Use `ssh <ws> bash -s <<'EOF'`.

### 5. Leftovers

Print the script's leftover section. Recreate only the `/src/*` and `wt-*`
cwds that appear in tmux `last`. Do not copy `/src`. Do not recreate every
`sf wt` that happened to exist on the old box.

```bash
sf wt init
sf wt create <name> --repo <repo>   # no --branch
```

`sf wt create` may resume `kdickerson/*` (CWS `origin.fetch` already
tracks those). Other branches (`kaleb/…`) need an explicit fetch because
the clone only tracks `main` + `kdickerson-*`:

```bash
git fetch origin '+refs/heads/<branch>:refs/remotes/origin/<branch>'
git checkout -B <branch> FETCH_HEAD
```

`/home/repo/wt-*` are ordinary git worktrees of `/home/repo/snowml`, not
`sf wt`:

```bash
git -C /home/repo/snowml fetch origin '+refs/heads/<branch>:refs/remotes/origin/<branch>'
git -C /home/repo/snowml worktree add -b <branch> /home/repo/wt-<name> origin/<branch>
```

Then:

```bash
connect <new>
```

First tmux start loads the stowed conf. Continuum restores layout only.
Do not add `agent` to `@resurrect-processes` — that starts a fresh chat and
blocks the assistant hook.

Upstream assistant-resurrect already detects Cursor CLI. If the probe shows
`assistant_sessions` near-empty while agents are running, the `sessionStart`
hook never wrote sidecars (typical for processes started before TPM installed
the hook). Restart those agents once on the old box if you want
`assistant-sessions.json` filled; chats copy still lets `agent resume` work
without it.
