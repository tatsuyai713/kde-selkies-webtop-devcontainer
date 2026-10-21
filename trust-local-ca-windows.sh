#!/usr/bin/env bash
# ==============================================================================
# trust-local-ca-windows.sh - trust ssl/ca.crt in the Windows certificate store
#                             (run inside WSL2)
#
# Adds the local development CA to "Trusted Root Certification Authorities" of
# the current Windows user (Cert:\CurrentUser\Root; no administrator rights).
# Chrome and Edge on Windows use that store, so https://localhost:<port> of the
# container opens without a certificate warning. Windows shows a security
# warning with the thumbprint before adding a root CA: confirm with "Yes".
# Firefox keeps its own store (about:config: security.enterprise_roots.enabled
# = true makes it use the Windows one).
#
# Usage: trust-local-ca-windows.sh [--remove] [ca.crt]
#   (default ca.crt: ssl/ca.crt next to this script)
#   --remove   remove this CA from the Windows user store again
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOVE=false
CA_CERT=""
for a in "$@"; do
  case "$a" in
    --remove) REMOVE=true ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    *) CA_CERT="$a" ;;
  esac
done
CA_CERT="${CA_CERT:-${SCRIPT_DIR}/ssl/ca.crt}"

if ! grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null || ! command -v powershell.exe >/dev/null 2>&1; then
  echo "This script must run inside WSL2 with Windows interop (powershell.exe)." >&2
  exit 1
fi
if [[ ! -f "${CA_CERT}" ]]; then
  echo "CA certificate not found: ${CA_CERT} (create it with ./generate-ssl-cert.sh)" >&2
  exit 1
fi

THUMBPRINT="$(openssl x509 -in "${CA_CERT}" -noout -fingerprint -sha1 | sed 's/.*=//; s/://g')"
SUBJECT="$(openssl x509 -in "${CA_CERT}" -noout -subject | sed 's/^subject=//')"
EXPIRES="$(openssl x509 -in "${CA_CERT}" -noout -enddate | sed 's/^notAfter=//')"
echo "CA:         ${SUBJECT}"
echo "Thumbprint: ${THUMBPRINT}"
echo "Expires:    ${EXPIRES}"

# not -NonInteractive: adding/removing a user root CA needs the Windows confirmation dialog
ps() { powershell.exe -NoProfile -Command "$1" | tr -d '\r'; }
registered() {
  [[ "$(ps "if (Get-ChildItem Cert:\\CurrentUser\\Root | Where-Object Thumbprint -eq '${THUMBPRINT}') { 'yes' }")" == yes ]]
}

if [[ "${REMOVE}" == true ]]; then
  if ! registered; then
    echo "Not registered in Cert:\\CurrentUser\\Root; nothing to remove."
    exit 0
  fi
  echo "Removing it from Cert:\\CurrentUser\\Root (confirm the Windows dialog with \"Yes\")..."
  ps "Remove-Item -Path 'Cert:\\CurrentUser\\Root\\${THUMBPRINT}'" || true
  if registered; then echo "Still registered (the removal was declined?)." >&2; exit 1; fi
  echo "Removed. Restart the browser."
  exit 0
fi

if registered; then
  echo "Already trusted by Windows (Cert:\\CurrentUser\\Root); nothing to do."
  exit 0
fi

# Import from a Windows-local copy: reading \\wsl.localhost\... paths is not
# reliable in every PowerShell / policy setup.
WIN_TEMP="$(ps '[IO.Path]::GetTempPath()')"
LOCAL_COPY="$(wslpath -u "${WIN_TEMP}")/webtop-local-ca-${THUMBPRINT}.crt"
cp "${CA_CERT}" "${LOCAL_COPY}"
WIN_COPY="$(wslpath -w "${LOCAL_COPY}")"
trap 'rm -f "${LOCAL_COPY}"' EXIT

echo "Adding it to Cert:\\CurrentUser\\Root."
echo "Windows will show a security warning: check that the thumbprint matches and click \"Yes\"."
ps "Import-Certificate -FilePath '${WIN_COPY}' -CertStoreLocation Cert:\\CurrentUser\\Root | Out-Null" || true

if registered; then
  echo "OK: Windows now trusts this CA."
  echo "Fully quit Chrome / Edge (including background processes) and open https://localhost:<HTTPS port> again."
else
  echo "The CA was not added (the dialog was declined, or the import failed)." >&2
  exit 1
fi
