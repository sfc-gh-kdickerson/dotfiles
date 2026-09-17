---
name: bazel-cache-clean
description: Find and remove Bazel output bases for workspaces (worktrees, repos) that no longer exist on disk. Reclaims disk space from stale caches.
user_invocable: true
arguments: []
---

# Bazel Cache Clean Skill

Finds Bazel output bases whose originating workspace no longer exists on disk, then offers to remove them.

## Workflow

### 1. Locate Caches

Determine Bazel cache locations:
- Check `~/.bazelrc` for `--output_user_root`, `--disk_cache`, `--repository_cache`
- Fall back to standard locations: `/private/var/tmp/_bazel_$USER`, `~/.cache/bazel`

### 2. Map Output Bases to Workspaces

For each hash directory under the output user root:
- Read `DO_NOT_BUILD_HERE` file (contains the workspace path)
- Fall back to grepping `command.log` for `Working directory:`
- Record the mapping: hash -> workspace path

Skip entries where no workspace path can be determined.

### 3. Check Existence

For each mapped workspace path, check if the directory still exists on disk.

Categorize into:
- **Stale**: workspace path does not exist — candidate for removal
- **Active**: workspace path still exists — keep

### 4. Present Summary

Show a table with:
- Size (from `du -sh`)
- Cache hash (abbreviated)
- Original workspace path
- Status: **stale** or **active**

If no stale entries found, report that and stop.

Report total reclaimable space.

### 5. Confirm

Use `AskUserQuestion`:
- If one stale entry: "Remove cache for `<workspace>`? (<size>)" — **"Remove"** / **"Cancel"**
- If multiple stale: "Which stale caches to remove? (~<total> reclaimable)" — **"All stale"** / **"Let me pick"** / **"Cancel"**
- If user picks "Let me pick", use a follow-up `AskUserQuestion` with `multiSelect: true` listing all stale entries

Do NOT remove anything without confirmation.

### 6. Remove

```bash
rm -rf ~/.cache/bazel/<hash>
```

For each confirmed stale entry.

### 7. Report

Concisely list what was removed and total space freed.

## Important

- **Never** remove output bases for workspaces that still exist
- **Always** confirm before any destructive action via `AskUserQuestion`
- The disk cache (`--disk_cache`) and repo cache (`--repository_cache`) are shared across all workspaces — do NOT delete them as part of this workflow (mention their size as FYI)
