# Maintainer: paella <seba.gabi@gmail.com>
#
# Ghostty with Arc-style vertical tabs in a left sidebar.
#
# This is the OFFICIAL Ghostty source tarball with patches/ applied on top --
# not a fork, and not a checkout of anyone's branch. Upgrading is a version
# bump plus a checksum, and the patch either still applies or it does not.
#
# The build recipe below is deliberately kept as close as possible to Arch's
# own ghostty package (packaging/packages/ghostty), so that any divergence in
# behaviour is attributable to the patch rather than to how we build it.

pkgname=ghostty-vertical-tabs
_pkgname=ghostty
pkgver=1.3.1
pkgrel=1
pkgdesc='Ghostty with vertical tabs in a left sidebar (patched official source)'
arch=(x86_64 aarch64)
url="https://github.com/ghostty-org/$_pkgname"
license=(MIT)

# Deliberately not a split package, unlike Arch's. The terminfo and
# shell-integration halves are untouched by the patch, so shipping our own
# copies would mean conflicting with the repo packages to deliver byte-identical
# files. We depend on theirs instead, which does mean this package wants to be
# bumped in step with repo ghostty.
depends=(bzip2
         fontconfig libfontconfig.so
         freetype2 libfreetype.so
         glibc
         glib2 libglib-2.0.so libgio-2.0.so libgobject-2.0.so
         gtk4 libgtk-4.so
         gtk4-layer-shell
         libx11
         harfbuzz libharfbuzz.so
         libadwaita libadwaita-1.so
         libpng
         oniguruma
         pixman
         wayland libwayland-client.so
         zlib
         "$_pkgname-shell-integration"
         "$_pkgname-terminfo")
makedepends=(blueprint-compiler
             pandoc-cli
             zig)
provides=("$_pkgname=$pkgver")
conflicts=("$_pkgname")

_archive="$_pkgname-$pkgver"

# The patch is listed by its basename, and the basename is a symlink into
# patches/. That indirection is not decoration: makepkg requires local sources
# to sit beside the PKGBUILD ("Source files must either reside in the same
# directory as the PKGBUILD, or be a fully-qualified URL"), and it rejects both
# `patches/foo.patch` and the `foo.patch::patches/foo.patch` rename form --
# tested, both fail with "was not found in the build directory". The symlink
# keeps patches/ as the one real home while giving makepkg what it wants,
# including a working checksum.
#
# After regenerating a patch, run `updpkgsums` or the sum below will not match.
source=("$url/archive/v$pkgver/$_archive.tar.gz"
        0001-gtk-vertical-tab-sidebar.patch)
sha256sums=('265837d3026b433f0e6b4e49d43153b915b0a19513f7edd8a8e693c559bd415b'
            '021a253d4fe74361567432a0d2707261a201a224e57b6b6ab8a92faeba0a41e4')

# Zig 0.15.x only.
#
# Ghostty v1.3.1 declares `minimum_zig_version = "0.15.2"`, which 0.16 also
# satisfies -- but a minimum is not a maximum, and upstream's own port to Zig
# 0.16 ("Update to Zig 0.16.0", e8525c0fd) landed months *after* this tag. So
# 0.16 is newer than any Zig this source was ever built against, and Arch's
# repo zig is 0.16 today. Failing here with an explanation beats failing 200
# lines into a compile with a syntax error in std.
#
# Set ZIG=/path/to/zig-0.15.2/zig to build with a toolchain of your own.
_zig="${ZIG:-zig}"

_check_zig() {
	local ver
	ver="$("$_zig" version 2>/dev/null)" || {
		error "cannot run '%s'" "$_zig"
		return 1
	}
	case "$ver" in
		0.15.*) msg2 "using zig $ver" ;;
		*)
			error "zig %s is not supported for ghostty %s; need 0.15.x" "$ver" "$pkgver"
			plain "Arch's repo zig has moved past it. Fetch the 0.15.2 tarball from"
			plain "https://ziglang.org/download/ and build with:"
			plain "    ZIG=/path/to/zig-0.15.2/zig makepkg"
			return 1
			;;
	esac
}

# Work around Zig being unable to link against Arch's libc at all.
#
# Arch's binutils 2.47 / gcc 16 emit a GNU_SFRAME section in /usr/lib/crt1.o
# carrying R_X86_64_PC64 relocations, and Zig's self-hosted ELF linker does not
# implement that relocation type:
#
#   error: fatal linker error: unhandled relocation type R_X86_64_PC64
#       note: in /usr/lib/crt1.o:.sframe
#
# This is not specific to Ghostty -- `pub fn main() void {}` with -lc fails the
# same way -- so there is nothing to fix in the patch or in this recipe. But it
# does mean a stock `makepkg` cannot build this package today, which is not a
# useful thing for a PKGBUILD to be.
#
# So: probe first, and only if the probe fails, copy the CRT objects somewhere
# private, drop the section, and point Zig at that copy with a --libc file.
# `.sframe` is stack-trace metadata for unwinders; nothing links against it and
# discarding it costs only the ability to unwind through the glibc startup
# stubs. The moment Zig implements the relocation, or binutils stops emitting
# it, the probe passes and none of this runs.
_workaround_sframe() {
	local probe="$srcdir/sframe-probe"
	rm -rf "$probe"; mkdir -p "$probe"
	printf 'pub fn main() void {}\n' >"$probe/probe.zig"

	if (cd "$probe" && "$_zig" build-exe probe.zig -lc \
			--cache-dir "$probe/cache" &>"$probe/log"); then
		msg2 "zig links against libc; no workaround needed"
		return 0
	fi

	if ! grep -q "R_X86_64_PC64" "$probe/log"; then
		error "zig cannot link a trivial program against libc:"
		cat "$probe/log" >&2
		return 1
	fi

	warning "zig cannot link against this libc (crt1.o .sframe); working around it"

	local crt="$srcdir/crt"
	rm -rf "$crt"; mkdir -p "$crt"

	# One objcopy per object: it takes a single input file, not a glob.
	local o
	for o in crt1 Scrt1 crti crtn rcrt1 gcrt1 Mcrt1; do
		[[ -f "/usr/lib/$o.o" ]] || continue
		cp "/usr/lib/$o.o" "$crt/"
		objcopy --remove-section=.sframe --remove-section=.rela.sframe "$crt/$o.o"
	done

	# Zig searches one directory for the CRT objects *and* the libraries beside
	# them, so glibc's own files have to be reachable from there too. Taken
	# from the package rather than a glob, so this stays exactly glibc's set
	# and does not drag the rest of /usr/lib into Zig's search path.
	local f
	while read -r f; do
		[[ -f $f ]] && ln -sf "$f" "$crt/"
	done < <(pacman -Qlq glibc | grep -E '^/usr/lib/(lib.*\.(a|so[0-9.]*)|ld-linux.*)$')

	# build() and check() key off this file existing rather than off a shell
	# variable, so `makepkg --noprepare` on an already-prepared tree still
	# picks the workaround up instead of silently rebuilding without it.
	"$_zig" libc >"$srcdir/libc.txt"
	sed -i "s|^crt_dir=.*|crt_dir=$crt|" "$srcdir/libc.txt"
}

_zig_libc() {
	[[ -f "$srcdir/libc.txt" ]] && printf '%s\n' --libc "$srcdir/libc.txt"
}

prepare() {
	_check_zig
	_workaround_sframe

	cd "$_archive"

	# The patch, and nothing else. `git apply` is not used because the
	# tarball is not a repository; `patch` reads the same diff.
	local p
	for p in "$srcdir"/*.patch; do
		msg2 "applying ${p##*/}"
		patch -p1 -i "$p"
	done

	# fetch-zig-cache.sh calls a bare `zig`, so $ZIG is not enough on its own:
	# with a toolchain that is not on PATH, the very first entry in
	# build.zig.zon.txt (a git+https dep) fails and the script exits, reporting
	# only "Failed to fetch" because it discards stderr. Give it a PATH entry
	# pointing at whichever zig we settled on.
	mkdir -p "$srcdir/zig-bin"
	ln -sf "$(command -v "$_zig" || readlink -f "$_zig")" "$srcdir/zig-bin/zig"

	PATH="$srcdir/zig-bin:$PATH" \
		ZIG_GLOBAL_CACHE_DIR="$srcdir/zig-global-cache/" \
		./nix/build-support/fetch-zig-cache.sh
}

build() {
	cd "$_archive"

	local libc
	mapfile -t libc < <(_zig_libc)

	# Identical to Arch's flags, with the version string marking this as
	# patched so `ghostty --version` cannot be mistaken for a stock build.
	DESTDIR=build "$_zig" build \
		"${libc[@]}" \
		--summary all \
		--prefix "/usr" \
		--system "$srcdir/zig-global-cache/p" \
		-Doptimize=ReleaseFast \
		-Dgtk-x11=true \
		-Dcpu=baseline \
		-Dpie=true \
		-Demit-docs \
		-Dversion-string="$pkgver-vertical-tabs$pkgrel" \
		--build-id=sha1
}

check() {
	cd "$_archive"

	local libc
	mapfile -t libc < <(_zig_libc)

	# Upstream's suite. It does not cover the sidebar -- Ghostty's test binary
	# excludes the GTK apprt entirely -- so this is a regression check on the
	# code the patch sits next to, not on the patch.
	"$_zig" build test "${libc[@]}" --system "$srcdir/zig-global-cache/p"
}

package() {
	cd "$_archive"
	cp -a build/* "$pkgdir/"
	install -Dm0644 -t "$pkgdir/usr/share/licenses/$pkgname/" LICENSE

	# Owned by the repo packages we depend on.
	rm -r "$pkgdir"/usr/share/terminfo
	rm -r "$pkgdir"/usr/share/ghostty/shell-integration

	# Needs nautilus-python, which we do not pull in.
	rm -rf "$pkgdir"/usr/share/nautilus-python/
}
