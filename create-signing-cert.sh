#!/usr/bin/env bash
#
# Creates (or reuses) a stable, self-signed code-signing certificate and prints its identity
# name on stdout.
#
# Why this exists: an ad-hoc signature's code hash changes on every build, and both TCC and
# SMAppService pin their records to the signed identity -- so after each rebuild macOS treats
# the binary as a stranger and the login-item registration has to be approved again. A
# self-signed certificate gives a stable Designated Requirement and the registration survives.
#
# The identity name defaults to axshot's so one keychain approval covers both apps. The two
# apps stay independent regardless: those records key on bundle identifier, not on the
# certificate alone.
#
# Idempotent: if the identity already exists this is a no-op. Progress goes to stderr; only the
# identity name reaches stdout, so callers can capture it:
#
#     IDENTITY="$(./create-signing-cert.sh)"
#
# It never prompts. codesign needs permission to use the new key, which macOS asks for with a
# one-time "Always Allow" dialog on the first build. To skip that dialog, pass the login password:
#
#     DICTATION_GLOW_KEYCHAIN_PASSWORD='…' ./create-signing-cert.sh
set -euo pipefail

CERT_NAME="${DICTATION_GLOW_SIGN_IDENTITY:-Axshot Local Signing}"
KEYCHAIN="${DICTATION_GLOW_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"

log() { printf '%s\n' "$*" >&2; }

# Self-signed certs are untrusted, so they only appear under the default (X.509 Basic) policy,
# not `-p codesigning`. Match on the identity name.
if security find-identity "$KEYCHAIN" 2>/dev/null | grep -qF "$CERT_NAME"; then
	printf '%s\n' "$CERT_NAME"
	exit 0
fi

log "==> Creating self-signed code-signing certificate \"$CERT_NAME\" (valid 10 years)…"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions     = v3
prompt              = no
[ dn ]
CN = $CERT_NAME
[ v3 ]
basicConstraints     = critical,CA:FALSE
keyUsage             = critical,digitalSignature
extendedKeyUsage     = critical,codeSigning
EOF

# The key file is named after the identity because `security import` takes the key's keychain
# label from the filename: a key.pem leaves codesign asking for permission to use key "key",
# which says nothing about what is being signed or why.
openssl req -x509 -newkey rsa:2048 -nodes \
	-keyout "$TMP/$CERT_NAME.pem" -out "$TMP/cert.pem" \
	-days 3650 -config "$TMP/cert.cnf" >/dev/null 2>&1

# Import key and cert separately -- more reliable than a PKCS#12 across OpenSSL versions.
# -T /usr/bin/codesign puts codesign on the key's access list.
security import "$TMP/$CERT_NAME.pem" -k "$KEYCHAIN" -T /usr/bin/codesign >/dev/null
security import "$TMP/cert.pem"       -k "$KEYCHAIN" -T /usr/bin/codesign >/dev/null

if [ -n "${DICTATION_GLOW_KEYCHAIN_PASSWORD:-}" ]; then
	if security set-key-partition-list -S apple-tool:,apple: -s -k "$DICTATION_GLOW_KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null 2>&1; then
		log "==> codesign authorised to use the signing key."
	else
		log "warning: could not authorise the key; expect a one-time keychain prompt on first build."
	fi
else
	log "note: no password given, so expect a one-time \"Always Allow\" prompt on the first build."
fi

log "==> Certificate ready."
printf '%s\n' "$CERT_NAME"
