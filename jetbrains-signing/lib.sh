# Helpers shared by the scripts. Sourced, after config.sh.

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

# Organisation secrets need more access than gh's default login has (admin:org). Either:
#   - GH_TOKEN is already set: a short-lived token made for this run, used as it is; or
#   - gh's login already has admin:org; or
#   - ask: add admin:org to gh's login now and remove it again when the script ends, or
#     paste a short-lived token for this run only.
# DRY_RUN=1 skips the check, as nothing is sent.
org_access() {
    [ -n "${DRY_RUN:-}" ] && return
    if [ -n "${GH_TOKEN:-}" ]; then
        echo "Using the token in GH_TOKEN for this run."
        return
    fi
    if gh auth status -h github.com 2>&1 | grep -q "'admin:org'"; then
        return
    fi
    cat <<EOF
Organisation secrets need the admin:org scope, which gh's login does not have.
  1) add it to gh's login for this run, and remove it again at the end (opens the browser twice)
  2) paste a short-lived token for this run only (gh's login is left alone): a classic token
     with the admin:org scope and a 1-day expiry, from https://github.com/settings/tokens/new
  q) stop
EOF
    read -rp "Choice [1/2/q]: " choice
    case "$choice" in
        1)
            gh auth refresh -h github.com -s admin:org
            trap 'echo "Removing admin:org from gh again."; gh auth refresh -h github.com -r admin:org' EXIT
            ;;
        2)
            read -rsp "Token: " GH_TOKEN; echo
            [ -n "$GH_TOKEN" ] || die "no token given"
            export GH_TOKEN
            echo "Delete it at https://github.com/settings/tokens when done (it expires anyway)."
            ;;
        *) die "stopped" ;;
    esac
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
