# Helpers shared by the scripts. Sourced, after .config.sh.

set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }

# Runs openssl with the key's password: from SIGNING_PASSWORD when set (scripted use), else
# openssl asks for it on the terminal.
with_password() {
    if [ -n "${SIGNING_PASSWORD:-}" ]; then
        "$@" -passin env:SIGNING_PASSWORD
    else
        "$@"
    fi
}

# Asks for the key's password, hidden, unless SIGNING_PASSWORD is already set, and checks it
# opens the key. Leaves it in SIGNING_PASSWORD.
read_password() {
    if [ -z "${SIGNING_PASSWORD:-}" ]; then
        read -rsp "Password for $KEY: " SIGNING_PASSWORD; echo
    fi
    export SIGNING_PASSWORD
    openssl pkey -in "$KEY" -passin env:SIGNING_PASSWORD -noout 2>/dev/null \
        || die "that password does not open $KEY"
}

require_files() {
    [ -f "$KEY" ] || die "no $KEY: restore it from the password manager (or set SIGNING_DIR)"
    [ -f "$CERT" ] || die "no $CERT: restore it from the password manager (or set SIGNING_DIR)"
}

TOKEN_URL="https://github.com/settings/tokens/new?scopes=admin:org&description=OfficeFloorMaintenance%20(temporary)"
TOKENS_URL="https://github.com/settings/tokens"

open_browser() {
    if command -v xdg-open >/dev/null; then
        xdg-open "$1" >/dev/null 2>&1 &
    elif command -v open >/dev/null; then
        open "$1"
    else
        echo "Open: $1"
    fi
}

# Organisation secrets need the admin:org scope. The only way these scripts get it is a
# temporary token made for this run: gh's own login is never used for them, nor changed, and a
# GH_TOKEN already in the environment is ignored. The token is held in this process only.
# DRY_RUN=1 skips this, as nothing is sent.
org_access() {
    [ -n "${DRY_RUN:-}" ] && return
    unset GH_TOKEN GITHUB_TOKEN
    cat <<EOF
This needs a temporary GitHub token with the admin:org scope, used for this run only.

  1. Press Enter to open GitHub's "New personal access token (classic)" page.
     The note and the admin:org scope are filled in already.
  2. Expiration: choose "Custom" and pick tomorrow (or the shortest offered).
  3. Check that admin:org is the only scope ticked, then "Generate token" at the bottom.
  4. Copy the token (ghp_...) and paste it here.

You must be an owner of the $ORG organisation.
EOF
    read -rp "Press Enter to open the browser (or Ctrl+C to stop)... "
    open_browser "$TOKEN_URL"
    echo "(if no browser opened: $TOKEN_URL)"
    read -rsp "Paste the token: " GH_TOKEN; echo
    [ -n "$GH_TOKEN" ] || die "no token given"
    export GH_TOKEN

    scopes="$(gh api -i user 2>/dev/null | tr -d '\r' | sed -n 's/^[Xx]-[Oo][Aa]uth-[Ss]copes: //p')" \
        || die "GitHub did not accept that token"
    [[ ", $scopes," == *", admin:org,"* ]] || die "that token lacks admin:org (it has: ${scopes:-none})"
    trap 'echo; echo "Done with the token: delete it now at $TOKENS_URL (it also expires by itself)."' EXIT
}

# Runs a command, or with DRY_RUN=1 only prints it
run() {
    if [ -n "${DRY_RUN:-}" ]; then
        echo "would run: $*"
    else
        "$@"
    fi
}

repo_list() { local IFS=,; echo "${REPOS[*]}"; }
