#!/usr/bin/env bash
# Makes the OfficeFloor signing identity: an encrypted RSA key and a self-signed certificate.
# Run once, or to replace the identity (README). openssl asks for the key's new password
# (twice), then for it again to sign the certificate. Refuses to overwrite an existing key.
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/config.sh"
source "$here/lib.sh"

[ -e "$KEY" ] && die "$KEY already exists: to replace the identity, set SIGNING_DIR to an empty directory"
umask 077
mkdir -p "$DIR"

echo "Choosing the key's password: this is the $SECRET_PASSWORD secret."
if [ -n "${SIGNING_PASSWORD:-}" ]; then
    openssl genpkey -aes-256-cbc -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out "$KEY" -pass env:SIGNING_PASSWORD
else
    openssl genpkey -aes-256-cbc -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out "$KEY"
fi
with_password openssl req -key "$KEY" -new -x509 -days "$DAYS" -subj "$SUBJECT" -out "$CERT"

"$here/check-signing-files.sh"
cat <<EOF

Made $KEY and $CERT.
Now:
  1. Save both files and the password in the password manager (GitHub never shows a secret again).
  2. ./upload-signing-secrets.sh to put them in the $ORG organisation's secrets.
  3. Delete $DIR.
EOF
