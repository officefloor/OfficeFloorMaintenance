#!/usr/bin/env bash
# Sets up the OfficeFloor organisation to publish IntelliJ plugins to the JetBrains Marketplace:
# the organisation secrets the plugin repositories' release workflows read. Each step asks first:
#
#   1. Signing: makes the OfficeFloor signing identity, an encrypted RSA key and a self-signed
#      certificate, and sets CERTIFICATE_CHAIN, PRIVATE_KEY and PRIVATE_KEY_PASSWORD.
#   2. Publishing: sets PUBLISH_TOKEN, a Marketplace token you create.
#   3. Access: makes the repositories that may read the secrets those listed in
#      jetbrains-plugin-repositories.txt. (Steps 1 and 2 already give a secret they set that
#      list; this is for the others, and for when the list changes.)
#
# Run once to set up, and again after editing the list (answering no to 1 and 2). All steps
# share one temporary GitHub token (admin:org) made for the run. Run it in your own terminal.
#
# DRY_RUN=1 makes a throwaway key and shows what would be done, sending nothing.
set -euo pipefail

ORG=officefloor
SECRETS=(PUBLISH_TOKEN CERTIFICATE_CHAIN PRIVATE_KEY PRIVATE_KEY_PASSWORD)
SUBJECT="/CN=OfficeFloor/O=OfficeFloor/OU=IntelliJ Plugins"
DAYS=9125   # 25 years: if the key is ever lost, a new identity replaces it (README)

here="$(cd "$(dirname "$0")" && pwd)"
REPO_LIST="$here/jetbrains-plugin-repositories.txt"
CERT_COPY="$here/jetbrains-signing-certificate.crt"   # public: committed, for registering later

die() { echo "error: $*" >&2; exit 1; }

# on exit, however it ends: the generated files go, and a reminder to delete the GitHub token
WORK=""
cleanup() {
    [ -z "$WORK" ] || rm -rf "$WORK"
    if [ -n "${GH_TOKEN:-}" ] && [ -z "${DRY_RUN:-}" ]; then
        echo; echo "Done with the GitHub token: delete it now at https://github.com/settings/tokens (it also expires by itself)."
    fi
}
trap cleanup EXIT

ask() {   # ask "question" -> 0 for yes
    local answer
    read -rp "$1 [y/N] " answer
    [[ "$answer" == [yY]* ]]
}

open_browser() {
    if command -v xdg-open >/dev/null; then
        xdg-open "$1" >/dev/null 2>&1 &
    elif command -v open >/dev/null; then
        open "$1"
    fi
    echo "(if no browser opened: $1)"
}

# The repositories from the list file: one name per line, # comments and blank lines ignored
REPOS=()
while IFS= read -r line; do
    line="${line%%#*}"
    line="$(echo "$line" | tr -d '[:space:]')"
    [ -z "$line" ] && continue
    [[ "$line" =~ ^[A-Za-z0-9._-]+$ ]] || die "$(basename "$REPO_LIST"): not a repository name: $line"
    REPOS+=("$line")
done < "$REPO_LIST"
[ ${#REPOS[@]} -gt 0 ] || die "$(basename "$REPO_LIST") lists no repositories"
REPO_CSV="$(IFS=,; echo "${REPOS[*]}")"

# The temporary GitHub token: asked for once, the first time GitHub is to be changed. gh's own
# login is never used, and a GH_TOKEN already set is ignored.
unset GH_TOKEN GITHUB_TOKEN
github_access() {
    [ -n "${GH_TOKEN:-}" ] && return
    [ -n "${DRY_RUN:-}" ] && { echo "(dry run: no GitHub token needed)"; GH_TOKEN=dry-run; return; }
    cat <<EOF

Changing organisation secrets needs a temporary GitHub token with the admin:org scope, used for
this run only.

  1. Press Enter to open GitHub's "New personal access token (classic)" page.
     The note and the admin:org scope are filled in already.
  2. Expiration: choose "Custom" and pick tomorrow (or the shortest offered).
  3. Check that admin:org is the only scope ticked, then "Generate token" at the bottom.
  4. Copy the token (ghp_...) and paste it here.

You must be an owner of the $ORG organisation.
EOF
    read -rp "Press Enter to open the browser (or Ctrl+C to stop)... "
    open_browser "https://github.com/settings/tokens/new?scopes=admin:org&description=OfficeFloor%20JetBrains%20setup%20(temporary)"
    read -rsp "Paste the GitHub token: " GH_TOKEN; echo
    [ -n "$GH_TOKEN" ] || die "no token given"
    export GH_TOKEN
    local scopes
    scopes="$(gh api -i user 2>/dev/null | tr -d '\r' | sed -n 's/^[Xx]-[Oo][Aa]uth-[Ss]copes: //p')" \
        || die "GitHub did not accept that token"
    [[ ", $scopes," == *", admin:org,"* ]] || die "that token lacks admin:org (it has: ${scopes:-none})"
}

SET_NOW=" "   # the secrets set in this run, which already have the list's access
set_secret() {   # set_secret NAME < value
    if [ -n "${DRY_RUN:-}" ]; then
        cat >/dev/null
        echo "would set $1 in $ORG for $REPO_CSV"
    else
        gh secret set "$1" --org "$ORG" --visibility selected --repos "$REPO_CSV"
        echo "set $1 in $ORG for $REPO_CSV"
    fi
    SET_NOW+="$1 "
}

setup_signing() {
    cat <<EOF

== 1. Signing ==
Makes the OfficeFloor signing identity, an encrypted RSA key and a self-signed certificate
($SUBJECT),
and sets CERTIFICATE_CHAIN, PRIVATE_KEY and PRIVATE_KEY_PASSWORD.
Setting them again replaces the identity the plugins are signed with.
EOF
    ask "Set up the signing keys?" || return 0

    local password confirm
    if [ -n "${SIGNING_PASSWORD:-}" ]; then
        password="$SIGNING_PASSWORD"
    else
        read -rsp "Choose a password for the private key: " password; echo
        read -rsp "Again: " confirm; echo
        [ "$password" = "$confirm" ] || die "the passwords differ"
    fi
    [ ${#password} -ge 8 ] || die "use at least 8 characters"
    export SIGNING_PASSWORD="$password"

    WORK="$(umask 077; mktemp -d)"
    local work="$WORK"
    openssl genpkey -aes-256-cbc -algorithm RSA -pkeyopt rsa_keygen_bits:4096 \
        -pass env:SIGNING_PASSWORD -out "$work/private_encrypted.pem" 2>/dev/null
    openssl req -key "$work/private_encrypted.pem" -passin env:SIGNING_PASSWORD \
        -new -x509 -days "$DAYS" -subj "$SUBJECT" -out "$work/chain.crt"
    echo "Made the key and certificate:"
    openssl x509 -in "$work/chain.crt" -noout -subject -enddate -fingerprint -sha256

    github_access
    set_secret CERTIFICATE_CHAIN < "$work/chain.crt"
    set_secret PRIVATE_KEY < "$work/private_encrypted.pem"
    set_secret PRIVATE_KEY_PASSWORD < <(printf '%s' "$password")

    if [ -n "${DRY_RUN:-}" ]; then
        echo "(dry run: $(basename "$CERT_COPY") left as it is)"
    else
        cp "$work/chain.crt" "$CERT_COPY"
    fi
    if ask "Keep a copy of the private key for a password manager (it is otherwise deleted)?"; then
        local keep="$HOME/officefloor-jetbrains-signing"
        (umask 077; mkdir -p "$keep")
        cp "$work/private_encrypted.pem" "$work/chain.crt" "$keep/"
        echo "Copied to $keep: save both files and the password, then delete it."
    else
        echo "Deleting the private key: if it is ever needed again, a new identity replaces it (README)."
    fi

    cat <<EOF

Register the public key with the Marketplace:
  JetBrains plans for authors to upload their public key to their Marketplace profile, after
  which only uploads signed with a registered key are accepted. Their documentation says this
  is "not available yet" (https://plugins.jetbrains.com/docs/intellij/plugin-signing.html), and
  there is no API for it. When it is offered:
    1. Sign in at https://plugins.jetbrains.com with the account that publishes the plugins.
    2. In the profile, add the certificate: $CERT_COPY
       (committed to this repository, so it is there when needed).
Now commit $(basename "$CERT_COPY") to this repository.
EOF
}

setup_publish_token() {
    cat <<EOF

== 2. Publishing ==
Sets PUBLISH_TOKEN, the JetBrains Marketplace token the release workflows upload with. It
belongs to a JetBrains account, which must be able to publish every plugin (the owner, or a
member of the vendor organisation they are under).
EOF
    ask "Set up PUBLISH_TOKEN?" || return 0
    cat <<EOF

  1. Press Enter to open the Marketplace's token page (sign in if asked, with that account).
  2. "Generate Token", name it e.g. "OfficeFloor GitHub releases", and copy it (shown once).
  3. Paste it here.
EOF
    read -rp "Press Enter to open the browser... "
    open_browser "https://plugins.jetbrains.com/author/me/tokens"
    local token
    read -rsp "Paste the Marketplace token: " token; echo
    [ -n "$token" ] || die "no token given"
    github_access
    set_secret PUBLISH_TOKEN < <(printf '%s' "$token")
}

update_access() {
    local name remaining=()
    for name in "${SECRETS[@]}"; do
        [[ "$SET_NOW" == *" $name "* ]] || remaining+=("$name")
    done
    [ ${#remaining[@]} -gt 0 ] || return 0
    cat <<EOF

== 3. Repositories with access ==
Makes the repositories that may read ${remaining[*]}
exactly those in $(basename "$REPO_LIST"): $REPO_CSV
EOF
    ask "Update the repositories with access?" || return 0
    github_access

    if [ -n "${DRY_RUN:-}" ]; then
        for name in "${remaining[@]}"; do echo "would give $name to: $REPO_CSV"; done
        return 0
    fi
    local repo id ids=()
    for repo in "${REPOS[@]}"; do
        id="$(gh api "repos/$ORG/$repo" --jq .id 2>/dev/null)" || die "no repository $ORG/$repo"
        ids+=("$id")
    done
    local body
    body="{\"selected_repository_ids\":[$(IFS=,; echo "${ids[*]}")]}"
    for name in "${remaining[@]}"; do
        local visibility
        if ! visibility="$(gh api "orgs/$ORG/actions/secrets/$name" --jq .visibility 2>/dev/null)"; then
            echo "$name is not set in $ORG: skipped (set it with step 1 or 2)"
            continue
        fi
        [ "$visibility" = selected ] || die "$name is visible to '$visibility' repositories, not selected ones: set it again with step 1 or 2"
        gh api -X PUT "orgs/$ORG/actions/secrets/$name/repositories" --input - <<<"$body" >/dev/null
        echo "$name: $(gh api "orgs/$ORG/actions/secrets/$name/repositories" --jq '[.repositories[].name] | join(", ")')"
    done
}

command -v openssl >/dev/null || die "needs openssl"
command -v gh >/dev/null || die "needs the GitHub CLI, gh"
echo "Sets up the $ORG organisation's secrets for publishing plugins to the JetBrains Marketplace,"
echo "for the repositories in $(basename "$REPO_LIST"): $REPO_CSV"
setup_signing
setup_publish_token
update_access
cat <<EOF

A repository secret of the same name as one of these would override the organisation's, so the
plugin repositories must not set their own.
EOF
