---
name: save-visualization
description: >
  Save an HTML visualization (diagram, explainer, interactive chart) into
  snowbox-kdickerson/visualizations and commit it. Use only when the user asks
  to save, keep, or commit a visualization ("save this one", "keep that
  diagram", "add it to my visualizations"). Building or showing a
  visualization is not a request to save it; scratch ones stay uncommitted.
---

# Save a visualization

Saved visualizations live in `/home/repo/snowbox-kdickerson/visualizations/`,
one self-contained `.html` file each.

**Only save when the user asks.** Draft and show visualizations anywhere
(the current project folder, `/tmp`). Do not copy them here, and do not commit
them, until the user says to save that specific one.

## Before saving

The file has to open on its own, from any machine, months later:

- One file. CSS and JavaScript inline. No CDN scripts, web fonts, or fetches.
- No references to local paths, open tabs, or other scratch files.
- A `<title>` and visible heading that say what it shows.
- Facts in it match what you told the user. Fix them in the file before saving.

## Steps

1. Pick a kebab-case name for the subject, not the session:
   `ai-gateway-billing-flow.html`, not `diagram-2.html` or `temp-viz.html`.
2. If that name already exists, it is either a new version of the same
   visualization (overwrite it) or a different one (pick another name). Ask if
   it's unclear.
3. Copy the file into `visualizations/`. Leave the scratch copy alone.
4. Commit only that path. The repo usually has unrelated uncommitted and staged
   changes; never sweep them in:

   ```bash
   git -C /home/repo/snowbox-kdickerson add visualizations/<name>.html
   git -C /home/repo/snowbox-kdickerson commit -m "Save <subject> visualization." -- visualizations/<name>.html
   ```

   The pathspec after `--` makes the commit contain only that file even if other
   files are staged.
5. Do not push unless the user asks.
6. Tell the user the saved path and the commit.

## Opening one

`terminal-browser open <path> --split right` shows it next to the
conversation. If terminal-browser isn't available, copy the file to the Mac
with mac-host `pull_from_cws` and open it in Chrome.
