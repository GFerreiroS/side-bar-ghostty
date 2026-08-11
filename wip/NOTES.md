# WIP — sidebar config options, settings file, richer tabs, prefs menu

**All six steps are done, building green and visually verified.** They are in
`patches/0001-gtk-vertical-tab-sidebar.patch`, which applies cleanly to a
pristine `v1.3.1`.

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
Ghostty's test binary (grep it for `GhosttyTabSidebar` — zero hits), so a
green suite says nothing about this work. It stays green — 2568/2590, 22
skipped, same as before the change — but the 10 tests that matter were run
standalone:

```sh
# tab_sidebar_git.zig has no GTK imports, so it runs as-is
build/zig-0.15.2/zig test build/ghostty/src/apprt/gtk/tab_sidebar_git.zig

# tab_sidebar_settings.zig needs glib and src/config.zig stubbed
sed 's|@import("../../config.zig")|@import("cfg")|' …/tab_sidebar_settings.zig > settings.zig
zig test --dep glib --dep cfg -Mroot=settings.zig -Mglib=glib.zig -Mcfg=config.zig
```

Geometry was measured off Xvfb screenshots (see the visual-testing notes):
width 54 → 54px, width 72 → 72px, expanded 260 → 260px, chip = icon-size at
both widths, all exact. A 3000ms `animation-duration` was caught mid-slide at
170px, and a 3000ms `collapse-delay` was still open 1.5s after the pointer
left. Rail mode with every row option on still measures exactly 54px.

**Known cosmetic defect, pre-existing:** the chip sits 1px right of the rail's
centre (margins 12/10 at the default, 25/23 at width 72) even though the CSS
margins are symmetric. Identical before and after this work, so something in
the viewport/scrollbar allocation adds it, not the margins.

4. **Runtime CSS.** `TabSidebar.writeCss` emits the configurable half of the
   sidebar's stylesheet into a provider added to the display at
   `STYLE_PROVIDER_PRIORITY_APPLICATION + 4` — above `style.css` so it wins,
   below `STYLE_PROVIDER_PRIORITY_USER` so a user's `gtk-custom-css` still
   beats it. Removed from the display on dispose, or a closed window keeps
   styling the open ones.

   The chip margins are the derived pair the earlier notes warned about, and
   they now come from `Settings.iconMargin` / `newButtonMargin` rather than
   being written down. Measured: `icon-size = 32` → a 32×32 chip,
   `icon-size = 24` → 24×24, at both the default and a 72px rail.

5. **Row content.** A second line (branch, then the `subtitle` setting) and
   status icons (bell, read-only — both real Surface properties,
   `getBellRinging` / `getReadonly`). Branch comes from
   `tab_sidebar_git.zig`: no libgit2 and no subprocess, just the `HEAD` file,
   with a `GFileMonitor` on it because a checkout rewrites it.

   Two things that are not obvious:
   - Indicators are shown **only when expanded**, because the row box has to
     measure exactly one chip across on the rail or the rail grows over the
     terminal. So a ringing bell *also* puts `ghostty-tab-attention` on the
     row, which tints the tab icon — the rail is where an unattended tab most
     needs to shout, and it is where there is no room for an icon.
   - With `subtitle = title`, the name no longer gets its `— title` suffix
     when two tabs share a directory: the subtitle line is already showing
     it, and the screenshot had it printed twice on one row.

6. **Preferences dialog.** `tab_sidebar_prefs.zig`, built in code rather than
   as a blueprint — thirteen rows mechanically derived from thirteen fields,
   and a `.blp` would mean naming them all twice with nothing checking the
   lists agree. One handler serves every row: any change re-reads the whole
   dialog, so the widget-to-field mapping exists once and `normalize` runs
   against the complete picture. Reached from the menu via a `sidebar.*`
   action group inserted on the widget.

   Verified end to end under Xvfb: menu → dialog → increment expanded width
   → the panel reflowed to exactly 265px live, `sidebar.conf` was written,
   and a restart came back at 265 against a config saying 260.

   *Beware:* `adw.SpinRow`/`SwitchRow` are `opaque` in this gobject binding
   but do have methods (`pub const new = adw_...`) — grepping for
   `^    pub fn ` finds only `as` and will mislead you into thinking they are
   unusable.

## Packaging (added 2026-08-11)

`PKGBUILD` and `.github/workflows/` now exist, so the repo finally matches the
three deliverables `CLAUDE.md` asks for. Verified by actually running them, not
by reading them.

- **A clean `makepkg` succeeds**, from the official tarball, ReleaseFast, with
  `check()` running upstream's suite. The resulting package was extracted and
  the binary launched under Xvfb: the sidebar renders, with branch and
  subtitle. `ghostty --version` reports `1.3.1-vertical-tabs1`.
- **makepkg will not take a local source in a subdirectory.** Both
  `patches/foo.patch` and `foo.patch::patches/foo.patch` fail with "was not
  found in the build directory" — the man page means it literally. The
  workaround is the root symlink `0001-…patch -> patches/0001-…patch`, which
  keeps `patches/` canonical and still checksums properly.
- **Two toolchain guards live in the PKGBUILD, and both are needed today:**
  - Arch's repo zig is 0.16, and v1.3.1 predates upstream's 0.16 port. The
    build fails fast with instructions rather than deep inside a compile.
    Override with `ZIG=/path/to/zig-0.15.2/zig makepkg`.
  - Zig cannot link against Arch's libc at all right now: `crt1.o` carries a
    `GNU_SFRAME` section with `R_X86_64_PC64` relocations Zig's ELF linker does
    not implement. `pub fn main() void {}` with `-lc` fails identically, so
    this is nothing to do with the patch. `prepare()` probes for it and, only
    if it fails, strips the section into a private CRT dir and points Zig at
    it with a `--libc` file. It disappears the moment either side fixes this.

    (`objcopy` takes one input file, not a glob — the first version of this
    silently printed its usage and failed `prepare()`.)
- **`ci/smoke-test.sh` is the guard against silent API drift**, which is the
  failure mode nothing else catches. It launches twice at two configured rail
  widths and asserts the *difference* — absolute pixel positions depend on the
  client-side decoration, the delta does not, and asserting on it also proves
  the widget still reads its configuration. Negative control: run it against
  `/usr/bin/ghostty` (unpatched) and it fails, as it must.
- **Upstream publishes no GitHub Release** — `/releases/latest` is a 404 — so
  the watcher reads the tag list, filters to `vX.Y.Z` (dropping the rolling
  `tip`) and sorts with `sort -V`.
- **`$ZIG` alone is not enough.** `nix/build-support/fetch-zig-cache.sh` calls
  a *bare* `zig`, and the first line of `build.zig.zon.txt` is a `git+https`
  dep, so with no zig on PATH the very first fetch fails — reporting only
  "Failed to fetch", because the script discards stderr. `prepare()` now
  symlinks the chosen toolchain into `$srcdir/zig-bin` and puts that on PATH.

  This was caught by CI, not locally: the first local `makepkg` passed only
  because `build/bin` happened to be on PATH supplying *both* `zig` and
  `blueprint-compiler`. Re-test packaging with `PATH` containing
  blueprint-compiler but **not** zig, which is what the container looks like.
- Re-running `makepkg` over an already-patched `src/` fails confusingly
  ("which already exists! Assume -R?"). Normal makepkg behaviour, not ours —
  use `makepkg -C` or a clean directory.
- The artifact glob `ghostty-vertical-tabs-*.pkg.tar.zst` also matches the
  `-debug` package, and `tar -xf` then treats the second match as a member
  name. Anchor on the version digit: `ghostty-vertical-tabs-[0-9]*`.

**Forward-compatibility, measured 2026-08-11:** the patch applies cleanly to
`v1.3.0` *and* to `tip`. It conflicts with `v1.2.0` and `v1.0.0`, which is how
the watcher was confirmed to actually detect conflicts. Applying is not
compiling and not behaving — `tip` was not built — but the patch regions have
stayed stable across a lot of upstream churn.

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
