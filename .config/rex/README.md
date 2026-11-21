# Rex with familiar tmux controls

This directory is tracked in `~/dotfiles/.config/rex` and linked to
`~/.config/rex` with GNU Stow. From `~/dotfiles`, link just Rex with:

```sh
stow --target="$HOME" --ignore='^(?!\.config(?:$|/rex(?:$|/))).*' .
```

Local appearance backups remain available in `appearance-backups/` and are
excluded from Git.

Bindings are in `init.lua`, based on `~/.tmux.conf` and the running tmux keymap.
The prefix is **Ctrl+Space**. Press it, release it, then press the next key.

| After the prefix | Action |
| --- | --- |
| Ctrl+Space | Send a literal Ctrl+Space to the terminal |
| c | New tab |
| n, Ctrl+n / Ctrl+p | Next / previous tab |
| p | Project picker (snowbox projects, sessions, zoxide) in a popup |
| e | Agent picker (Cursor agents, ready first) in a popup |
| 1–9 | Select tab by number |
| , | Rename tab |
| $ | Rename session |
| o | Session picker |
| l | Toggle to the last session visited through session shortcuts, across hosts |
| g | Open lazygit in a centered 70% × 70% popup in the source directory |
| [ | Enter native copy mode |
| ( / ) | Previous / next session in order |
| d | Close the app window; server session remains running |
| % / " | Split right / down, inheriting the working directory |
| h / j / k | Focus left / down / up |
| Arrow keys | Focus a pane in that direction |
| Ctrl+arrow | Resize toward that direction by 5% of the split |
| z | Toggle pane zoom |
| x / X | Close current pane or tab / close tab |
| Ctrl+l | Send Ctrl+l to the terminal |
| R | Reload Rex configuration |
| : / ? | Open Rex's command palette |

Option+Backspace and Shift+Enter also retain the custom escape sequence and
literal newline bindings from Ghostty. Rex's other shortcuts remain available.

**Ctrl+H/J/K/L**, without the prefix, focus the left/down/up/right Rex pane.
When Vim, Neovim, fzf, or nested tmux is in the foreground, the keys go to that program instead,
as with the tmux navigator plugin. The Neovim plugin configuration adds the return
handoff: in normal mode, navigate editor splits first, then Rex panes at an edge.
This activates only inside Rex when Neovim is not itself inside tmux. Restart
Neovim to load the integration; prefix+arrows always target Rex directly.
Use prefix+Ctrl+L to clear the shell, since plain Ctrl+L now navigates right.
**Ctrl+P** toggles a centered scratch-shell popup (70% wide, 70% high).
Each window has its own scratch shell, starting in the source pane's directory.
Hiding it keeps the shell and running commands alive; showing it in that window
again reuses it. Use `exit` or prefix+x to close
the popup shell; prefix+X closes the whole tab.
**prefix+g** opens lazygit in a separate popup using the source pane's directory.
Quit lazygit with `q` to close it and return to the underlying pane. Repeating
prefix+g while that tab's lazygit popup is open focuses it rather than duplicating it.
**prefix+p** and **prefix+e** run `~/scripts/rex-picker` in a popup on the focused
session's host: tmux-picker's fzf views and the `~/.config/tmux-picker` plugins,
with `~/.config/rex-picker/lua/tmux_picker/tmux.lua` talking to Rex instead of tmux.
Picking a project opens or creates its session and switches the window to it;
C-n creates, C-a archives (and closes the session), C-e/C-p/C-t/C-x switch views.
In the agents view, C-s sends a message to the selected agent without leaving.
tmux keeps its own tmux-picker; both read the same plugins.
**prefix+[** enters Rex's native copy mode in the focused terminal.
Use `h/j/k/l` to move, `/` to search, `v` for character selection, `V` for lines,
and Ctrl+V for rectangular selection. Press `y` or Enter to copy to the system
clipboard and exit, or `q` / Esc to exit without copying. Use Cmd+V to paste.
Rex's default Cmd+Shift+C shortcut also enters copy mode.
Programs launched through a noninteractive shell wrapper can appear as the shell
in Rex's foreground-process information; editor/fzf passthrough detection may
then miss them. Direct launches and fzf from an interactive shell were checked.

## Appearance

Rex Settings uses JetBrainsMono Nerd Font at 16 pt, ligatures off, dark appearance,
compact pane headers, and top tabs. The active pane has a Catppuccin yellow border
at 82% opacity, with a fade transition when focus changes.

The selected `Catppuccin Mocha` theme uses Mocha's base background (`#1e1e2e`),
text (`#cdd6f4`), and a slate selection (`#45475a`) with light text. Inactive panes
dim their content only, keeping backgrounds consistent. Whole-window fading is
off so switching to another app does not dim the terminal further.

Theme source files are in `themes/` beside this document. The previous
`Catppuccin Mocha (Ghostty)` theme with its black background is still available
in Settings > Themes. A snapshot of the previous appearance preferences is under
`appearance-backups/20261101-113158/`.
Copy on selection remains off and the cursor remains a blinking block.

Adjust the focus border and fade mode under Settings > Interface > Customize
pane behavior. The current build offers Off, Surface, Content, and Surface &
Content fade modes; the pane-content fade strength has no exposed slider.

## Remaining differences

- `prefix+l` tracks history per app client through `prefix+o`, Cmd+K, and the
  `prefix+(`/`prefix+)` cycle shortcuts, including remote sessions on connected hosts.
  It skips sessions that are closed or whose host cannot be reached.
  It uses native session cycling to reach the target across hosts; this Rex
  build restricts `session.select` to the current host.
  When a remote session is active, it queries this Mac through the bundled CLI
  and local socket because Rex routes Lua API calls to the active remote host.
  Picker cancellation leaves history intact.
  Mouse-only session switches are not reliably tracked. History resets on config
  reload; with exactly two sessions across connected hosts, `prefix+l` can
  immediately toggle between them.
- Ctrl+arrow resizing needs the prefix each time. Rex has no tmux repeat-time
  timer, and its amount is a percentage rather than five terminal cells.
- The worktree manager (`Ctrl+;`), lock (`prefix+t`), and other tmux plugin
  bindings are not ported.
- The custom status bar, CPU/memory/git pills, peach pane labels, 60% window
  opacity, Ghostty cursor shader, exact padding, and pixel line-height adjustment
  are not reproduced. Rex's own session persistence does not reproduce
  tmux-resurrect/continuum restoration across a server restart.

## Validation

`rex config check` passed, configuration reload succeeded, and keymap validation
against this app's advertised actions returned no diagnostics. In a temporary
tab, Ctrl+Space sequences were exercised for new tab, split, pane focus, resize,
zoom, and closing panes/tabs. The temporary tab was closed after verification.
The Neovim handoff was also checked in an isolated live Rex session with four
editor splits: all four Ctrl+H/J/K/L keys moved within the editor first and into
a Rex pane at the editor edge. That test session was removed afterward.
The full user Neovim configuration was checked as well: all four normal-mode
navigation mappings load the Rex handoff, physical app keystrokes pass into and
out of Neovim, nested tmux keeps its keys and Neovim integration, and interactive
fzf receives its Ctrl+J navigation. An obsolete blink.cmp `formatting` option was
removed; colorful-menu rendering already uses `completion.menu.draw`.
Last-session switching was exercised with three live sessions to distinguish
visit history from list order. Picker cancellation preserves history, and
removed sessions are skipped. The temporary history-check session was removed.
Cross-host switching was checked between this Mac and `rex-pi` in both directions.
A temporary fourth session verified switches requiring two native cycling steps;
that test session was removed. Configuration checking reported no diagnostics.
The scratch popup was checked in an isolated two-window session: each window
keeps its own shell PID and source directory across hide/show, and opening one
does not move the other. Hiding restores each window's source focus and zoom.
The old shared popup is adopted by its own window. The test session was removed.
The lazygit popup was checked in a temporary Git repository: it opened at the
configured size, displayed that repository's files, reused an existing popup,
and closed on `q` while restoring the source pane. It uses the installed
`~/.nix-profile/bin/lazygit` executable because Rex's default PATH omits it.
