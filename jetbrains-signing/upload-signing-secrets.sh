#!/usr/bin/env bash
# Puts the key, its password and the certificate in the organisation's secrets, available to
# the repositories in .config.sh. Re-run after create-signing-identity.sh, or to reset the
# repository list to .config.sh's.
# DRY_RUN=1 ./upload-signing-secrets.sh shows what it would do.
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/.config.sh"
source "$here/.lib.sh"

require_files
read_password
"$here/check-signing-files.sh"
org_access

repos="$(repo_list)"
echo "Setting $SECRET_CERT, $SECRET_KEY and $SECRET_PASSWORD in $ORG for: $repos"
run gh secret set "$SECRET_CERT" --org "$ORG" --visibility selected --repos "$repos" < "$CERT"
run gh secret set "$SECRET_KEY" --org "$ORG" --visibility selected --repos "$repos" < "$KEY"
if [ -n "${DRY_RUN:-}" ]; then
    echo "would run: gh secret set $SECRET_PASSWORD --org $ORG --visibility selected --repos $repos"
else
    printf '%s' "$SIGNING_PASSWORD" | gh secret set "$SECRET_PASSWORD" --org "$ORG" --visibility selected --repos "$repos"
fi

[ -n "${DRY_RUN:-}" ] || "$here/show-signing-secrets.sh"
cat <<EOF

Done. A repository must not set its own $SECRET_CERT, $SECRET_KEY or $SECRET_PASSWORD: a
repository secret overrides the organisation's.
EOF
