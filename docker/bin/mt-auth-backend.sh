#!/bin/sh
#
# mt-auth-backend.sh — lighttpd include_shell helper: prints the auth backend
# block consumed by conf/lighttpd-mirror.conf from environment variables.
#
# Default (MT_LDAP_AUTH unset or 0): the htpasswd file seeded by the
# entrypoint — the round-3 behaviour, byte-identical config semantics.
#
# MT_LDAP_AUTH=1 switches the SAME auth.require rules (Basic Auth on the
# admin UI, see lighttpd-mirror.conf) to LDAP lookups:
#
#   MT_LDAP_URL            ldap://dc.example.com:389 or ldaps://...:636 (required)
#   MT_LDAP_BASE_DN        search base DN, e.g. DC=corp,DC=example,DC=com (required)
#   MT_LDAP_BIND_DN        service account DN (empty -> anonymous bind)
#   MT_LDAP_BIND_PASSWORD  service account password (requires BIND_DN)
#   MT_LDAP_FILTER         search filter; default (uid=?); lighttpd replaces
#                          '?' with the LDAP-escaped login, e.g.
#                          (&(sAMAccountName=?)(memberOf=CN=admins,...))
#   MT_LDAP_STARTTLS       1 -> auth.backend.ldap.starttls = "enable" (for ldap:// URLs)
#   MT_LDAP_CA_CERT        CA certificate path (inside the container) for
#                          self-signed ldaps:// / STARTTLS; emitted as
#                          auth.backend.ldap.ca-file (libldap also honours
#                          the LDAPTLS_CACERT environment variable)
#   MT_LDAP_REQUIRE_GROUP  restrict the admin UI to members of a group: the
#                          value is a group DN, or several DNs joined with '|'.
#                          Emitted as "require" => "group=<dn>|group=<dn>" and
#                          checked by mod_authn_ldap natively: it searches
#                          (member=<user DN>) with the group DN as the search
#                          base. This works for groupOfNames/groupOfUniqueNames
#                          entries whose member attribute lives on the GROUP
#                          entry — such membership cannot be expressed as a
#                          user-search filter at all.
#   MT_LDAP_GROUP_MEMBER   membership attribute used with REQUIRE_GROUP;
#                          default "member" (compared against the user DN).
#                          Use "memberUid" for posixGroup entries (the
#                          LDAP-escaped login is substituted then).
#
# A self-signed ldaps:// or starttls setup may additionally need the CA
# certificate: set LDAPTLS_CACERT=/path/to/ca.pem in the environment
# (libldap reads it directly, no config change needed).
#
# Values are printed as lighttpd double-quoted strings (backslash and quote
# escaped here) — no env.* config references, so an unset optional variable
# can never break the config parse. Control characters in any value abort
# the config load (the entrypoint runs lighttpd -tt before supervisord), as
# do missing required variables and malformed URLs.

set -u

fail() {
    echo "mt-auth-backend.sh: $1" >&2
    exit 1
}

# lighttpd double-quoted string literal: escape backslash and double quote.
cfg_str() {
    printf '"%s"' "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
}

# auth.require rules are emitted here (not in lighttpd-mirror.conf) so the
# "require" value can switch between valid-user and group=... membership
# rules. The condition regex and realm are byte-identical to the conf's
# $HTTP["url"] block, which keeps dir-listing/fastcgi only.
emit_auth_require() {
    printf '%s\n' '$HTTP["url"] =~ "^/mt-proxy($|/)" {'
    printf '    auth.require = ( "" => ( "method" => "basic",\n'
    printf '                             "realm"  => "mikrotik-local-repo admin",\n'
    printf '                             "require" => %s ) )\n' "$(cfg_str "$1")"
    printf '%s\n' '}'
}

# Anything outside printable ASCII (incl. newline, which grep cannot see
# inside a single line) would corrupt the generated config — refuse it.
check_printable() {
    [ "$(LC_ALL=C printf '%s' "$1" | LC_ALL=C wc -l)" -eq 0 ] \
        || fail "$2 contains newline characters"
    if LC_ALL=C printf '%s' "$1" | LC_ALL=C grep -q '[^ -~]'; then
        fail "$2 contains characters outside printable ASCII"
    fi
    return 0
}

if [ "${MT_LDAP_AUTH:-0}" != "1" ]; then
    cat <<'EOF'
auth.backend                    = "htpasswd"
auth.backend.htpasswd.userfile  = "/data/config/.htpasswd"
EOF
    emit_auth_require "valid-user"
    exit 0
fi

[ -n "${MT_LDAP_URL:-}" ]     || fail "MT_LDAP_AUTH=1 but MT_LDAP_URL is not set"
[ -n "${MT_LDAP_BASE_DN:-}" ] || fail "MT_LDAP_AUTH=1 but MT_LDAP_BASE_DN is not set"

case "${MT_LDAP_URL}" in
    ldap://*|ldaps://*) ;;
    *) fail "MT_LDAP_URL must start with ldap:// or ldaps:// (got: ${MT_LDAP_URL})" ;;
esac

if [ -n "${MT_LDAP_BIND_PASSWORD:-}" ] && [ -z "${MT_LDAP_BIND_DN:-}" ]; then
    fail "MT_LDAP_BIND_PASSWORD is set but MT_LDAP_BIND_DN is empty (anonymous bind cannot carry a password)"
fi

check_printable "${MT_LDAP_URL}"         "MT_LDAP_URL"
check_printable "${MT_LDAP_BASE_DN}"     "MT_LDAP_BASE_DN"
check_printable "${MT_LDAP_BIND_DN:-}"   "MT_LDAP_BIND_DN"
check_printable "${MT_LDAP_BIND_PASSWORD:-}" "MT_LDAP_BIND_PASSWORD"
check_printable "${MT_LDAP_FILTER:-}"    "MT_LDAP_FILTER"
check_printable "${MT_LDAP_CA_CERT:-}"   "MT_LDAP_CA_CERT"

cat <<'EOF'
# --- LDAP admin auth (MT_LDAP_AUTH=1) --------------------------------------
server.modules += ( "mod_authn_ldap" )
auth.backend = "ldap"
EOF

filter='(uid=?)'
[ -n "${MT_LDAP_FILTER:-}" ] && filter="${MT_LDAP_FILTER}"
case "$filter" in
    *"?"*) ;;
    *) fail "MT_LDAP_FILTER must contain '?' — lighttpd replaces it with the LDAP-escaped login; examples: (uid=?) or (&(sAMAccountName=?)(memberOf=CN=admins,DC=corp,DC=example,DC=com))" ;;
esac

# lighttpd 1.4.79 (mod_authn_ldap): the server URI is auth.backend.ldap.hostname
# (ldap://host:port / ldaps://host:port); there is no .url key.
echo "auth.backend.ldap.hostname = $(cfg_str "${MT_LDAP_URL}")"
echo "auth.backend.ldap.base-dn = $(cfg_str "${MT_LDAP_BASE_DN}")"

if [ -n "${MT_LDAP_BIND_DN:-}" ]; then
    echo "auth.backend.ldap.bind-dn = $(cfg_str "${MT_LDAP_BIND_DN}")"
    echo "auth.backend.ldap.bind-pw = $(cfg_str "${MT_LDAP_BIND_PASSWORD:-}")"
fi

echo "auth.backend.ldap.filter = $(cfg_str "$filter")"
echo 'auth.backend.ldap.allow-empty-pw = "disable"'

if [ "${MT_LDAP_STARTTLS:-0}" = "1" ]; then
    echo 'auth.backend.ldap.starttls = "enable"'
fi

if [ -n "${MT_LDAP_CA_CERT:-}" ]; then
    echo "auth.backend.ldap.ca-file = $(cfg_str "${MT_LDAP_CA_CERT}")"
fi

# --- auth.require rules: valid-user, or native group membership (0005) ------
# mod_authn_ldap checks require group= itself: filter (groupmember=<value>)
# with each group DN as the search base. "member" compares the user DN (the
# DN found by the user search above); anything else is treated as memberUid
# and receives the escaped login instead (mod_authn_ldap.c).
if [ -n "${MT_LDAP_GROUP_MEMBER:-}" ] && [ -z "${MT_LDAP_REQUIRE_GROUP:-}" ]; then
    fail "MT_LDAP_GROUP_MEMBER is set but MT_LDAP_REQUIRE_GROUP is empty (the membership attribute has no effect without group requirements)"
fi

require_val=""
if [ -n "${MT_LDAP_REQUIRE_GROUP:-}" ]; then
    check_printable "${MT_LDAP_REQUIRE_GROUP}" "MT_LDAP_REQUIRE_GROUP"
    check_printable "${MT_LDAP_GROUP_MEMBER:-}" "MT_LDAP_GROUP_MEMBER"
    rest="${MT_LDAP_REQUIRE_GROUP}"
    while [ -n "$rest" ]; do
        case "$rest" in
            *"|"*) item="${rest%%|*}"; rest="${rest#*|}";;
            *)     item="$rest"; rest="";;
        esac
        [ -n "$item" ] || fail "MT_LDAP_REQUIRE_GROUP contains an empty group DN (check the '|' separators)"
        if [ -n "$require_val" ]; then
            require_val="${require_val}|group=${item}"
        else
            require_val="group=${item}"
        fi
    done
    echo "auth.backend.ldap.groupmember = $(cfg_str "${MT_LDAP_GROUP_MEMBER:-member}")"
fi
[ -n "$require_val" ] || require_val="valid-user"

emit_auth_require "$require_val"
