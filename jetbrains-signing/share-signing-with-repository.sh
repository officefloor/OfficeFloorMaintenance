#!/usr/bin/env bash
# Gives another repository the signing secrets that are already in the organisation, without
# needing the key: ./share-signing-with-repository.sh MyNewPlugin. Add it to REPOS in
# .config.sh too, so a later upload-signing-secrets.sh keeps it.
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/.config.sh"
source "$here/.lib.sh"

[ $# -eq 1 ] || die "usage: $0 <repository name in $ORG>"
repo="$1"
[[ " ${REPOS[*]} " == *" $repo "* ]] || echo "note: $repo is not in REPOS in .config.sh; add it there too" >&2

org_access
id="$(gh api "repos/$ORG/$repo" --jq .id)"
for name in "$SECRET_CERT" "$SECRET_KEY" "$SECRET_PASSWORD"; do
    run gh api -X PUT "orgs/$ORG/actions/secrets/$name/repositories/$id" --silent
    echo "$repo can read $name"
done
