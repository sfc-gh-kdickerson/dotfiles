---
name: mac-computer-use
description: Drive the user's Mac from the cloud workspace through the mac-host MCP. Covers seeing (window screenshots with OCR), reading Chrome pages (AppleScript `execute javascript`, same-origin API fetches), scrolling, switching tabs, and real mouse clicks via CoreGraphics. Use when the user says "control my browser/Mac", "look at my Chrome tab", "take a screenshot", "click X", "check the dashboards I have open", or otherwise asks the agent to see or act on their laptop.
---

# Mac computer use (mac-host MCP)

All of this goes through `CallDynamicTool` with namespace `mac-host`. `run_applescript` is unrestricted code execution on the user's laptop: read freely, but act only as far as the user asked.

## Ground rules

- **Hands-off by default.** Read and screenshot. Do not type into fields, submit forms, send messages, or change settings unless the user asked for that exact action.
- **The user is using the machine too.** `activate` and `set active tab index` take focus away from them. Prefer reading a tab by index without activating it. If the user switches tabs mid-task, stop and re-check before acting.
- **Clean up.** Undo anything you changed (injected CSS, changed URL params, opened tabs) or reload the tab when done, and say so in the summary.
- If a host tool errors, check `host_status` before retrying (the laptop may be asleep or disconnected).

## Tools

| Tool | Use |
|---|---|
| `list_windows` (`app: "Google Chrome"`) | Get `window_id` and bounds. Re-run whenever the user may have moved or resized things. |
| `screenshot` | `target: "window", window_id: N, include_ocr: true`. `region` for small details. |
| `run_applescript` | Everything else: Chrome tabs, JS in pages, clicks. `timeout_seconds` max 120. |
| `open_url` | Opens a new Chrome tab. |
| `push_to_cws` / `pull_from_cws` | Move files between Mac and CWS (for big outputs, captures). |
| `clipboard_get` / `clipboard_set`, `notify` | As named. |

Do not use `target: "frontmost_window"`. It captures whatever the user has focused (usually their terminal).

## Seeing: screenshots

1. `list_windows` → note `window_id` and `bounds` (x, y, width, height in screen points).
2. `screenshot` the window with `include_ocr: true`. OCR text is noisy (letters swapped, `$` for `s`) but good for finding labels and numbers. Read the image for layout.
3. The returned image is downscaled (a 1678-pt window came back 1024 px wide). **scale = window width (pt) / image width (px).** You need this for clicks.
4. For dense tables or small text, capture a `region` around the area instead of the whole window.

## Reading Chrome pages (preferred over screenshots)

Requires Chrome → View → Developer → **Allow JavaScript from Apple Events** (already on for this user).

```applescript
tell application "Google Chrome" to set r to execute (tab 39 of window 1) javascript "document.body.innerText.slice(0, 5000)"
return r
```

- Target `tab N of window 1` directly; no need to activate it.
- List tabs first; indexes shift when tabs open or close, so match on URL:

```applescript
set out to ""
tell application "Google Chrome"
  repeat with i from 1 to (count of tabs of window 1)
    set out to out & i & " | " & (title of tab i of window 1) & " | " & (URL of tab i of window 1) & linefeed
  end repeat
end tell
return out
```

- **Same-origin APIs with the user's SSO session:** a synchronous XHR from a tab on that origin returns JSON the CWS can't fetch itself (e.g. Grafana `/api/dashboards/uid/<uid>`):

```javascript
(function(){var x=new XMLHttpRequest();x.open('GET','/api/dashboards/uid/UID',false);x.send();return x.status+'\n'+x.responseText})()
```

`execute javascript` does not await promises; use sync XHR or stash the async result on `window.__r` and read it in a second call.

- **Large results:** write them to a Mac file from AppleScript, then `push_to_cws`:

```applescript
set f to open for access (POSIX file "/tmp/out.json") with write permission
set eof of f to 0
write r to f as «class utf8»
close access f
```

- Quoting: the JS goes inside an AppleScript string, so use single quotes in JS and escape `\` as `\\`. Inside a `run_applescript` JSON payload that becomes `\\\\n` for a JS `\n`.

## Scrolling

`window.scrollTo` does nothing on app-style pages (Grafana, Snowsight). Find the real scroll container once, keep it on `window`, then set `scrollTop`:

```javascript
(function(){var els=[...document.querySelectorAll('*')].filter(e=>{var s=getComputedStyle(e);return (s.overflowY=='auto'||s.overflowY=='scroll')&&e.scrollHeight>e.clientHeight+50});els.sort((a,b)=>b.scrollHeight-a.scrollHeight);window.__sc=els[0];return els[0]?els[0].scrollHeight+' '+els[0].clientHeight:'none'})()
```

Then `window.__sc.scrollTop=600`, wait 3–5 s for lazy panels, screenshot. To jump to a panel: find its heading element and set `scrollTop` to its offset inside `__sc`.

**Cross-origin iframes** (Snowsight Streamlit apps): JS can't read or click inside. To see more of one, make the iframe and its ~4 parent elements `height:6000px` from the parent page, then scroll the parent's scroll container as above and screenshot. Reload the tab afterwards.

## Clicking

**Prefer DOM clicks** on same-origin pages: `document.querySelector(...).click()` via `execute javascript`. Use coordinates only for things JS can't reach (cross-origin iframes, canvas, Chrome's own dialogs like "Page Unresponsive").

If the MCP ever offers a DevTools-Protocol click (`Input.dispatchMouseEvent`), use it over everything below: it takes page coordinates, works in background tabs and cross-origin iframes, and doesn't move the user's cursor.

Chrome doesn't expose page elements to the macOS accessibility tree by default: System Events only sees the toolbar and tab strip, and can't set `AXManualAccessibility` to turn it on. So there is no click-by-element-name through System Events.

**`System Events` `click at {x, y}` does not work on web content.** It's an accessibility "press" that Chrome's page content ignores. It returns success and nothing happens. This is not a permissions problem.

**Real clicks: CoreGraphics mouse events through JXA.** Install the helper once per Mac boot (it lives in `/tmp`):

```applescript
set js to "function run(argv) {
  ObjC.import('CoreGraphics');
  var p = $.CGPointMake(parseFloat(argv[0]), parseFloat(argv[1]));
  var mv = $.CGEventCreateMouseEvent($(), 5, p, 0); $.CGEventPost(0, mv);
  delay(0.15);
  var d = $.CGEventCreateMouseEvent($(), 1, p, 0); $.CGEventPost(0, d);
  delay(0.05);
  var u = $.CGEventCreateMouseEvent($(), 2, p, 0); $.CGEventPost(0, u);
  return 'clicked ' + argv[0] + ',' + argv[1];
}"
set f to open for access (POSIX file "/tmp/mac-click.js") with write permission
set eof of f to 0
write js to f as «class utf8»
close access f
return "ok"
```

Event types: 5 = mouse moved, 1 = left down, 2 = left up. Coordinates are **global screen points**.

**Computing the point:**

1. Screenshot the window and find the target at image pixel (px, py).
2. Offset in points: `ox = px × scale`, `oy = py × scale` (scale from the Seeing section).
3. Screen point = window origin + offset. **Read the bounds in the same script as the click** (the user moves and resizes the window), and abort if the size changed since the screenshot:

```applescript
tell application "Google Chrome" to set b to bounds of window 1
set x0 to item 1 of b
set y0 to item 2 of b
set w to (item 3 of b) - x0
if w is not 1678 then return "abort: width is now " & w
do shell script "osascript -l JavaScript /tmp/mac-click.js " & (x0 + 927) & " " & (y0 + 254)
```

4. Screenshot again to confirm the click did what you expected. A miss of ~20 pt usually means a stale scale or bounds.

`bounds` is {left, top, right, bottom}. Return items individually; `bounds as string` comes back garbled.

## Gotchas

- **Background tabs render blank** until activated; give them 5–15 s after `set active tab index`.
- **Heavy pages hang `execute javascript`** (the AppleScript times out) and can raise Chrome's "Page Unresponsive" dialog. Click "Exit Page" with a CoreGraphics click and use another data source. Grafana boards: use the Grafana MCP with PromQL instead of the browser.
- **Changing a tab's URL** (e.g. Grafana `from=now-24h`) changes the user's view. Save the original URL and set it back.
- Opening an iframe's `src` as its own tab usually renders blank (it needs the parent's auth handshake).
- AppleScript handlers (`on min(...)`) can't be called inside a `tell` block without `my`; just inline the math.
- The Chrome window id from `list_windows` is stable, but tab indexes and window bounds are not.
