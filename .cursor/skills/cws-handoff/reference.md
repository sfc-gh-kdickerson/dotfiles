# CWS handoff reference

## What `--from` copies (we do not use it)

Declared git dirt under `/home/repo` and snowflake-repo JetBrains state.
Not `$HOME` extras, not Cursor sessions, not tmux resurrect, not `/src` worktrees.

## Session store

`agent --resume` / `agent resume` reads SQLite under:

```
~/.config/cursor/chats/<md5(cwd)>/<uuid>/store.db
```

`~/.cursor/projects/<slug>/agent-transcripts/` is an export mirror. Copy it;
it is not enough to resume.

Hash is `md5` of the absolute cwd string (no newline), Linux `md5sum`. Same
dest paths (`/home/repo/...`) keep hashes aligned.

## Default copy set

| Path | Why |
|---|---|
| `~/.config/cursor/chats/<hash>/` for cwds in tmux `last` | Resume store |
| `~/.cursor/projects/*/agent-transcripts/` | Human-readable exports |
| `~/.cursor/plans/` | Plan files |
| `~/.tmux/resurrect/last` + its target | Layout |
| `assistant-sessions.json` | `--resume` map once the plugin sees `agent` |
| `~/.snowflake/connections.toml` | Connector profiles. Create writes a stub. |
| `~/.snowflake/config.toml` | Snowflake CLI config. Create does not copy this. |

## Never copy

`auth.json`, `agent-tools`, `ai-tracking`, `~/.cursor-server`,
`~/.local/share/cursor-agent` binaries, `~/.claude`, caches,
`~/.snowflake/pats.txt`, `~/.snowflake/logs/`, git working trees,
historical continuum snapshots, `/src`.

`connections.toml` and `config.toml` are the exception: copy them,
chmod 600, do not print them, do not put them in git.

## Tmux resume wiring

Upstream `tmux-assistant-resurrect` officially supports Cursor Agent CLI
(`agent` and legacy `cursor-agent`). Do not patch the plugin.

- Do **not** put `agent` in `@resurrect-processes`. That re-execs without `--resume` and the assistant hook then skips the pane.
- Detection is not the gap. Session IDs come from the Cursor `sessionStart` hook that TPM writes into `~/.cursor/hooks.json`. The hook writes `~/.local/state/tmux-assistant-resurrect/cursor-<pid>.json`. Agents started before that hook existed have no sidecar; `assistant-sessions.json` stays empty until those processes are restarted once.
- `~/.config/cursor/chats/` is still the resume store. An empty sidecar map does not block `agent resume` / `--resume <uuid>` after the chats tree is copied.

## setup.sh

Dropped by `file(dest = "~/setup.sh")`. Not auto-run. After stow it should
run TPM `install_plugins` (published in `dev-config` #13045). Ends in
`exec zsh -l` — strip that for non-TTY ssh.

`config.star` `git()` dests are not guaranteed. A 1549 create cloned
platform repos under `/home/repo` but skipped `sfc-gh-kdickerson/dotfiles`
and `tmux-plugins/tpm` even though both were declared. Setup assumes
`~/dotfiles` exists.

`tmux-mem-cpu-load` is a CMake project. TPM clones it; the plugin
`.tmux` hook runs `cmake . && cmake --build .` if the binary is
missing. cmake is not in home-manager, so the hook fails and the
cpu/mem island is blank. The CWS id pill (`tmux-cws-pill`) does not
need that binary.

## Mac rsync / ssh

`/usr/bin/rsync` is openrsync 2.6.9. No `--info=stats1`. No
`hostA:path hostB:path`. `cws-handoff` hops through `$TMPDIR/cws-handoff.*`.

`ssh_ws` must keep stdin (probe is `bash -s <<<"$probe_script"`). Use
`ssh -n` only on the dest `mkdir` inside the `find | while` transcript
loop. A global `-n` makes the probe empty: dirty/agent gates no-op, chats
and tmux last are skipped.

Transcript dests are
`~/.cursor/projects/<slug>/agent-transcripts/`. The slug dir does not
exist on a new box. `mkdir -p` before rsync.

## CWS git fetch

Clones set `remote.origin.fetch` to `main` plus `kdickerson-*` /
`kdickerson/*`. `git fetch origin some/other/branch` lands in
`FETCH_HEAD` and does not create `origin/some/other/branch`. Pin it:

```
git fetch origin '+refs/heads/<branch>:refs/remotes/origin/<branch>'
```

Then `worktree add` / `checkout -B` from that ref. `@{u}` will still be
missing until `branch -u`; the dirty probe treats no-upstream as
`problem`.

## Dirty copy (when the user refuses to commit)

Do it after setup + stow. Hash-compare the copied set. New-box extras
from setup are expected. Do not rsync the whole dirty working tree.
