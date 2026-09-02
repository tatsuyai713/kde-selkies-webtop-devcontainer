#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CA_CERT="${1:-${SCRIPT_DIR}/ssl/ca.crt}"
CERT_NICKNAME="Webtop Local Development CA"

if [[ ! -f "${CA_CERT}" ]]; then
  echo "CA certificate not found: ${CA_CERT}" >&2
  exit 1
fi

# Chromium M146+ defaults to ~/.local/share/pki/nssdb, but keeps using the
# legacy ~/.pki/nssdb when that database already exists.
if [[ -d "${HOME}/.pki/nssdb" ]]; then
  NSS_DB="${HOME}/.pki/nssdb"
else
  NSS_DB="${HOME}/.local/share/pki/nssdb"
fi
mkdir -p "${NSS_DB}"

TEMP_DIR=""
cleanup() {
  if [[ -n "${TEMP_DIR}" && -d "${TEMP_DIR}" ]]; then
    rm -rf -- "${TEMP_DIR}"
  fi
}
trap cleanup EXIT

if command -v certutil >/dev/null 2>&1; then
  CERTUTIL="$(command -v certutil)"
else
  if ! command -v apt-get >/dev/null 2>&1 || ! command -v dpkg-deb >/dev/null 2>&1; then
    echo "certutil is required. Install the libnss3-tools package first." >&2
    exit 1
  fi
  echo "certutil is not installed; downloading libnss3-tools without system installation..."
  TEMP_DIR="$(mktemp -d /tmp/webtop-nss-tools.XXXXXX)"
  (
    cd "${TEMP_DIR}"
    apt-get download libnss3-tools
  )
  DEB_FILES=("${TEMP_DIR}"/libnss3-tools_*.deb)
  if [[ ! -f "${DEB_FILES[0]}" ]]; then
    echo "Failed to download libnss3-tools." >&2
    exit 1
  fi
  dpkg-deb -x "${DEB_FILES[0]}" "${TEMP_DIR}/extracted"
  CERTUTIL="${TEMP_DIR}/extracted/usr/bin/certutil"
fi

if [[ ! -f "${NSS_DB}/cert9.db" ]]; then
  "${CERTUTIL}" -d "sql:${NSS_DB}" -N --empty-password
fi

"${CERTUTIL}" -d "sql:${NSS_DB}" -D -n "${CERT_NICKNAME}" 2>/dev/null || true
"${CERTUTIL}" -d "sql:${NSS_DB}" -A -t "C,," \
  -n "${CERT_NICKNAME}" -i "${CA_CERT}"

echo "Chrome trust registration completed:"
echo "  NSS DB: ${NSS_DB}"
"${CERTUTIL}" -d "sql:${NSS_DB}" -L -n "${CERT_NICKNAME}"
echo "Fully quit and restart Chrome before reconnecting."
