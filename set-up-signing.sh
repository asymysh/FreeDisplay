#!/bin/bash
# FreeDisplay — one-time setup of a STABLE self-signed code-signing identity.
#
# WHY: build-local.sh normally ad-hoc-signs the app. Ad-hoc signatures have no stable
# identity — the code hash changes on every build — so macOS TCC forgets every
# permission you grant (Screen Recording, Accessibility) after each rebuild.
#
# This creates a persistent self-signed code-signing certificate in a DEDICATED keychain
# (with a known password, so there are no interactive prompts) and lets `codesign` use
# it. After running this once, build-local.sh signs with this identity, the app's
# designated requirement becomes cert-based (stable across rebuilds), and you only need
# to grant each permission ONCE.
#
# It weakens no system security: the cert is self-signed and untrusted for verification
# (that's fine — TCC matches on the code requirement, not on a trusted chain).
#
# Usage:  ./set-up-signing.sh
set -euo pipefail

DIR="$HOME/.freedisplay-signing"
KC="$DIR/fd-signing.keychain-db"
KCPASS="fdlocal"
CN="FreeDisplay Local Signing"

mkdir -p "$DIR"; cd "$DIR"

echo "==> Generating self-signed code-signing certificate (valid 10 years)…"
cat > openssl.cnf <<'CNF'
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = FreeDisplay Local Signing
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 3650 -nodes \
  -config openssl.cnf >/dev/null 2>&1

echo "==> Packaging as PKCS#12 (legacy 3DES so Apple's Security framework accepts it)…"
# OpenSSL 3 defaults to PBKDF2/AES which `security import` cannot read; force legacy algos.
LEGACY=""
openssl version | grep -q "OpenSSL 3" && LEGACY="-legacy"
openssl pkcs12 -export -inkey key.pem -in cert.pem -out cert.p12 \
  -passout pass:"$KCPASS" -name "$CN" \
  -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 $LEGACY >/dev/null 2>&1

echo "==> Creating dedicated keychain and importing the identity…"
security delete-keychain "$KC" 2>/dev/null || true
security create-keychain -p "$KCPASS" "$KC"
security set-keychain-settings "$KC"                 # no auto-lock
security unlock-keychain -p "$KCPASS" "$KC"
# Add to the user search list without dropping the login keychain.
EXISTING=$(security list-keychains -d user | sed 's/[",]//g' | xargs)
security list-keychains -d user -s $EXISTING "$KC"
security import "$DIR/cert.p12" -k "$KC" -P "$KCPASS" -T /usr/bin/codesign -A
# Let codesign use the private key without a GUI prompt.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KCPASS" "$KC" >/dev/null 2>&1

echo ""
echo "==> Done. Identity installed:"
security find-identity -p codesigning "$KC" 2>&1 | grep "$CN" | sed 's/^/    /'
echo ""
echo "Next: ./build-local.sh install    (now signs with the stable identity)"
echo "Then grant Screen Recording ONCE — it will persist across all future rebuilds."
