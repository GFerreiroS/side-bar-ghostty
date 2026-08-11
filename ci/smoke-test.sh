#!/usr/bin/env bash
#
# Prove that a built Ghostty actually renders the vertical tab sidebar.
#
# This exists because the interesting failure mode of a patch is not the one
# that fails to apply -- CI catches that in seconds -- but the one that applies,
# compiles, and is silently wrong because libadwaita changed underneath it. A
# green build says nothing about that. Looking at the pixels does.
#
# Method: launch headless twice, at two different configured rail widths, and
# measure the sidebar band on a scanline each time. The assertion is on the
# *difference* between the two, not on either absolute number, because the
# window's client-side decoration puts an offset in front of the sidebar that
# is not worth trying to model -- and it cancels exactly. That also makes this
# a stronger check than "is there a sidebar": it fails if the widget renders
# but has stopped listening to its configuration.
#
# Usage: ci/smoke-test.sh /path/to/ghostty

set -euo pipefail

GHOSTTY=${1:?usage: smoke-test.sh /path/to/ghostty}

for tool in Xvfb xdotool import python3; do
    command -v "$tool" >/dev/null || { echo "need $tool"; exit 127; }
done

NARROW=54
WIDE=94

WORK=$(mktemp -d)
export DISPLAY=:97
XVFB_PID=

cleanup() {
    [[ -n $XVFB_PID ]] && kill "$XVFB_PID" 2>/dev/null || true
    rm -rf "$WORK"
}
trap cleanup EXIT

Xvfb "$DISPLAY" -screen 0 1280x800x24 +extension GLX +render -noreset \
    >"$WORK/xvfb.log" 2>&1 &
XVFB_PID=$!
sleep 2

# Our own config dir: the sidebar layers sidebar.conf over the config file, and
# a developer's real one would move the widths out from under the assertion.
export XDG_CONFIG_HOME="$WORK/config"
mkdir -p "$XDG_CONFIG_HOME"

# Measure the sidebar band for one configured width. Echoes the pixel count.
measure() {
    local want=$1 shot="$WORK/shot-$1.png" pid wid

    cat >"$WORK/ghostty.conf" <<EOF
gtk-tabs-location = left
gtk-tabs-sidebar-width = $want
gtk-tabs-sidebar-mode = hover
window-width = 100
window-height = 30
EOF

    GDK_BACKEND=x11 LIBGL_ALWAYS_SOFTWARE=1 \
        "$GHOSTTY" --config-file="$WORK/ghostty.conf" --gtk-single-instance=false \
        >"$WORK/ghostty-$want.log" 2>&1 &
    pid=$!

    wid=
    for _ in $(seq 30); do
        wid=$(xdotool search --class ghostty 2>/dev/null | tail -1 || true)
        [[ -n $wid ]] && break
        sleep 1
    done
    if [[ -z $wid ]]; then
        echo "FAIL: ghostty window never appeared (width=$want)" >&2
        cat "$WORK/ghostty-$want.log" >&2
        kill "$pid" 2>/dev/null || true
        return 1
    fi

    # The sidebar hides itself while there is only one tab, by design.
    xdotool key --window "$wid" ctrl+shift+t
    sleep 3
    import -window root "$shot"

    kill "$pid" 2>/dev/null || true
    sleep 2

    python3 - "$shot" <<'PY'
import sys
from PIL import Image

im = Image.open(sys.argv[1]).convert("RGB")
px = im.load()
w, h = im.size
row = h // 3

# Runs of constant colour from the left edge. The window frame contributes a
# couple of thin ones before the sidebar, so take the first run long enough to
# be a sidebar rather than a border.
runs, start = [], 0
for x in range(1, w):
    if px[x, row] != px[start, row]:
        runs.append((start, x - 1))
        start = x
runs.append((start, w - 1))

for a, b in runs:
    n = b - a + 1
    if n >= 16:
        print(n)
        break
else:
    sys.exit("FAIL: no run wide enough to be a sidebar")
PY
}

echo "== measuring at width=$NARROW"
narrow=$(measure "$NARROW")
echo "   band = ${narrow}px"

echo "== measuring at width=$WIDE"
wide=$(measure "$WIDE")
echo "   band = ${wide}px"

want=$((WIDE - NARROW))
got=$((wide - narrow))
echo "== delta: got ${got}px, want ${want}px"

if [[ $got -ne $want ]]; then
    echo "FAIL: sidebar did not track its configured width" >&2
    exit 1
fi

echo "OK: sidebar renders and tracks gtk-tabs-sidebar-width"
