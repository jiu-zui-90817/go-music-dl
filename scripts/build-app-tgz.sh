#!/usr/bin/env bash
# Build app.tgz (fnOS payload) from an upstream go-music-dl release archive.
#
# Usage: scripts/build-app-tgz.sh <upstream-linux.tar.gz> <output-app.tgz>
set -euo pipefail

RELEASE_TGZ="${1:?usage: build-app-tgz.sh <upstream-linux.tar.gz> <output-app.tgz>}"
OUT_TGZ="${2:?usage: build-app-tgz.sh <upstream-linux.tar.gz> <output-app.tgz>}"

die() { echo "ERROR: $*" >&2; exit 1; }

[ -f "${RELEASE_TGZ}" ] || die "release archive not found: ${RELEASE_TGZ}"

mkdir -p "$(dirname "${OUT_TGZ}")"
OUT_DIR=$(cd "$(dirname "${OUT_TGZ}")" && pwd)
OUT_TGZ="${OUT_DIR}/$(basename "${OUT_TGZ}")"

WORK_DIR=$(mktemp -d)
trap 'rm -rf "${WORK_DIR}"' EXIT

tar -xzf "${RELEASE_TGZ}" -C "${WORK_DIR}"
BIN=$(find "${WORK_DIR}" -maxdepth 3 -type f -name music-dl | head -n 1)
[ -n "${BIN}" ] || die "music-dl binary not found inside ${RELEASE_TGZ}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_SRC="$(cd "${SCRIPT_DIR}/.." && pwd)/fnos"
UI_SRC="${PKG_SRC}/ui"
[ -d "${UI_SRC}" ] || die "missing fnos/ui (desktop entry + icons)"

ROOT="${WORK_DIR}/app_root"
mkdir -p "${ROOT}/bin"
cp "${BIN}" "${ROOT}/bin/music-dl"
chmod 755 "${ROOT}/bin/music-dl"
for extra in LICENSE README.md; do
    if [ -f "${WORK_DIR}/${extra}" ]; then
        cp "${WORK_DIR}/${extra}" "${ROOT}/${extra}"
    fi
done

# fnOS registers the app-center / desktop entry from the payload's own ui/config
# (installed as ${TRIM_APPDEST}/ui), not from a root-level ui/ directory. Without
# this copy the app installs and runs but has no open entry on the desktop.
cp -a "${UI_SRC}" "${ROOT}/ui"

( cd "${ROOT}" && tar -czf "${OUT_TGZ}" . )
echo "[build-app-tgz] wrote ${OUT_TGZ} ($(wc -c < "${OUT_TGZ}") bytes)"
