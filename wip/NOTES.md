# WIP — sidebar config options, settings file, richer tabs, prefs menu

Steps 1-3 are **done, building green and visually verified**; they are in
`patches/0001-gtk-vertical-tab-sidebar.patch`. Steps 4-6 remain.

The build tree now lives in `build/` (gitignored) rather than `/tmp`. It was
moved there on 2026-08-09 because `/tmp` is a 16G tmpfs with `usrquota` and the
13G of clone plus zig cache had hit the quota — which broke the Bash tool
outright, since it spools command output through `/tmp`. Living under `/home`
also ends the wipe risk that cost this project its implementation once.

## Agreed scope

Decided with the user on 2026-08-09:

- **Tab rows show:** git branch, a process/title second line, and status
  indicators (bell, read-only). *Not* a working-directory line — the row label
  is already folder-derived and the full path is in the tooltip.
- **Config options for:** sizes, appearance, timings, behaviour — all four
  groups.
- **Menu changes persist to a settings file the sidebar owns**, not to the
  user's hand-written Ghostty config, and not runtime-only.

## Done

1. `src/apprt/gtk/tab_sidebar_settings.zig` — config baseline + `sidebar.conf`
   overlay, with `load`/`save`/`set`, `normalize`, and four unit tests.
2. `src/config/Config.zig` — 12 new options plus two new enums.
3. Settings plumbed into `TabSidebar`. `rail_width`/`expanded_width`/
   `animation_ms`/`hover_collapse_ms`/`icon_chip` are gone as constants and
   read from `priv.settings`; the window pushes them in from `syncAppearance`
   via `setSettings`. `auto_hide` gates `Window.getSidebarVisible`.

   **`expand-on-hover` became `gtk-tabs-sidebar-mode`** — `hover` / `expanded`
   / `rail` — after the user asked for a "narrow but tooltips" behaviour *and*
   an always-expanded choice. Two booleans would have had a contradictory
   combination; the enum does not. Consequences worth remembering:
   - `rail` puts the row's name in the tooltip, since the label is never
     shown. The other modes keep the tooltip to the path alone.
   - `rail` also **keeps the "…" menu visible and turns `top_bar` vertical**
     to give it a row of its own. Without that the preferences dialog would be
     unreachable in the one mode that can never show it — a dead end you could
     only escape by hand-editing a file.
   - `expanded` reserves the *full* width from the terminal rather than
     overlaying it. Verified by screenshot: with the rail-only inset the panel
     sat permanently on top of the first ~200 columns.

### Verification

`zig build test` does **not** cover any of this: the GTK apprt is absent from
Ghostty's test binary (grep it for `GhosttyTabSidebar` — zero hits), so the
settings tests never ran there. They were run standalone instead, with `glib`
and `src/config.zig` stubbed: all 4 pass.

Geometry was measured off Xvfb screenshots (see the visual-testing notes):
width 54 → 54px, width 72 → 72px, expanded 260 → 260px, all exact. A 3000ms
`animation-duration` was caught mid-slide at 170px, and a 3000ms
`collapse-delay` was still open 1.5s after the pointer left.

## Remaining

4. **Runtime CSS.** Corner radius, icon size and the chip margins currently
   live in the static `style.css`, so configurable sizes need a generated
   stylesheet. `application.zig` already keeps a `css_provider` plus a
   `custom_css_providers` list (see ~line 368 and ~1105) — add a sidebar-owned
   `gtk.CssProvider` regenerated whenever settings change.
   *Reminder:* the chip margins are a derived pair — rows get
   `(width - icon_size) / 2`, and the "+" button gets that minus 6, because a
   flat button carries 6px of Adwaita padding that our `padding: 0` never wins
   against. Recompute both, never hardcode. `Settings.iconMargin` and
   `Settings.newButtonMargin` already derive the pair — use them.
   You can see the gap this leaves today: run with
   `gtk-tabs-sidebar-width = 72`, and the selected row's chip renders as a
   wide pill, because the CSS is still centring for a 54px rail.
5. Row content: subtitle line, indicators, git branch via a `GFileMonitor` on
   the repo's `HEAD` for each tab's pwd.
6. `Adw.PreferencesDialog` opened from the sidebar's "…" menu, wired to
   `Settings.save`, applying live.

## The 12 options

They are in the patch now, so they are no longer transcribed here. Two of them
(`corner-radius`, `icon-size`) are only half-wired: the Zig side reads them,
but the CSS side is step 4, so changing them today moves the icon box without
moving the chip drawn behind it.

## Scope warning worth revisiting

Twelve options in `src/config/Config.zig` widens the patch's conflict surface
well beyond `src/apprt/gtk/`, which is the opposite of the earlier decision to
drop a keybind and an auto-expand option to keep the patch inside the GTK
apprt. Upstream config churn will now cause conflicts more often. Worth a
conscious confirmation before this lands.

## How the shell died

`pkill -f 'zig-out/bin/ghostty'` matches on the **full command line**, which
includes the wrapper process running that very command — so it killed its own
shell. That is what the repeated exit-144s were. Use `pkill -x ghostty`, or
match a pattern that cannot appear in the invoking command line.
