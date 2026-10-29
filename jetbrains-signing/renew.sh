#!/usr/bin/env bash
# Extends the certificate before it expires: a new certificate for the same key and subject,
# so the plugins keep the same signing identity. Then save it and run ./upload.sh.
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/config.sh"
source "$here/lib.sh"

require_files
read_password
umask 077
cp "$CERT" "$CERT.previous"
openssl req -key "$KEY" -passin env:SIGNING_PASSWORD -new -x509 -days "$DAYS" -subj "$SUBJECT" -out "$CERT"
"$here/check.sh"
cat <<EOF

Renewed $CERT (the old one is $CERT.previous).
Now save the new certificate in the password manager, run ./upload.sh, and delete $DIR.
EOF
