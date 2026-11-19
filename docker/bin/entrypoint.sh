#!/bin/bash
#
# entrypoint.sh — materialize code/state layout, seed first-run config from env,
# then hand over to supervisord.
#
# Everything persistent lives under /data:
#   /data/routeros   — package mirror, version caches, device *.rsc scripts
#   /data/state      — mt_proxy.db (+ WAL sidecars)
#   /data/config     — config.sh, mt_proxy_config.php, fullchain.pem, .htpasswd
#
# *config.sh* and *mt_proxy_config.php* are generated from environment
# variables on FIRST start only; afterwards they are user-editable files.

set -euo pipefail

APP=/opt/app
DATA=/data
umask 022

: "${SITE_URL:=http://localhost}"
: "${TZ:=UTC}"

if [ "${1:-supervisord}" != "supervisord" ]; then
    exec "$@"
fi

# ---------------------------------------------------------------- token check
# WARMUP_TOKEN is substituted into config.sh and mt_proxy_config.php with sed
# (delimiter "|") on first start. A token containing sed metacharacters would
# silently corrupt the generated configs, so refuse to start with a clear
# message instead. Allowed: letters, digits, '_', '-' (as documented in
# .env.example / README: "pwgen 20 1" output fits).
if [ -n "${WARMUP_TOKEN:-}" ] && [ "${WARMUP_TOKEN}" != "CHANGE_ME" ] \
   && ! printf '%s' "${WARMUP_TOKEN}" | grep -qE '^[A-Za-z0-9_-]+$'; then
    echo "ERROR: WARMUP_TOKEN contains unsupported characters: '${WARMUP_TOKEN}'" >&2
    echo "       Allowed: letters, digits, '_', '-'. The token is substituted" >&2
    echo "       into the generated config files via sed; '|' and '&' would" >&2
    echo "       corrupt them. Refusing to start." >&2
    exit 1
fi

if [ "${WARMUP_TOKEN:-}" = "change-me-to-a-random-secret" ]; then
    echo "WARNING: WARMUP_TOKEN still has the .env.example placeholder value." >&2
    echo "         It passes the charset check but is a predictable token:" >&2
    echo "         change it to a random secret (e.g. \"pwgen 20 1\")." >&2
elif [ -z "${WARMUP_TOKEN:-}" ] || [ "${WARMUP_TOKEN}" = "CHANGE_ME" ]; then
    echo "WARNING: WARMUP_TOKEN is not set — ros-warmup.php and sync use 'CHANGE_ME'." >&2
    echo "         Set WARMUP_TOKEN in the environment (or edit /data/config/mt_proxy_config.php)." >&2
fi
# ---------------------------------------------------------------- time zone
if [ -e "/usr/share/zoneinfo/${TZ}" ]; then
    ln -sf "/usr/share/zoneinfo/${TZ}" /etc/localtime
fi

# PHP >= 7.3 ignores TZ//etc/localtime for date.timezone; propagate explicitly
# (the installed pool conf always carries this line).
for fpm in /etc/php/*/fpm/pool.d/container.conf; do
    [ -e "$fpm" ] || continue
    sed -i "s|^[;[:space:]]*php_admin_value\[date\.timezone\].*|php_admin_value[date.timezone] = ${TZ}|" "$fpm"
done

# ---------------------------------------------------------------- data dirs
mkdir -p "${DATA}/routeros" "${DATA}/state" "${DATA}/config"
chown www-data:www-data "${DATA}/routeros" "${DATA}/state"
chmod 755 "${DATA}"

# ---------------------------------------------------------------- config.sh
# SITE_URL is deliberately removed: inside the container the warm-up call is
# always a local self-request (patched in the Dockerfile); SITE_URL is the
# device-facing address and is baked into the *.rsc scripts instead.
CONFIG_SH="${DATA}/config/config.sh"
if [ ! -f "${CONFIG_SH}" ]; then
    sed \
        -e "s|^TARGET_DIR=.*|TARGET_DIR=\"${DATA}/routeros\"|" \
        -e "s|^WARMUP_TOKEN=.*|WARMUP_TOKEN=\"${WARMUP_TOKEN:-CHANGE_ME}\"|" \
        -e '/^# Website address for update policies$/d' \
        -e '/^SITE_URL=.*$/d' \
        "${APP}/scripts/config.sh" > "${CONFIG_SH}"
fi
ln -sfn "${CONFIG_SH}" /usr/local/bin/config.sh

# ------------------------------------------------------ mt_proxy_config.php
MT_CFG="${DATA}/config/mt_proxy_config.php"
if [ ! -f "${MT_CFG}" ]; then
    sed "s|'WARMUP_TOKEN' => 'CHANGE_ME'|'WARMUP_TOKEN' => '${WARMUP_TOKEN:-CHANGE_ME}'|" \
        "${APP}/html/mt-proxy/mt_proxy_config.php" > "${MT_CFG}"
fi
ln -sfn "${MT_CFG}" /var/www/html/mt-proxy/mt_proxy_config.php

# ---------------------------------------------------------------- fullchain
FULLCHAIN="${DATA}/config/fullchain.pem"
[ -f "${FULLCHAIN}" ] || cp "${APP}/html/fullchain.pem" "${FULLCHAIN}"
ln -sfn "${FULLCHAIN}" /var/www/html/fullchain.pem

# ---------------------------------------------------------------- web seeds
# (Re)install device scripts into the mirror; -C keeps them byte-identical
# with the image when unchanged, so SERVER_NAME placeholders are available
# for re-substitution on EVERY start (SITE_URL change = just restart).
for f in "${APP}"/mikrotik/*.rsc; do
    install -C -m 644 -o www-data -g www-data "$f" "${DATA}/routeros/"
done

# Device-facing identity for the mirror copies:
#   <scheme>://SERVER_NAME  ->  SITE_URL as given (the scheme from the file
#                               is replaced too, so devices always end up on
#                               exactly the configured URL)
#   SERVER_NAME (bare)      ->  host[:port] from SITE_URL
#   SERVER_IP (dns.rsc)     ->  resolved IPv4/IPv6; left as placeholder when
#                               unresolvable (non-fatal, it is imported by
#                               hand anyway)
SITE_HOST="${SITE_URL#*://}"
SITE_HOST="${SITE_HOST%%/*}"
SITE_HOST="${SITE_HOST%%\?*}"
case "$SITE_HOST" in
    \[*\]:*) SITE_HOST="${SITE_HOST%:*}" ;;      # [::1]:8080 -> [::1]
    *:*)     SITE_HOST="${SITE_HOST%%:*}" ;;     # host:port -> host
esac

case "$SITE_HOST" in
    ''|localhost|127.*|\[::1\]|::1)
        echo "WARNING: SITE_URL=\"$SITE_URL\" is not reachable from routers;" >&2
        echo "         device scripts will embed this address as-is." >&2
        ;;
esac

SITE_IP=""
if [[ "$SITE_HOST" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
    SITE_IP="$SITE_HOST"
elif [[ "$SITE_HOST" == \[*\] ]]; then
    SITE_IP="${SITE_HOST//[\[\]]/}"
elif [ -n "$SITE_HOST" ]; then
    # libc resolver (getent) — the container image has no ping/ICMP tooling.
    SITE_IP="$(getent ahostsv4 -- "$SITE_HOST" 2>/dev/null | awk 'NR==1{print $1}' || true)"
    if [ -z "$SITE_IP" ]; then
        SITE_IP="$(getent ahostsv6 -- "$SITE_HOST" 2>/dev/null | awk 'NR==1{print $1}' || true)"
    fi
    if [ -z "$SITE_IP" ]; then
        echo "WARNING: cannot resolve \"$SITE_HOST\"; SERVER_IP placeholder in dns.rsc will be left intact." >&2
    fi
fi

esc_url="$(printf '%s' "$SITE_URL"   | sed 's/[&|\\]/\\&/g')"
esc_host="$(printf '%s' "$SITE_HOST" | sed 's/[&|\\]/\\&/g')"

shopt -s nullglob
for f in "${DATA}"/routeros/*.rsc; do
    sed -i \
        -e "s|https\{0,1\}://SERVER_NAME|${esc_url}|g" \
        -e "s|SERVER_NAME|${esc_host}|g" \
        "$f"
    if [ -n "$SITE_IP" ]; then
        sed -i "s|SERVER_IP|${SITE_IP}|g" "$f"
    fi
done

for f in "${APP}"/html/routeros/*.cache; do
    [ -e "${DATA}/routeros/$(basename "$f")" ] || \
        install -C -m 664 -o www-data -g www-data "$f" "${DATA}/routeros/"
done

# Generate a .md5 next to EVERY *.rsc on the mirror (BackupAndUpdate.md5 is
# the one the on-device updater checks; the rest are produced for free).
(
    cd "${DATA}/routeros" || exit 1
    for f in *.rsc; do
        md5sum "$f" | cut -d ' ' -f 1 > "${f%.rsc}.md5~"
        mv -- "${f%.rsc}.md5~" "${f%.rsc}.md5"
    done
    chown www-data:www-data . *.md5
)

# Sweep old wget warm-up artifacts (files named "ros-warmup.php?token=...")
# that sync created in the mirror dir before the Dockerfile patch.
rm -f "${DATA}"/routeros/ros-warmup.php*

# /var/www/html/routeros in the image is just a staging dir baked by `cp -a`;
# replace it with a symlink into the volume (ln cannot swap a non-empty dir).
rm -rf /var/www/html/routeros
ln -sfn "${DATA}/routeros" /var/www/html/routeros

# ---------------------------------------------------------------- admin auth
HTPASSWD="${DATA}/config/.htpasswd"
if [ ! -f "${HTPASSWD}" ]; then
    if [ -n "${ADMIN_PASSWORD_HASH:-}" ]; then
        printf '%s:%s\n' "${ADMIN_USER:-admin}" "${ADMIN_PASSWORD_HASH}" > "${HTPASSWD}"
    else
        if [ -n "${ADMIN_PASSWORD:-}" ]; then
            pw="${ADMIN_PASSWORD}"
        else
            pw="$(openssl rand -hex 12)"
            echo "ADMIN UI password for '${ADMIN_USER:-admin}' (generated once, stored in ${HTPASSWD}): ${pw}"
        fi
        printf '%s:%s\n' "${ADMIN_USER:-admin}" "$(openssl passwd -6 "${pw}")" > "${HTPASSWD}"
    fi
    chmod 640 "${HTPASSWD}"
    chown root:www-data "${HTPASSWD}"
fi
chown root:www-data "${DATA}/config"
chmod 750 "${DATA}/config"

if [ "${MT_LDAP_AUTH:-0}" = "1" ]; then
    echo "Admin UI auth backend: LDAP (${MT_LDAP_URL:-}); htpasswd at ${HTPASSWD} kept as fallback."
fi

# ------------------------------------------------------------------ ldap.conf
# System-wide libldap settings, read by mod_authn_ldap (no lighttpd-level
# directive exists for e.g. TLS_REQCERT) and by php-ldap. Managed on EVERY
# start:
#   /data/config/ldap.conf present -> installed as-is (manual full control,
#   survives restarts and image updates — it lives on the volume);
#   otherwise generated from env: TLS_REQCERT from MT_LDAP_TLS_REQCERT
#   (never|allow|try|demand|hard), TLS_CACERT from MT_LDAP_CA_CERT (the same
#   CA is also handed to lighttpd via auth.backend.ldap.ca-file).
LDAP_CONF=/etc/ldap/ldap.conf
LDAP_USER_CONF="${DATA}/config/ldap.conf"
case "${MT_LDAP_TLS_REQCERT:-}" in
    ''|never|allow|try|demand|hard) ;;
    *)
        echo "ERROR: MT_LDAP_TLS_REQCERT must be one of never|allow|try|demand|hard (got: '${MT_LDAP_TLS_REQCERT}')" >&2
        exit 1
        ;;
esac
if [[ "${MT_LDAP_CA_CERT:-}" == *$'\n'* ]]; then
    echo "ERROR: MT_LDAP_CA_CERT contains newline characters" >&2
    exit 1
fi
if [ -f "${LDAP_USER_CONF}" ]; then
    install -m 644 "${LDAP_USER_CONF}" "${LDAP_CONF}"
    echo "ldap.conf: installed user-managed ${LDAP_USER_CONF} as ${LDAP_CONF}."
else
    {
        echo '# Generated by the container entrypoint on every start.'
        echo "# To manage this file by hand (TLS_REQCERT, TLS_CACERT, BASE, URI...),"
        echo "# put it at ${LDAP_USER_CONF} — it survives restarts and image updates."
        echo '# All directives: man 5 ldap.conf.'
        echo ''
        echo '#TLS_REQCERT never'
        [ -n "${MT_LDAP_TLS_REQCERT:-}" ] && echo "TLS_REQCERT ${MT_LDAP_TLS_REQCERT}"
        [ -n "${MT_LDAP_CA_CERT:-}" ] && echo "TLS_CACERT ${MT_LDAP_CA_CERT}"
        true
    } > "${LDAP_CONF}"
    if [ "${MT_LDAP_TLS_REQCERT:-}" = "never" ]; then
        echo "WARNING: TLS_REQCERT never disables LDAP server certificate verification — anyone on the path to the directory can impersonate it." >&2
    fi
fi

# ------------------------------------------------------------------ ldap.conf
# System-wide libldap settings, read by mod_authn_ldap (no lighttpd-level
# directive exists for e.g. TLS_REQCERT) and by php-ldap. Managed on EVERY
# start:
#   /data/config/ldap.conf present -> installed as-is (manual full control,
#   survives restarts and image updates — it lives on the volume);
#   otherwise generated from env: TLS_REQCERT from MT_LDAP_TLS_REQCERT
#   (never|allow|try|demand|hard), TLS_CACERT from MT_LDAP_CA_CERT (the same
#   CA is also handed to lighttpd via auth.backend.ldap.ca-file).
LDAP_CONF=/etc/ldap/ldap.conf
LDAP_USER_CONF="${DATA}/config/ldap.conf"
# /etc/ldap comes from libldap-common, which libldap2 only Recommends — a
# --no-install-recommends image has neither the package nor the directory.
mkdir -p /etc/ldap
case "${MT_LDAP_TLS_REQCERT:-}" in
    ''|never|allow|try|demand|hard) ;;
    *)
        echo "ERROR: MT_LDAP_TLS_REQCERT must be one of never|allow|try|demand|hard (got: '${MT_LDAP_TLS_REQCERT}')" >&2
        exit 1
        ;;
esac
if [[ "${MT_LDAP_CA_CERT:-}" == *$'\n'* ]]; then
    echo "ERROR: MT_LDAP_CA_CERT contains newline characters" >&2
    exit 1
fi
if [ -f "${LDAP_USER_CONF}" ]; then
    install -m 644 "${LDAP_USER_CONF}" "${LDAP_CONF}"
    echo "ldap.conf: installed user-managed ${LDAP_USER_CONF} as ${LDAP_CONF}."
else
    {
        echo '# Generated by the container entrypoint on every start.'
        echo "# To manage this file by hand (TLS_REQCERT, TLS_CACERT, BASE, URI...),"
        echo "# put it at ${LDAP_USER_CONF} — it survives restarts and image updates."
        echo '# All directives: man 5 ldap.conf.'
        echo ''
        echo '#TLS_REQCERT never'
        [ -n "${MT_LDAP_TLS_REQCERT:-}" ] && echo "TLS_REQCERT ${MT_LDAP_TLS_REQCERT}"
        [ -n "${MT_LDAP_CA_CERT:-}" ] && echo "TLS_CACERT ${MT_LDAP_CA_CERT}"
        true
    } > "${LDAP_CONF}"
    if [ "${MT_LDAP_TLS_REQCERT:-}" = "never" ]; then
        echo "WARNING: TLS_REQCERT never disables LDAP server certificate verification — anyone on the path to the directory can impersonate it." >&2
    fi
fi

# ------------------------------------------------------------ lighttpd bits
install -m 644 /opt/docker/conf/lighttpd-mirror.conf /etc/lighttpd/lighttpd.conf

lighttpd -tt -f /etc/lighttpd/lighttpd.conf

exec /usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf
