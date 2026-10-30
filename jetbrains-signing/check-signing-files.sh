#!/usr/bin/env bash
# Checks the key and certificate: the password opens the key, the certificate is the key's,
# and how long the certificate has left.
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/config.sh"
source "$here/lib.sh"

require_files
read_password

key_pub="$(openssl pkey -in "$KEY" -passin env:SIGNING_PASSWORD -pubout)"
cert_pub="$(openssl x509 -in "$CERT" -noout -pubkey)"
[ "$key_pub" = "$cert_pub" ] || die "$CERT was not made from $KEY"

echo "The key opens and the certificate is its own."
openssl x509 -in "$CERT" -noout -subject -enddate -fingerprint -sha256
if ! openssl x509 -in "$CERT" -noout -checkend $((90 * 24 * 3600)) >/dev/null; then
    echo "warning: the certificate expires within 90 days: replace the identity (README, Updating)" >&2
fi
