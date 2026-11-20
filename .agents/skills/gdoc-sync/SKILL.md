---
name: gdoc-sync
description: Push edits from a local markdown file into one Google Doc tab without wiping comments. Prose edits go through the Natoma Google Docs API as small insert/delete ranges; images, code blocks, and structural changes go through Docs' "Paste from Markdown" driven by the mac-host MCP. Use when the user says "sync/push/apply this to the Google Doc", "update the doc tab from the markdown", "publish notes/x.md to the doc", or links a local .md file to a docs.google.com URL.
---

# Google Doc sync (markdown → doc tab)

The local markdown is the source of truth. You iterate on it with the user, then run this skill to apply only what changed to the doc tab. Never paste the whole document once people have commented: every comment anchored in replaced text is lost.

## Which tool does what

| Change | Route | Why |
|---|---|---|
| Prose edits in paragraphs, headings, list items, table cells; inline formatting; heading renames | Natoma `batch_update_doc` | Minimal insert/delete ranges keep comment anchors, runs headless |
| New paragraphs, headings, same-level list items next to existing prose | Natoma `batch_update_doc` | Inserted by splitting the neighbour paragraph |
| Images, code blocks (new or changed), tables that change shape, list nesting/kind changes, anything else structural | Paste from Markdown via `mac-host` | Docs API rejects `data:` image URIs and can't create native code blocks |
| Deleted blocks | Natoma `batch_update_doc` | |

`scripts/gdoc_sync.py` makes this decision per block. Don't hand-write Docs API requests.

## Files

- `scripts/gdoc_sync.py` (run directly; `uv` resolves `markdown-it-py`):
  - `init MD URL` writes `.<name>.gdoc.json` next to the markdown (doc id + tab id). The URL must include `?tab=`.
  - `plan MD DOC_JSON [--force] [--verify]` writes `~/CWS-outbox/gdoc-sync/<stem>/{plan.json,requests.json,paste-N.md}` and prints a summary.
  - `accept MD` copies the markdown to `.<name>.gdoc-base.md`, the last-synced base.
- `scripts/clip_and_focus.applescript` loads a snippet onto the Mac clipboard and brings the doc tab to the front.

The base file makes the diff three-way. A block the doc changed but the markdown didn't (an accepted suggestion, a teammate's fix) is reported as a warning and left alone. It is not reverted.

## Workflow

```
- [ ] 1. Link (first time only)
- [ ] 2. Fetch the doc tab JSON
- [ ] 3. Plan and review with the user
- [ ] 4. Apply API requests
- [ ] 5. Run paste groups (mac-host)
- [ ] 6. Verify
- [ ] 7. Accept
```

**1. Link.** `gdoc_sync.py init notes/doc.md 'https://docs.google.com/document/d/<id>/edit?tab=t.xxxx'`. If the tab already has content and no base exists, the first plan does a two-way diff against the doc. Show the user that plan before applying it.

**2. Fetch.** Call `natoma_google_drive.get_doc_content` with `{documentId, tabId}`. Large output is saved to a file automatically; use that path. If the JSON comes back inline, Write it to `/tmp/gdoc-sync-<stem>.json`.

**3. Plan.** `gdoc_sync.py plan notes/doc.md <doc.json>`. Before applying anything, tell the user:
- the counts (API edits, inserts, deletes, paste groups);
- every warning. "Doc edited remotely" means offer to pull that text into the markdown. "Conflict" means ask; `--force` overwrites the doc;
- any paste group whose `replaces` text overlaps a comment's quoted text (`read_doc_comments`, `quotedFileContent`), because that comment will lose its anchor.

**4. Apply.** Read `requests.json` and pass the array unchanged to `natoma_google_drive.batch_update_doc`. Set `confirmExternalLink` / `confirmBulkDelete` exactly as `plan.json` → `needs` says. The links come from the user's own markdown. Requests are ordered bottom-up, so send them as one batch and don't reorder or split them. The batch also inserts one marker paragraph (`GDOCSYNC<n>X<hex>`) per paste group.

**5. Paste groups** (skip if `pastes` is empty). This takes over the user's Chrome window for a few seconds, so say so first. Check `mac-host.host_status`; if the Mac is disconnected, stop here and tell the user the markers are waiting in the doc.
1. `mac-host.pull_from_cws` with `remote_path: ~/CWS-outbox/gdoc-sync/<stem>/` and `local_path: /Users/<user>/CWS-inbox/gdoc-sync/<stem>`. Get the Mac home from `host_info`.
2. For each paste in `plan.json`:
   - Run `clip_and_focus.applescript` through `run_applescript`, with `__MD_PATH__`, `__DOC_ID__` and `__TAB_ID__` filled in.
   - `key` `f` + `command`, then `type_text` the marker, then `key` `escape`. Docs leaves the match selected.
   - `key` `/` + `option` opens Docs' menu search. `type_text` "Paste from Markdown", then `key` `return`. The paste replaces the selected marker.
3. Wait about 3 seconds before fetching.

If a paste goes wrong, press `command+z` in the doc, fix it, and retry. Coordinate clicks aren't needed. If you need to look at the screen, follow the `mac-computer-use` skill.

**6. Verify.** Fetch again, then run `gdoc_sync.py plan --verify notes/doc.md <doc.json>`. It must print `verify: CLEAN` (exit 0), and the JSON must not contain `GDOCSYNC`. If something remains, run a normal `plan` and apply the leftovers. Images can't be compared against the doc, so `--verify` treats them as synced.

**7. Accept.** `gdoc_sync.py accept notes/doc.md`. Only accept after a clean verify, because the base drives image change detection and remote-edit protection.

## Gotchas

- Paste from Markdown inserts at the cursor. With the cursor in the middle of a paragraph, the first pasted block merges into that paragraph. Always paste over a selected marker.
- Code block changes are always replaced whole, so syntax highlighting stays right. Comments inside a code block don't survive an edit to that block.
- Paragraphs with smart chips (people, dates, links shown as chips) are skipped with a warning; editing them would drop the chips.
- API edits apply directly even if the doc is in Suggesting mode.
- Inline styles the planner sets: code is Roboto Mono in green, links are underlined in blue (matching what Paste from Markdown produces). Named heading styles come from the doc's theme.
- Ordered and unordered lists aren't distinguished when inserting list items through the API. A new item copies its neighbour's list.
- `mac-host` Chrome `tab_id`s change when a tab navigates, so target by URL.
