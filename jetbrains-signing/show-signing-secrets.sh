#!/usr/bin/env bash
# Shows the organisation's signing secrets: when each was last set, and which repositories
# can read it; and warns of any repository that overrides one with its own.
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/.config.sh"
source "$here/.lib.sh"

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
    # the temporary token has only admin:org, which cannot list a repository's own secrets, so
    # this check uses gh's login
    if ! own="$(env -u GH_TOKEN gh secret list -R "$ORG/$repo" --json name --jq '.[].name' 2>/dev/null)"; then
        echo "note: could not list $repo's own secrets to check for overrides" >&2
        continue
    fi
    for name in "$SECRET_CERT" "$SECRET_KEY" "$SECRET_PASSWORD"; do
        if grep -qx "$name" <<<"$own"; then
            echo "warning: $repo sets its own $name, which overrides the organisation's" >&2
        fi
    done
done
