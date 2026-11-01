#!/usr/bin/env bash
# Sets up the OfficeFloor organisation to publish libraries to Maven Central with Gradle: the
# organisation secrets that the release workflows of the repositories in
# central-publishing-repositories.txt read, as ORG_GRADLE_PROJECT_mavenCentralUsername,
# mavenCentralPassword, signingInMemoryKey and signingInMemoryKeyPassword. The same Central
# account and signing key as OfficeFloor's own releases, whose secrets are its repository's.
# Each step asks first:
#
#   1. Central: sets SONATYPE_USERNAME and SONATYPE_PASSWORD, a Central Portal user token you
#      generate (https://central.sonatype.com/account, "Generate User Token").
#   2. Signing: sets GPG_PRIVATE_KEY and GPG_PASSPHRASE, either an existing key exported from
#      your GPG keyring by its id, or a new one generated here (RSA 4096, in a private GPG home
#      for the run) and registered with the public keyservers Central checks. Its public half is
#      written to central-signing-key.asc, to commit.
#   3. Access: makes the repositories that may read the secrets those listed in
#      central-publishing-repositories.txt. (Steps 1 and 2 already give a secret they set that
#      list; this is for the others, and for when the list changes.)
#
# Run once to set up, and again after editing the list (answering no to 1 and 2). All steps
# share one temporary GitHub token (admin:org) made for the run. Run it in your own terminal.
#
# DRY_RUN=1 shows what would be done, sending nothing (a generated key is a throwaway, neither
# sent to the keyservers nor written here).
set -euo pipefail

ORG=officefloor
SECRETS=(SONATYPE_USERNAME SONATYPE_PASSWORD GPG_PRIVATE_KEY GPG_PASSPHRASE)

here="$(cd "$(dirname "$0")" && pwd)"
REPO_LIST="$here/central-publishing-repositories.txt"
KEY_COPY="$here/central-signing-key.asc"   # public: committed, for anyone checking signatures

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

Now a GITHUB token, separate from the Central token: it lets this script write the officefloor
organisation's secrets, and nothing else. A temporary one with the admin:org scope, for this
run only.

  1. Press Enter to open GitHub's "New personal access token (classic)" page.
     The note and the admin:org scope are filled in already.
  2. Expiration: choose "Custom" and pick tomorrow (or the shortest offered).
  3. Check that admin:org is the only scope ticked, then "Generate token" at the bottom.
  4. Copy the token (ghp_...) and paste it here.

You must be an owner of the $ORG organisation.
EOF
    read -rp "Press Enter to open the browser (or Ctrl+C to stop)... "
    open_browser "https://github.com/settings/tokens/new?scopes=admin:org&description=OfficeFloor%20Central%20setup%20(temporary)"
    read -rsp "Paste the GitHub token (ghp_..., hidden): " GH_TOKEN; echo
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

setup_central() {
    cat <<EOF

== 1. Central ==
Sets SONATYPE_USERNAME and SONATYPE_PASSWORD: a Central Portal user token, which uploads the
libraries. Generate one at https://central.sonatype.com/account ("Generate User Token"), signed
in as the account that owns the net.officefloor namespace; it shows a username and a password.
EOF
    ask "Set the Central token?" || return 0
    local user pass
    read -rp "Central token username: " user
    read -rsp "Central token password (hidden): " pass; echo
    [ -n "$user" ] && [ -n "$pass" ] || die "the Central token needs both its username and its password"
    github_access
    set_secret SONATYPE_USERNAME < <(printf '%s' "$user")  # not a pipe: set_secret records what it set
    set_secret SONATYPE_PASSWORD < <(printf '%s' "$pass")  # not a pipe: set_secret records what it set
}

setup_signing() {
    cat <<EOF

== 2. Signing ==
Sets GPG_PRIVATE_KEY and GPG_PASSPHRASE: the key Central checks every artifact's signature
against, by its public half on a public keyserver. Either an existing key from your keyring
(OfficeFloor's release key, so everything under net.officefloor is signed alike), or a new one
made here and registered with the keyservers. Its public half is written to
$(basename "$KEY_COPY") here, to commit.
EOF
    ask "Set the signing key?" || return 0
    command -v gpg >/dev/null || die "needs gpg"
    local choice
    read -rp "Use an existing key from your keyring, or generate a new one? [e/g] " choice
    case "$choice" in
        [gG]*) generate_signing_key ;;
        [eE]*) existing_signing_key ;;
        *) die "answer e or g" ;;
    esac
}

existing_signing_key() {
    local id pass key
    read -rp "Signing key id (gpg --list-secret-keys --keyid-format long): " id
    [ -n "$id" ] || die "no key id given"
    if [ -n "${DRY_RUN:-}" ]; then
        key="(dry run: the armoured key of $id)"
    else
        key="$(gpg --armor --export-secret-keys "$id")" || die "gpg could not export $id"
        [ -n "$key" ] || die "no secret key $id in the keyring"
    fi
    read -rsp "The key's passphrase (hidden): " pass; echo
    github_access
    set_secret GPG_PRIVATE_KEY < <(printf '%s' "$key")  # not a pipe: set_secret records what it set
    set_secret GPG_PASSPHRASE < <(printf '%s' "$pass")  # not a pipe: set_secret records what it set
    if [ -n "${DRY_RUN:-}" ]; then
        echo "(dry run: $(basename "$KEY_COPY") left as it is)"
        return 0
    fi
    gpg --armor --export "$id" > "$KEY_COPY"
    if ask "Publish its public half to the keyservers too (do so if Central has never seen it)?"; then
        publish_key "$id" ""
    fi
    echo "Now commit $(basename "$KEY_COPY") to this repository."
}

generate_signing_key() {
    local name email pass confirm
    read -rp "Name on the key [OfficeFloor]: " name
    name="${name:-OfficeFloor}"
    read -rp "Email on the key (keys.openpgp.org emails it to confirm): " email
    [[ "$email" == *@*.* ]] || die "give the email address the key is for"
    read -rsp "Choose a passphrase for the new key (hidden): " pass; echo
    read -rsp "The passphrase again: " confirm; echo
    [ "$pass" = "$confirm" ] || die "the passphrases differ"
    [ ${#pass} -ge 8 ] || die "use at least 8 characters"

    # A private GPG home for this run only: nothing reaches your own keyring unless you keep it.
    WORK="$(umask 077; mktemp -d)"
    local home="$WORK/gnupg" fpr key
    (umask 077; mkdir -p "$home")
    gpg --homedir "$home" --batch --pinentry-mode loopback --passphrase-fd 0 \
        --quick-generate-key "$name <$email>" rsa4096 sign never <<<"$pass" 2>/dev/null \
        || die "gpg could not make the key"
    fpr="$(gpg --homedir "$home" --quiet --with-colons --list-secret-keys 2>/dev/null | awk -F: '/^fpr/ {print $10; exit}')"
    [ -n "$fpr" ] || die "the new key has no fingerprint"
    echo "Made the key: $name <$email>, RSA 4096, sign only, no expiry"
    echo "  fingerprint $fpr"
    key="$(gpg --homedir "$home" --batch --pinentry-mode loopback --passphrase-fd 0 \
        --armor --export-secret-keys "$fpr" <<<"$pass")" || die "gpg could not export the new key"

    github_access
    set_secret GPG_PRIVATE_KEY < <(printf '%s' "$key")  # not a pipe: set_secret records what it set
    set_secret GPG_PASSPHRASE < <(printf '%s' "$pass")  # not a pipe: set_secret records what it set

    if [ -n "${DRY_RUN:-}" ]; then
        echo "(dry run: the key is not sent to the keyservers, and $(basename "$KEY_COPY") is left as it is)"
    else
        gpg --homedir "$home" --armor --export "$fpr" > "$KEY_COPY"
        publish_key "$fpr" "$home"
    fi
    if ask "Keep a copy of the private key for a password manager (it is otherwise deleted)?"; then
        local keep="$HOME/officefloor-central-signing"
        (umask 077; mkdir -p "$keep")
        printf '%s\n' "$key" > "$keep/private-key.asc"
        gpg --homedir "$home" --armor --export "$fpr" > "$keep/public-key.asc"
        echo "Copied to $keep: save both files and the passphrase, then delete it."
        echo "(gpg --import $keep/private-key.asc puts it in a keyring, should it be needed.)"
    else
        echo "Deleting the private key: if it is ever needed again, a new key replaces it (README)."
    fi
    gpgconf --homedir "$home" --kill all 2>/dev/null || true
    [ -n "${DRY_RUN:-}" ] || echo "Now commit $(basename "$KEY_COPY") to this repository."
}

# The public keyservers Central looks a signing key up on.
KEYSERVERS=(hkps://keyserver.ubuntu.com hkps://keys.openpgp.org)

publish_key() {   # publish_key FINGERPRINT-OR-ID [GNUPGHOME]
    local id="$1" home=() server
    [ -n "${2:-}" ] && home=(--homedir "$2")
    for server in "${KEYSERVERS[@]}"; do
        if gpg "${home[@]}" --keyserver "$server" --send-keys "$id" 2>/dev/null; then
            echo "sent the public key to $server"
        else
            echo "WARNING: could not send the public key to $server: send it later with"
            echo "  gpg --keyserver $server --send-keys $id"
        fi
    done
    local fpr
    fpr="$(gpg "${home[@]}" --with-colons --fingerprint "$id" | awk -F: '/^fpr/ {print $10; exit}')"
    if curl --fail --silent --show-error -o /dev/null \
        "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x$fpr" 2>/dev/null; then
        echo "keyserver.ubuntu.com serves the key: Central can check signatures with it"
    else
        echo "keyserver.ubuntu.com does not serve the key yet (it can take a few minutes); check"
        echo "  https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x$fpr before the first release"
    fi
    cat <<EOF
keys.openpgp.org sends a confirmation email to the key's address: confirm it, so the key is
found by its address too. Central finds it by its id either way.
EOF
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

command -v gh >/dev/null || die "needs the GitHub CLI, gh"
echo "Sets up the $ORG organisation's secrets for publishing libraries to Maven Central,"
echo "for the repositories in $(basename "$REPO_LIST"): $REPO_CSV"
setup_central
setup_signing
update_access
cat <<EOF

A repository secret of the same name as one of these would override the organisation's, so the
repositories listed must not set their own.
EOF
