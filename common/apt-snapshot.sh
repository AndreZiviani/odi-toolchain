#!/bin/sh
# Point apt at snapshot.debian.org, frozen at one timestamp, so an image
# built next year installs the same package versions as one built today.
#
#     apt-snapshot.sh <YYYYMMDDTHHMMSSZ>
#
# The debian:bookworm images already carry the snapshot URI for their own
# build date as a comment in debian.sources; this replaces the live mirror
# with the snapshot for the timestamp given. Plain http is deliberate: the
# slim image has no CA bundle, and apt checks the archive signatures anyway.
# Check-Valid-Until is off because a snapshot Release file expires by design.
set -eu
ts=${1:?usage: apt-snapshot.sh <timestamp>}
src=/etc/apt/sources.list.d/debian.sources
[ -f "$src" ] || { echo "no $src in this image" >&2; exit 1; }
sed -i \
	-e "s|^URIs: http://deb.debian.org/debian-security\$|URIs: http://snapshot.debian.org/archive/debian-security/$ts|" \
	-e "s|^URIs: http://deb.debian.org/debian\$|URIs: http://snapshot.debian.org/archive/debian/$ts|" \
	"$src"
grep -q "snapshot.debian.org/archive/debian/$ts" "$src" || { echo "apt-snapshot: debian URI not rewritten" >&2; exit 1; }
grep -q "snapshot.debian.org/archive/debian-security/$ts" "$src" || { echo "apt-snapshot: security URI not rewritten" >&2; exit 1; }
cat > /etc/apt/apt.conf.d/99snapshot <<CONF
Acquire::Check-Valid-Until "false";
Acquire::Retries "5";
CONF
