#!/usr/bin/env bash
# Shows the organisation's signing secrets: when each was last set, and which repositories
# can read it; and warns of any repository that overrides one with its own.
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/config.sh"
source "$here/lib.sh"

org_access
for name in "$SECRET_CERT" "$SECRET_KEY" "$SECRET_PASSWORD"; do
    if ! updated="$(gh api "orgs/$ORG/actions/secrets/$name" --jq .updated_at 2>/dev/null)"; then
        echo "$name: not set in $ORG"
        continue
    fi
    repos="$(gh api "orgs/$ORG/actions/secrets/$name/repositories" --jq '[.repositories[].name] | join(", ")')"
    echo "$name: set $updated, for: $repos"
done
for repo in "${REPOS[@]}"; do
    own="$(gh secret list -R "$ORG/$repo" --json name --jq '.[].name' 2>/dev/null || true)"
    for name in "$SECRET_CERT" "$SECRET_KEY" "$SECRET_PASSWORD"; do
        if grep -qx "$name" <<<"$own"; then
            echo "warning: $repo sets its own $name, which overrides the organisation's" >&2
        fi
    done
done
