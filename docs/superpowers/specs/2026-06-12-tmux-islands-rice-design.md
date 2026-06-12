# tmux "Islands" Rice — Design Spec

**Date:** 2026-06-12
**Scope:** A (fresh visual skin) + D (cohesion with the rest of the desktop). No new information modules, no workflow/cockpit changes.
**File touched:** `~/dotfiles/.tmux.conf` (symlinked to `~/.tmux.conf`). No new plugins.

---

## 1. Goal

Rebuild the tmux status bar, pane borders, popups, and message styling so the terminal speaks the **same visual language as sketchybar** — floating rounded "islands," accent-colored icons with calm neutral labels, and peach as the single focus accent. The result should read as one coherent Catppuccin Mocha desktop (AeroSpace + sketchybar + tmux + nvim), not four separately-themed tools.

This is purely aesthetic. We are explicitly **not** adding clock/CPU/battery modules (that's sketchybar's job) and **not** surfacing Claude/PR/worktree status in the bar.

## 2. The cohesion target (sketchybar's grammar)

From `~/.config/sketchybar/{variables.sh,sketchybarrc}`:

- **Islands / brackets:** items grouped into floating rounded rectangles, `background.color = base (#1e1e2e)`, `corner_radius 7`, soft drop shadow, on a transparent bar.
- **"Calm the rainbow":** each item's **icon** carries an accent color; **labels** are neutral `subtext1 (#bac2de)`. Not every segment a different bright color.
- **Focus accent:** `peach (#fab387)` for the active workspace number, sitting on a `surface1 (#45475a)` chip.
- **Font:** `MesloLGS NF` Bold.

The current tmux bar violates all three: flat colored text on plain `│` separators, every segment a different bright color, no island shape.

## 3. Design decisions (approved)

| Decision | Choice |
|---|---|
| Segment language | **Islands** — `surface-0` pills with rounded caps (U+E0B6 / U+E0B4) |
| Accent discipline | **Per-function accent icons** + neutral `subtext-1` labels |
| Active window | `surface-1` chip + **peach** bold index (mirrors aerospace spaces) |
| Prefix-held tell | Session pill fills **peach**, text → base |
| Zoom indicator | **Pink** pill, right side |
| Pane borders | Keep current structure; active = peach, inactive dimmed to crust. No titles. |
| Popups | Unified rounded line; **per-tool accent** color retained |
| Messages / copy-mode | Themed to `surface-0` / peach |
| Palette | Stay Catppuccin Mocha |
| Plugins | None added |

## 4. Palette & glyph reference

Define any missing palette user-options explicitly. The catppuccin plugin exposes most `@thm_*`, but we must **not** assume `@thm_subtext_1`, `@thm_surface_1`, `@thm_text`, `@thm_overlay_2` exist — set them from the hex below if absent. Values match `sketchybar/variables.sh` so the two configs share one conceptual source of truth:

```
base     #1e1e2e   surface_0 #313244   subtext_1 #bac2de
mantle   #181825   surface_1 #45475a   overlay_0 #6c7086
crust    #11111b   surface_2 #585b70   overlay_2 #9399b2
text     #cdd6f4
green #a6e3a1   maroon #eba0ac   blue #89b4fa   peach #fab387
pink  #f5c2e7   mauve  #cba6f7
```

Glyphs (all already in use except the caps):

```
LEFTCAP   = U+E0B6   (left half-circle, solid)
RIGHTCAP  = U+E0B4   (right half-circle, solid)
session   = U+EBC8
command   = U+EA85
git       = U+F062C
zoom      = U+F00E
```

## 5. Per-surface spec

### 5.1 Pill helper pattern

A pill is built from three pieces over a **transparent** (`bg=default`) bar:

```
#[fg=PILL,bg=default]LEFTCAP #[fg=ACCENT,bg=PILL]ICON #[fg=#bac2de,bg=PILL]LABEL #[fg=PILL,bg=default]RIGHTCAP
```

where `PILL = surface_0 (#313244)` for normal segments. The cap glyphs are the pill color on a transparent background, so they render as rounded ends floating on the terminal background. (Consider a small tmux format helper / shell snippet to avoid repeating this markup for every segment.)

### 5.2 status-left

- **Session pill:** icon (U+EBC8) in **green**, label `#S` in subtext-1, on surface-0.
  - **Prefix held** (`#{client_prefix}`): the whole pill fills **peach**; icon + label become **base** color, bold.
- **Command pill:** icon (U+EA85) in **maroon**, label `#{pane_current_command}` in subtext-1, on surface-0.

### 5.3 window list (centered, `status-justify absolute-centre`)

- **Current window:** `surface-1` chip pill — index in **peach bold**, name in **text**. Direct analog of the focused aerospace space (surface-1 chip + peach number).
- **Other windows:** flat `overlay-0` text, no pill. Keep the existing format `#I#{?#{!=:#{window_name},Window},: #W,}`.
- Keep the existing `automatic-rename-format "Window"` convention (index-only when unnamed).

### 5.4 status-right

- **Git pill** (only inside a work tree — keep the existing `git rev-parse` guard): icon (U+F062C) in **blue**, branch in subtext-1, on surface-0.
- **Zoom pill** (only when `#{window_zoomed_flag}`): icon (U+F00E) + `zoom` on a **pink** pill, text in base.

Verify `status-left-length` / `status-right-length` (currently 100) still accommodate the wider pill markup; bump if truncation appears.

### 5.5 pane borders

Keep current behavior — only confirm the accent:

```
pane-active-border-style  fg=peach     (bg=base)
pane-border-style         fg=surface_0 (bg=base)
window-style              bg=crust          # inactive dim
window-active-style       bg=base
pane-border-status top, pane-border-format ""   (empty — no titles)
```

### 5.6 popups (per-tool accent, unified rounded line)

Global default:

```
set -g popup-border-lines rounded
set -g popup-border-style "fg=#{@thm_surface_1}"
set -g popup-style        "bg=#{@thm_mantle}"
```

Per binding (the two we fully control), add `-b rounded` and an accent `-S fg=ACCENT`:

- **Neogit** `C-g` → accent **mauve**
- **Worktrees** `C-;` → accent **peach** (already titled ` Worktrees `)

Plugin popups are themed via their own (limited) options:

- **floax** `C-p` → `@floax-border-color` blue; rounded only if the plugin supports it.
- **sessionx** `o` → set available accent/prompt options to green; sessionx's border styling is limited by its fzf-tmux popup — accept whatever it exposes.

> Honesty note: floax and sessionx do not give full border control. We theme what they expose and accept the rest.

### 5.7 messages & copy-mode

```
message-style          bg=surface_0, fg=peach
message-command-style  bg=surface_0, fg=peach
mode-style             bg=surface_1, fg=text   # copy-mode selection
```

## 6. Out of scope (YAGNI)

- New status modules (clock, CPU, RAM, battery, now-playing) — declined (option B).
- Claude-status / PR / worktree indicators in the bar — declined (option C).
- Pane-border titles.
- Palette change away from Mocha.
- New tmux plugins.
- Powerline slants (rejected in favor of islands).

## 7. Risks & caveats

1. **Cap-glyph seam.** The half-circle caps (U+E0B6 / U+E0B4) can show a hairline seam or vertical misalignment depending on the terminal's font rendering. MesloLGS NF generally renders them cleanly; verify in the primary terminal and nudge padding if needed. This is the single most likely thing to need fiddling.
2. **catppuccin var availability.** Don't assume every `@thm_*` exists; define the ones we use explicitly from §4 hex.
3. **Centered justify + wide pills.** `absolute-centre` must still center the window list once pills widen the left/right segments; check `status-*-length`.
4. **Transparent bg dependency.** Caps rely on `bg=default` matching the terminal background. Correct for the current transparent setup; an opaque `status-bg` would require the caps to use that color instead.
5. **Plugin popup theming limits** (§5.6).

## 8. Verification plan

tmux config isn't unit-testable; verification is a manual visual checklist after `tmux source-file ~/.tmux.conf` (back up first; revert is `git checkout .tmux.conf`).

- [ ] Normal bar: session + command pills render, caps clean (no seam), labels neutral.
- [ ] Hold prefix (`C-Space`): session pill turns peach.
- [ ] Multiple windows: active = peach chip, others = overlay; centered correctly.
- [ ] `cd` into a non-git dir: git pill disappears; into a repo: shows branch in blue.
- [ ] Zoom a pane (`prefix z`): pink zoom pill appears, disappears on unzoom.
- [ ] Each popup (`C-g`, `C-;`, `C-p`, `o`): rounded border, correct per-tool accent.
- [ ] Trigger a message: surface-0/peach styling.
- [ ] Enter copy-mode + select: selection uses surface-1/text.
- [ ] Inactive pane still dims to crust; active pane base with peach top border.
- [ ] Cross-check side-by-side with sketchybar: pill shape / accent-icon / peach focus visibly rhyme.

## 9. Rollout

- Branch: continue on `work` (or a dedicated branch); single-file change keeps revert trivial.
- Implement in `~/dotfiles/.tmux.conf`, reload, walk the §8 checklist in the real terminal.
- Commit once the checklist passes.
