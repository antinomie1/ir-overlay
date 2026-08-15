# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop optfeature pax-utils unpacker xdg

# Upstream ships ChatGPT, ChatGPT Work and the Codex coding agent as a single
# unified Electron app whose Debian package, payload directory
# (/usr/lib/chatgpt), launcher symlink (/usr/bin/chatgpt) and .desktop entry
# are all named "chatgpt" -- only the CDN path and app branding say "Codex".
# The upstream binary name "chatgpt" is kept for the installed command so the
# shipped .desktop file, the x-scheme-handler/codex MIME handler, and any
# user-facing docs that say "run chatgpt" keep working, while the package
# itself is named dev-util/codex-desktop to sit next to dev-util/codex (the
# Rust CLI).
MY_PN="chatgpt"

DESCRIPTION="OpenAI Codex/ChatGPT unified desktop application (Electron, proprietary)"
HOMEPAGE="https://developers.openai.com/codex/app"

# Upstream also serves a rolling .../deb/latest/chatgpt_amd64.deb alias, but
# that URL's content changes over time, so it cannot be used here: SRC_URI
# for a fixed PV must always resolve to the same bytes, or Manifest digest
# verification is meaningless. This pool path is version-pinned instead
# (served with `cache-control: immutable`) and always returns exactly the
# bytes that shipped as ${PV}. See update.sh for how to pick up new releases.
OAI_BASE="https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/${MY_PN}"
SRC_URI="${OAI_BASE}/${MY_PN}_${PV}_amd64.deb -> ${P}-amd64.deb"
S="${WORKDIR}"

# The only license text shipped inside the package is the MIT copyright for
# the bundled Electron runtime (usr/share/doc/chatgpt/copyright) plus
# Chromium's LICENSES.chromium.html. No OpenAI license file is included, so
# the application itself is treated as all-rights-reserved.
LICENSE="all-rights-reserved MIT"
SLOT="0"
KEYWORDS="~amd64"
IUSE="apparmor egl wayland"
RESTRICT="bindist mirror strip"

RDEPEND="
	app-accessibility/at-spi2-core:2
	app-arch/xz-utils
	app-misc/ca-certificates
	dev-libs/expat
	dev-libs/glib:2
	dev-libs/libusb:1
	dev-libs/nspr
	dev-libs/nss
	dev-libs/openssl:0/3
	media-gfx/graphite2
	media-libs/alsa-lib
	media-libs/libglvnd
	media-libs/mesa[gbm(+)]
	net-print/cups
	sys-apps/dbus
	virtual/libudev:=
	x11-libs/cairo
	x11-libs/gdk-pixbuf:2
	x11-libs/gtk+:3
	x11-libs/libdrm
	x11-libs/libnotify
	x11-libs/libX11
	x11-libs/libxcb
	x11-libs/libXcomposite
	x11-libs/libXdamage
	x11-libs/libXext
	x11-libs/libXfixes
	x11-libs/libxkbcommon
	x11-libs/libXrandr
	x11-libs/pango
	x11-misc/xdg-utils
	apparmor? ( sys-apps/apparmor )
"

# gdk-pixbuf-thumbnailer is used at install time to scale the single icon
# upstream ships into the icon sizes hicolor actually declares.
BDEPEND="x11-libs/gdk-pixbuf:2"

QA_PREBUILT="*"

# Payload lives in usr/lib/chatgpt inside the .deb.
CODEX_SRCDIR="usr/lib/${MY_PN}"
CODEX_DESTDIR="/opt/${PN}"

src_install() {
	dodir "${CODEX_DESTDIR}"
	cp -a "${CODEX_SRCDIR}/." "${ED}${CODEX_DESTDIR}/" || die

	# This Electron build ships no setuid chrome-sandbox helper: it relies on
	# unprivileged user namespaces instead (the bundled AppArmor profile's
	# only rule is "userns,"). Hence no `fperms 4711` here -- see
	# pkg_postinst for the kernel requirement.
	pax-mark m "${ED}${CODEX_DESTDIR}/ChatGPT"

	# codex-launcher resolves its own path with `readlink -f "$0"` and then
	# execs ./ChatGPT next to it, so it is symlink-safe by design and no
	# wrapper script is needed.
	dosym -r "${CODEX_DESTDIR}/codex-launcher" "/opt/bin/${MY_PN}"
	dosym -r "${CODEX_DESTDIR}/codex-launcher" "/opt/bin/${PN}"

	local exec_flags=()
	if use wayland; then
		exec_flags+=(
			--ozone-platform-hint=auto
			--enable-wayland-ime
			--wayland-text-input-version=3
		)
	fi
	if use egl; then
		exec_flags+=( --use-gl=egl )
	fi

	# Upstream ships Exec=chatgpt %U / Icon=chatgpt; only splice in the flags.
	sed -e "s|^Exec=${MY_PN}|Exec=${MY_PN} ${exec_flags[*]}|" \
		"usr/share/applications/${MY_PN}.desktop" \
		>"${T}/${PN}.desktop" || die
	domenu "${T}/${PN}.desktop"

	# Upstream ships exactly one icon, a 1024x1024 PNG. Installing it at its
	# native size alone leaves the menu entry iconless: hicolor's index.theme
	# declares no 1024x1024 directory, and XDG themed-icon lookup scans only
	# the directories a theme declares. Scale it into the standard declared
	# sizes instead. gdk-pixbuf-thumbnailer comes from x11-libs/gdk-pixbuf,
	# which is already a runtime dependency of this package.
	local size
	for size in 16 22 24 32 48 64 128 256 512 ; do
		gdk-pixbuf-thumbnailer -s ${size} \
			"usr/share/pixmaps/${MY_PN}.png" "${T}/${size}-${MY_PN}.png" || die
		newicon -s ${size} "${T}/${size}-${MY_PN}.png" "${MY_PN}.png"
	done

	# Keep upstream's unthemed full-resolution copy too. GTK searches
	# /usr/share/pixmaps as a fallback; Qt/KDE does not, which is why the
	# themed sizes above are the actual fix rather than this.
	insinto /usr/share/pixmaps
	doins "usr/share/pixmaps/${MY_PN}.png"

	if use apparmor; then
		insinto /etc/apparmor.d
		doins "etc/apparmor.d/${MY_PN}"
	fi
}

pkg_postinst() {
	xdg_pkg_postinst

	elog "The ${PN} binary is installed as both /opt/bin/${MY_PN} and"
	elog "/opt/bin/${PN}; upstream calls the command 'chatgpt'."
	elog
	elog "This build has no setuid chrome-sandbox helper: the renderer sandbox"
	elog "needs unprivileged user namespaces (CONFIG_USER_NS=y and"
	elog "kernel.unprivileged_userns_clone / user.max_user_namespaces > 0)."
	elog "Without them the app only starts with --no-sandbox, which is not"
	elog "recommended."

	optfeature "repository operations from the Codex agent" dev-vcs/git
	optfeature "system tray icon" dev-libs/libayatana-appindicator-glib
	optfeature "audio playback via PulseAudio/PipeWire" media-libs/libpulse
}
