#!/usr/bin/env bash
# Build a fnOS .fpk package for go-music-dl.
#
# Usage: scripts/build-fpk.sh <version> <platform> <app-tgz> [out-dir]
#   version  - package version, e.g. 1.1.7 (upstream release without the leading v)
#   platform - fnOS platform: x86 (amd64) or arm (arm64)
#   app-tgz  - payload produced by scripts/build-app-tgz.sh
#   out-dir  - output directory (default: dist/)
#
# The fpk layout follows the fnOS native-app spec: app.tgz + manifest (with the
# app.tgz md5 checksum) + cmd/ + config/ + ui/ + icons + *.sc port map.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PKG_SRC="${REPO_ROOT}/fnos"

die() { echo "ERROR: $*" >&2; exit 1; }

VERSION="${1:?usage: build-fpk.sh <version> <platform> <app-tgz> [out-dir]}"
PLATFORM="${2:?usage: build-fpk.sh <version> <platform> <app-tgz> [out-dir]}"
APP_TGZ="${3:?usage: build-fpk.sh <version> <platform> <app-tgz> [out-dir]}"
OUT_DIR="${4:-${REPO_ROOT}/dist}"

case "${VERSION}" in
    v*) VERSION="${VERSION#v}" ;;
esac
case "${PLATFORM}" in
    x86|arm|all) ;;
    *) die "invalid platform '${PLATFORM}' (expected x86, arm or all)" ;;
esac

[ -d "${PKG_SRC}" ] || die "missing fnos/ app directory: ${PKG_SRC}"
[ -f "${APP_TGZ}" ] || die "app.tgz not found: ${APP_TGZ}"
[ -f "${PKG_SRC}/manifest" ] || die "missing fnos/manifest"
[ -f "${PKG_SRC}/ICON.PNG" ] || die "missing fnos/ICON.PNG"
[ -f "${PKG_SRC}/ICON_256.PNG" ] || die "missing fnos/ICON_256.PNG"
[ -d "${PKG_SRC}/cmd" ] || die "missing fnos/cmd"
[ -d "${PKG_SRC}/config" ] || die "missing fnos/config"
[ -d "${PKG_SRC}/ui" ] || die "missing fnos/ui"

APPNAME=$(grep -E '^appname[[:space:]]*=' "${PKG_SRC}/manifest" | head -n 1 | cut -d '=' -f 2- | tr -d '[:space:]')
[ -n "${APPNAME}" ] || die "cannot read appname from fnos/manifest"

APP_TGZ_SIZE=$(wc -c < "${APP_TGZ}" | tr -d '[:space:]')
[ "${APP_TGZ_SIZE}" -ge 10240 ] || die "app.tgz too small (${APP_TGZ_SIZE} bytes) - corrupted download?"

if command -v md5sum >/dev/null 2>&1; then
    CHECKSUM=$(md5sum "${APP_TGZ}" | awk '{print $1}')
elif command -v md5 >/dev/null 2>&1; then
    CHECKSUM=$(md5 -q "${APP_TGZ}")
else
    die "md5sum/md5 not available"
fi

mkdir -p "${OUT_DIR}"
OUT_DIR=$(cd "${OUT_DIR}" && pwd)

WORK_DIR=$(mktemp -d)
trap 'rm -rf "${WORK_DIR}"' EXIT
PKG_DIR="${WORK_DIR}/package"
mkdir -p "${PKG_DIR}/cmd"

# 1. payload
cp "${APP_TGZ}" "${PKG_DIR}/app.tgz"
# 2. lifecycle scripts
cp -a "${PKG_SRC}/cmd/." "${PKG_DIR}/cmd/"
chmod 755 "${PKG_DIR}"/cmd/* 2>/dev/null || true
# 3. config + ui
cp -a "${PKG_SRC}/config" "${PKG_DIR}/config"
cp -a "${PKG_SRC}/ui" "${PKG_DIR}/ui"
# 4. icons + port map
cp "${PKG_SRC}/ICON.PNG" "${PKG_SRC}/ICON_256.PNG" "${PKG_DIR}/"
for sc in "${PKG_SRC}"/*.sc; do
    [ -e "${sc}" ] && cp "${sc}" "${PKG_DIR}/"
done
# 5. manifest with build-specific fields
cp "${PKG_SRC}/manifest" "${PKG_DIR}/manifest"
sed -E -i "s|^version[[:space:]]*=.*|version         = ${VERSION}|" "${PKG_DIR}/manifest"
sed -E -i "s|^platform[[:space:]]*=.*|platform        = ${PLATFORM}|" "${PKG_DIR}/manifest"
sed -E -i "s|^checksum[[:space:]]*=.*|checksum        = ${CHECKSUM}|" "${PKG_DIR}/manifest"

FPK_NAME="${APPNAME}_${VERSION}_${PLATFORM}.fpk"
( cd "${PKG_DIR}" && tar -czf "${OUT_DIR}/${FPK_NAME}" * )

# Verify the packaged payload matches the checksum recorded in the manifest.
PACKED_CHECKSUM=$(tar -xzOf "${OUT_DIR}/${FPK_NAME}" app.tgz | md5sum | awk '{print $1}')
[ "${PACKED_CHECKSUM}" = "${CHECKSUM}" ] || die "checksum verification failed for ${FPK_NAME}"
[ "$(tar -xzOf "${OUT_DIR}/${FPK_NAME}" manifest | grep -E '^checksum' | cut -d '=' -f 2- | tr -d '[:space:]')" = "${CHECKSUM}" ] || die "manifest checksum mismatch in ${FPK_NAME}"

# fnOS reads the desktop/app-center entry from the payload (${TRIM_APPDEST}/ui),
# so refuse to publish a package whose app.tgz has no ui/config or icons.
mkdir -p "${WORK_DIR}/check_app"
tar -xzOf "${OUT_DIR}/${FPK_NAME}" app.tgz > "${WORK_DIR}/check_app.tgz"
tar -xzf "${WORK_DIR}/check_app.tgz" -C "${WORK_DIR}/check_app"
[ -f "${WORK_DIR}/check_app/ui/config" ] || die "app.tgz is missing ui/config (fnOS would register no app entry)"
[ -f "${WORK_DIR}/check_app/bin/music-dl" ] || die "app.tgz is missing bin/music-dl"
for size in 64 256; do
    [ -f "${WORK_DIR}/check_app/ui/images/icon_${size}.png" ] || die "app.tgz is missing ui/images/icon_${size}.png"
done

echo "[build-fpk] wrote ${OUT_DIR}/${FPK_NAME} (${FPK_NAME})"
