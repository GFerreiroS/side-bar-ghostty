# Ghostty vertical tabs (Linux / GTK)

## Goal

Add **Arc-browser-style vertical tabs in a left sidebar** to Ghostty on Linux,
delivered as a **patch applied to the official source**, not a maintained fork.

Ghostty ships tabs horizontally only. The aim is a left sidebar listing tabs
vertically, so many sessions stay readable — the horizontal strip becomes
unusable past a handful of tabs.

## How it must be delivered

A repo containing:

```
patches/*.patch     the change, as a diff against an upstream tag
PKGBUILD            fetches the OFFICIAL ghostty tarball, applies the patches
.github/workflows/  CI that re-tests the patch against each new upstream release
```

**Patch + PKGBUILD, not a fork.** Upgrading is then a version bump rather than a
merge of a parallel tree. Keep the change **additive** — a new sidebar widget in
its own file plus a few hook lines conflicts far less than edits scattered
through existing code.

### Maintenance expectation — be honest about this

Truly zero maintenance is **not achievable**. What is achievable: CI (weekly
cron) that watches for a new upstream tag, applies the patch, builds, smoke
tests, and publishes — silent while it works, an alert when it doesn't.

Two failure modes no automation fixes:

1. **Patch conflict** — upstream edits the same lines. A human resolves it.
2. **Silent API drift** — patch applies and compiles, but libadwaita behaviour
   changed underneath, so the sidebar is subtly wrong. Nastier: nothing errors.

Release cadence for sizing the exposure: 12 tags from v1.0.0 to v1.3.1.

**Consider upstreaming instead.** If merged, maintenance genuinely drops to
zero. There is real demand (see issues below). Slower, and the timeline isn't
ours to control.

---

## Research already done — do NOT redo this

All verified on this machine. Ghostty **1.3.1-arch2**, Arch Linux, GNOME 50.4
on Wayland.

### Ghostty cannot do this through configuration

| surface | finding |
|---|---|
| `gtk-tabs-location` | accepts only `top`, `bottom`, `hidden`. No left/right. |
| plugin / extension API | **does not exist**. The only two "plugin" mentions in the man page are about KWin's blur effect. |
| `gtk-custom-css` | GTK4 CSS is **styling only** — colour, borders, padding, some sizing. Unlike web CSS it has no layout engine, so it cannot reorient a horizontal `AdwTabBar`. |
| `custom-shader` | Shadertoy-style GLSL applied *after* rendering. Pixel effects on the terminal surface; cannot create widgets. |
| `keybind`, `command-palette-entry` | bind existing actions only; cannot add UI. |

### GTK4 closed the runtime back door

GTK3 could load shared libraries into a running app via `GTK_MODULES`, which
would have allowed restructuring the widget tree without touching source.
**GTK4 removed it.** Verified:

```
strings /usr/lib/libgtk-4.so.1 | grep -cx gtk_module_init   -> 0
strings /usr/lib/libgtk-3.so.0 | grep -cx gtk_module_init   -> 1
```

So modifying the source is the only path.

### Existing forks are useless here

- [tomreinert/ghostty](https://github.com/tomreinert/ghostty) ("Sidegeist") —
  sidebar tabs with a git panel, but **macOS/Swift only** (`macos/`,
  `.swiftlint.yml`). Zero reuse for GTK.
- [cmux](https://news.ycombinator.com/item?id=47079718) — also macOS only.

Nothing existing targets the GTK frontend. This work starts from scratch there.

### Upstream discussion

- [Issue #2548 — Vertical Tabs](https://github.com/ghostty-org/ghostty/issues/2548)
- [Discussion #2549](https://github.com/ghostty-org/ghostty/discussions/2549)
- [Discussion #11744 — left-hand project navigation panel](https://github.com/ghostty-org/ghostty/discussions/11744)

---

## Technical starting point

Ghostty's GTK frontend is **Zig + GTK4 + libadwaita**.

The core constraint: **`AdwTabBar` is horizontal by design** — no orientation
property to flip.

The opening this leaves: **`AdwTabView` holds the tab model** and already backs
`AdwTabOverview`. So the job is adding a *new consumer* of that existing model —
a custom sidebar widget — rather than rewriting tab handling. That is what makes
this tractable and what keeps the patch additive.

### Build prerequisites — NOT installed on this machine

```
zig                  missing
blueprint-compiler   missing
```

Runtime deps already present via the `ghostty` package: `gtk4`, `libadwaita`,
`gtk4-layer-shell`, `harfbuzz`, `freetype2`, `fontconfig`, `oniguruma`,
`pixman`, `wayland`.

---

## First step, before any code

**Confirm a clean, unmodified source build works on this machine.** Clone
upstream at the tag matching the installed version, install the toolchain,
build, run it.

This is the risky step. If the toolchain fights, nothing else matters — and
there is no point designing UI before knowing the build works. Do not write
sidebar code until an unmodified build runs.

After that, and before proposing a design: read how the GTK apprt wires up
`AdwTabView` — where tabs are created, how the tab bar is attached to the
window, and what the window layout hierarchy looks like.

---

## Open design decisions — ask, don't assume

1. **Scope**: plain vertical tab strip, or the Arc/Sidegeist treatment (per-tab
   working directory, git branch, drag-to-reorder)?
2. **Fork for personal use, or aim upstream?** Changes how the patch is written
   — upstreaming needs a config option (`gtk-tabs-location = left`?) and to
   respect existing conventions; a personal patch can be more opinionated.
3. **Sidebar behaviour**: always visible, collapsible, auto-hide with one tab?
4. **Does it replace or complement the top bar?**

---

## Working style for this project

The user has been explicit about this, and it matters:

- **Do not guess.** Verify with evidence — read the source, run the command,
  check the docs. State what was actually confirmed versus what is assumed.
- **Ask design questions before implementing.** Show options with concrete
  previews rather than picking unilaterally.
- **Report failures honestly**, including one's own mistakes and wrong turns.

## Related

The user's desktop/dotfiles repo lives at
`~/Documents/projects/random/gnome-tahoe-setup` (branch `tahoe`, no `main`),
covering the macOS-like GNOME setup, zsh config, and the current ghostty config
this project would extend. Ghostty there is configured with
`gtk-titlebar-style = tabs` — the tab bar merged into the titlebar, one
horizontal row — which is the status quo a sidebar would replace.
