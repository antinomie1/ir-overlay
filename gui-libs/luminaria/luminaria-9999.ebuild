# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

LLVM_COMPAT=( 22 )

inherit llvm-r2 git-r3

DESCRIPTION="Minimal Wayland compositor library built with C++23 modules and Vulkan"
HOMEPAGE="https://github.com/antinomie1/luminaria"
EGIT_REPO_URI="https://github.com/antinomie1/luminaria.git"

LICENSE="BSD-2"
SLOT="0"
IUSE="debug test"
RESTRICT="!test? ( test )"

RDEPEND="
	dev-libs/libinput:=
	dev-libs/wayland
	dev-libs/wayland-protocols
	media-libs/fcft
	media-libs/mesa[gbm(+)]
	media-libs/vulkan-loader
	sys-auth/seatd:=
	virtual/libudev:=
	x11-libs/libdrm
	x11-libs/libxcb:=
	x11-libs/libxkbcommon
	x11-libs/pixman
"
DEPEND="
	${RDEPEND}
	dev-util/vulkan-headers
"
BDEPEND="
	$(llvm_gen_dep '
		llvm-core/clang:${LLVM_SLOT}
	')
	dev-build/xmake
	dev-util/glslang
	dev-util/wayland-scanner
	virtual/pkgconfig
"

pkg_setup() {
	llvm-r2_pkg_setup
	export XMAKE_ROOT=y
}

src_configure() {
	xmake g --network=private || die "xmake global config failed"

	local xmake_args=(
		-y
		-v
		-D
		--toolchain=clang
		--mode=$(usex debug debug release)
		--cxflags="-D_FORTIFY_SOURCE=0"
	)
	xmake f "${xmake_args[@]}" || die "xmake configure failed"
}

src_compile() {
	xmake build -y -v -D || die "xmake build failed"
}

src_test() {
	local -x XDG_RUNTIME_DIR="${T}/run"
	mkdir -p "${XDG_RUNTIME_DIR}" || die
	chmod 0700 "${XDG_RUNTIME_DIR}" || die
	xmake test -v || die "xmake test failed"
}

src_install() {
	xmake install -y -o "${ED}/usr" --binaries=n --libraries=y --headers=y || die "xmake install failed"

	# Install source tree and xmake module targets for downstream consumers (e.g. gui-wm/mio)
	insinto /usr/share/luminaria
	doins -r src protocol xmake.lua
	if [[ -d build/generated ]]; then
		insinto /usr/share/luminaria/build
		doins -r build/generated
	fi

	einstalldocs
}
