#!/usr/bin/env bash
# Bump dev-util/codex-desktop to whatever build OpenAI is currently shipping,
# and regenerate the Manifest to match.
#
# The ebuild's SRC_URI points at a version-pinned, immutable pool URL (not
# the rolling .../deb/latest/ alias -- that one's bytes change over time,
# which is incompatible with a fixed PV and digest verification). This
# script uses the "latest" alias only to *discover* the current version
# cheaply (a ~64KiB range request, just enough to read the .deb's embedded
# control.tar.xz member, without pulling the full ~400MB payload), then
# downloads the real distfile from the immutable pool URL for hashing.
#
# There is still only ever one live ebuild version for this package: once
# upstream ships a newer build, the previous PV's exact bytes are no longer
# discoverable (the pool URL for that PV keeps working -- it's immutable --
# but nothing points a new user at old PVs), so this script renames the
# existing ebuild (git mv) rather than adding a new one alongside it.
set -euo pipefail

PKGDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PN="codex-desktop"
MY_PN="chatgpt"
LATEST_URL="https://persistent.oaistatic.com/codex-app-prod/linux/deb/latest/${MY_PN}_amd64.deb"
OAI_BASE="https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/${MY_PN}"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

echo "Checking current version at ${LATEST_URL} ..."
curl -fsSL -r 0-65535 "$LATEST_URL" -o "$workdir/prefix.deb"
(cd "$workdir" && ar x prefix.deb control.tar.xz && tar -xJf control.tar.xz ./control)
newver="$(awk -F': ' '/^Version:/{print $2}' "$workdir/control")"
[[ -n "$newver" ]] || { echo "error: could not read Version: from control file" >&2; exit 1; }

old_ebuild="$(find "$PKGDIR" -maxdepth 1 -name "${PN}-*.ebuild" | head -n1 || true)"
old_ver=""
[[ -n "$old_ebuild" ]] && old_ver="$(basename "$old_ebuild" .ebuild | sed "s/^${PN}-//")"

if [[ "$newver" == "$old_ver" ]]; then
	echo "Already at ${newver}, nothing to do."
	exit 0
fi

pool_url="${OAI_BASE}/${MY_PN}_${newver}_amd64.deb"
echo "New version ${newver}, downloading ${pool_url} ..."
curl -fsSL "$pool_url" -o "$workdir/chatgpt_amd64.deb"

size="$(stat -c%s "$workdir/chatgpt_amd64.deb")"
b2="$(b2sum "$workdir/chatgpt_amd64.deb" | cut -d' ' -f1)"
sha512="$(sha512sum "$workdir/chatgpt_amd64.deb" | cut -d' ' -f1)"

new_ebuild="$PKGDIR/${PN}-${newver}.ebuild"
if [[ -n "$old_ebuild" ]]; then
	git -C "$PKGDIR" mv "$(basename "$old_ebuild")" "$(basename "$new_ebuild")"
else
	echo "warning: no existing ${PN}-*.ebuild found in ${PKGDIR}, nothing to rename" >&2
	exit 1
fi

printf 'DIST %s-amd64.deb %s BLAKE2B %s SHA512 %s\n' \
	"${PN}-${newver}" "$size" "$b2" "$sha512" >"$PKGDIR/Manifest"

echo "Bumped ${old_ver:-<none>} -> ${newver}"
echo "Now review the diff and: git -C '${PKGDIR}' add -A && git -C '${PKGDIR}' commit"
