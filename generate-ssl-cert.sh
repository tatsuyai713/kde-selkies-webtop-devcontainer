#!/usr/bin/env bash
set -euo pipefail

# Default values
SSL_DIR="${SSL_DIR:-$(pwd)/ssl}"
DAYS=${DAYS:-365}
CN=${CN:-localhost}
SUBJECT=${SUBJECT:-}
CREATE_CA=${CREATE_CA:-true}
FORCE=${FORCE:-false}
NEW_CA=${NEW_CA:-false}
AUTO_SAN=${AUTO_SAN:-true}
EXTRA_SANS=()

usage() {
  cat <<EOF
Usage: $0 [-d ssl_dir] [-n days] [-c common_name] [-s subject] [--san name_or_ip] [--no-ca] [--new-ca] [-f]
  -d  output directory for certificates (default: ./ssl)
  -n  validity period in days (default: 365)
  -c  common name / hostname (default: localhost)
  -s  full subject string (overrides -c)
  --san  add a DNS name or IP address to Subject Alternative Names (repeatable)
  --no-ca  create self-signed cert without CA (simpler but less secure)
  --new-ca  replace the existing local CA as well as the server certificate
  -f  force overwrite existing certificates

Output files:
  ssl/ca.crt          - Certificate Authority (if --no-ca not used)
  ssl/ca.key          - CA private key (keep secure!)
  ssl/cert.pem        - Server certificate
  ssl/cert.key        - Server private key

Examples:
  $0                          # Generate certs for localhost
  $0 -c myhost.local          # Generate certs for custom hostname
  $0 --san desktop.local --san 192.168.1.10
  $0 -c "*.local" -n 730      # Wildcard cert, 2 years validity
  $0 --no-ca                  # Simple self-signed (no CA)
  $0 -f                       # Reissue server cert and keep the trusted CA
  $0 -f --new-ca              # Replace both server cert and CA
EOF
}

# Parse options
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d) SSL_DIR="$2"; shift 2 ;;
    -n) DAYS="$2"; shift 2 ;;
    -c) CN="$2"; shift 2 ;;
    -s) SUBJECT="$2"; shift 2 ;;
    --san) EXTRA_SANS+=("$2"); shift 2 ;;
    --no-ca) CREATE_CA=false; shift ;;
    --new-ca) NEW_CA=true; shift ;;
    -f) FORCE=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

# Check if certificates already exist
if [[ -f "${SSL_DIR}/cert.pem" && "${FORCE}" != "true" ]]; then
  echo "Certificate already exists at ${SSL_DIR}/cert.pem"
  echo "Use -f to force overwrite."
  exit 1
fi

if [[ ! "${DAYS}" =~ ^[1-9][0-9]*$ ]]; then
  echo "Validity period must be a positive number of days: ${DAYS}" >&2
  exit 1
fi

# Modern browsers validate Subject Alternative Names, not the Common Name.
# Include names and addresses that this host can actually be reached through so
# the documented LAN URL works without a certificate name mismatch.
DNS_SANS=(localhost "*.localhost")
IP_SANS=(127.0.0.1 ::1)

add_san() {
  local value="$1"
  [[ -n "${value}" ]] || return 0
  case "${value}" in
    DNS:*) DNS_SANS+=("${value#DNS:}") ;;
    IP:*) IP_SANS+=("${value#IP:}") ;;
    *:*) IP_SANS+=("${value}") ;;
    *[!0-9.]* ) DNS_SANS+=("${value}") ;;
    *) IP_SANS+=("${value}") ;;
  esac
}

add_san "${CN}"
if [[ "${AUTO_SAN}" == "true" ]]; then
  add_san "$(hostname 2>/dev/null || true)"
  add_san "$(hostname -f 2>/dev/null || true)"
  while IFS= read -r host_ip; do
    add_san "${host_ip}"
  done < <(hostname -I 2>/dev/null | tr ' ' '\n' | sed '/^$/d')
fi
for extra_san in "${EXTRA_SANS[@]}"; do
  add_san "${extra_san}"
done

deduplicate_array() {
  local -n values_ref="$1"
  local -A seen=()
  local value
  local unique=()
  for value in "${values_ref[@]}"; do
    if [[ -n "${value}" && -z "${seen[${value}]+x}" ]]; then
      seen["${value}"]=1
      unique+=("${value}")
    fi
  done
  values_ref=("${unique[@]}")
}

deduplicate_array DNS_SANS
deduplicate_array IP_SANS

# Create SSL directory
mkdir -p "${SSL_DIR}"

# Build subject string
if [[ -z "${SUBJECT}" ]]; then
  SUBJECT="/C=US/ST=State/L=City/O=Development/CN=${CN}"
fi

echo "Generating SSL certificates..."
echo "  Output: ${SSL_DIR}/"
echo "  Common Name: ${CN}"
echo "  DNS SANs: ${DNS_SANS[*]}"
echo "  IP SANs: ${IP_SANS[*]}"
echo "  Validity: ${DAYS} days"
echo ""

if [[ "${CREATE_CA}" == "true" ]]; then
  # Method 1: Create CA + signed certificate (recommended)
  if [[ -f "${SSL_DIR}/ca.crt" && -f "${SSL_DIR}/ca.key" && "${NEW_CA}" != "true" ]]; then
    echo "Reusing existing Certificate Authority (registered trust remains valid)..."
  elif [[ -e "${SSL_DIR}/ca.crt" || -e "${SSL_DIR}/ca.key" ]] && [[ "${NEW_CA}" != "true" ]]; then
    echo "Existing CA is incomplete; both ca.crt and ca.key are required." >&2
    echo "Restore the missing file or use --new-ca to replace the CA." >&2
    exit 1
  else
    echo "Creating Certificate Authority..."
    openssl genrsa -out "${SSL_DIR}/ca.key" 4096 2>/dev/null
    openssl req -new -x509 -days "${DAYS}" \
      -key "${SSL_DIR}/ca.key" \
      -out "${SSL_DIR}/ca.crt" \
      -subj "/C=US/ST=State/L=City/O=Development CA/CN=Local Development CA" \
      -addext "basicConstraints=critical,CA:TRUE" \
      -addext "keyUsage=critical,keyCertSign,cRLSign" \
      -addext "subjectKeyIdentifier=hash" \
      2>/dev/null
  fi
  
  echo "Creating server certificate signed by CA..."
  
  # Generate server private key
  openssl genrsa -out "${SSL_DIR}/cert.key" 2048 2>/dev/null
  
  # Generate certificate signing request
  openssl req -new \
    -key "${SSL_DIR}/cert.key" \
    -out "${SSL_DIR}/cert.csr" \
    -subj "${SUBJECT}" \
    2>/dev/null
  
  # Create extensions file for SAN (Subject Alternative Names)
  cat > "${SSL_DIR}/cert.ext" <<EOF
[server_cert]
authorityKeyIdentifier=keyid,issuer
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName = @alt_names

[alt_names]
EOF

  san_index=1
  for dns_san in "${DNS_SANS[@]}"; do
    printf 'DNS.%d = %s\n' "${san_index}" "${dns_san}" >> "${SSL_DIR}/cert.ext"
    san_index=$((san_index + 1))
  done
  san_index=1
  for ip_san in "${IP_SANS[@]}"; do
    printf 'IP.%d = %s\n' "${san_index}" "${ip_san}" >> "${SSL_DIR}/cert.ext"
    san_index=$((san_index + 1))
  done
  
  # Sign server certificate with CA
  openssl x509 -req -days "${DAYS}" \
    -in "${SSL_DIR}/cert.csr" \
    -CA "${SSL_DIR}/ca.crt" \
    -CAkey "${SSL_DIR}/ca.key" \
    -CAcreateserial \
    -out "${SSL_DIR}/cert.pem" \
    -extfile "${SSL_DIR}/cert.ext" \
    -extensions server_cert \
    2>/dev/null
  
  # Cleanup temporary files
  rm -f "${SSL_DIR}/cert.csr" "${SSL_DIR}/cert.ext" "${SSL_DIR}/ca.srl"
  
  # Set permissions
  chmod 600 "${SSL_DIR}/ca.key" "${SSL_DIR}/cert.key"
  chmod 644 "${SSL_DIR}/ca.crt" "${SSL_DIR}/cert.pem"
  
  echo ""
  echo "=== Certificate Authority Ready ==="
  echo "  CA Certificate: ${SSL_DIR}/ca.crt"
  echo "  CA Private Key: ${SSL_DIR}/ca.key (keep secure!)"
  echo ""
  echo "=== Server Certificate Created ==="
  echo "  Certificate: ${SSL_DIR}/cert.pem"
  echo "  Private Key: ${SSL_DIR}/cert.key"
  echo ""
  echo "=== Next Steps ==="
  echo "1. Trust the CA certificate on your system:"
  echo ""
  echo "   macOS (Keychain - this covers Chrome, Safari, and all apps):"
  echo "     First, copy ca.crt to your Mac:"
  echo "       scp <user>@<host>:${SSL_DIR}/ca.crt ~/Desktop/ca.crt"
  echo "     Command line:"
  echo "       sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ~/Desktop/ca.crt"
  echo "     GUI:"
  echo "       1. Double-click ~/Desktop/ca.crt to open in Keychain Access"
  echo "       2. It will be added to the 'login' keychain"
  echo "       3. Find 'Local Development CA' in the list, double-click it"
  echo "       4. Expand 'Trust' section"
  echo "       5. Set 'When using this certificate' to 'Always Trust'"
  echo "       6. Close the window and enter your password to confirm"
  echo "     Then fully restart the browser."
  echo ""
  echo "   Linux (Ubuntu/Debian) - system level (curl, wget, etc.):"
  echo "     sudo cp ${SSL_DIR}/ca.crt /usr/local/share/ca-certificates/local-dev-ca.crt"
  echo "     sudo update-ca-certificates"
  echo ""
  echo "2. Trust the CA certificate in Chrome/Chromium browser:"
  echo "   Chrome uses its own NSS database, NOT the system CA store."
  echo "   Without this step, you will see ERR_CERT_AUTHORITY_INVALID."
  echo ""
  echo "   Install certutil if not available:"
  echo "     sudo apt install -y libnss3-tools"
  echo ""
  echo "   Create NSS database (if it does not exist):"
  echo "     mkdir -p \$HOME/.pki/nssdb"
  echo "     certutil -d sql:\$HOME/.pki/nssdb -N --empty-password"
  echo ""
  echo "   Register the CA certificate:"
  echo "     certutil -d sql:\$HOME/.pki/nssdb -A -t \"C,,\" -n \"Local Development CA\" -i ${SSL_DIR}/ca.crt"
  echo ""
  echo "   Verify:"
  echo "     certutil -d sql:\$HOME/.pki/nssdb -L"
  echo ""
  echo "   Then fully restart the browser (close all windows and background processes)."
  echo ""
  echo "   Firefox (snap):"
  echo "     certutil -d sql:\$HOME/snap/firefox/common/.mozilla/firefox/*.default -A -t \"C,,\" -n \"Local Development CA\" -i ${SSL_DIR}/ca.crt"
  echo ""
  echo "   Windows (Chrome uses the Windows certificate store):"
  echo "     Copy ca.crt to your Windows machine, then run in PowerShell (Admin):"
  echo "       Import-Certificate -FilePath .\\ca.crt -CertStoreLocation Cert:\\LocalMachine\\Root"
  echo "     Or double-click ca.crt → Install Certificate → Local Machine"
  echo "       → Place all certificates in the following store → Trusted Root Certification Authorities"
  echo "     Then fully restart Chrome."
  echo ""
  echo "   WSL: To copy the cert to Windows:"
  echo "     cp ${SSL_DIR}/ca.crt /mnt/c/Users/\$USER/Desktop/ca.crt"
  echo ""
  echo "3. Start the container (SSL auto-detected from ./ssl/):"
  echo "     ./start-container.sh --encoder nvidia --gpu all"
  echo ""
  
else
  # Method 2: Simple self-signed certificate (no CA)
  echo "Creating self-signed certificate (no CA)..."
  
  SAN_LIST=""
  for dns_san in "${DNS_SANS[@]}"; do SAN_LIST+="DNS:${dns_san},"; done
  for ip_san in "${IP_SANS[@]}"; do SAN_LIST+="IP:${ip_san},"; done
  SAN_LIST="${SAN_LIST%,}"
  openssl req -x509 -nodes -days "${DAYS}" -newkey rsa:2048 \
    -keyout "${SSL_DIR}/cert.key" \
    -out "${SSL_DIR}/cert.pem" \
    -subj "${SUBJECT}" \
    -addext "basicConstraints=critical,CA:FALSE" \
    -addext "keyUsage=critical,digitalSignature,keyEncipherment" \
    -addext "extendedKeyUsage=serverAuth" \
    -addext "subjectAltName=${SAN_LIST}" \
    2>/dev/null
  
  chmod 600 "${SSL_DIR}/cert.key"
  chmod 644 "${SSL_DIR}/cert.pem"
  
  echo ""
  echo "=== Self-Signed Certificate Created ==="
  echo "  Certificate: ${SSL_DIR}/cert.pem"
  echo "  Private Key: ${SSL_DIR}/cert.key"
  echo ""
  echo "Note: Browsers will show security warnings for self-signed certificates."
  echo "Use without --no-ca to create a CA that can be trusted system-wide."
  echo ""
fi

echo "Done!"
