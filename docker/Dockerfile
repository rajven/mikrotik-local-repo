# mikrotik-local-repo — all-in-one container
#
# Build context = repository root:
#   docker build -f docker/Dockerfile -t mikrotik-local-repo:docker .
#
# What is inside: nginx (device endpoints + admin UI), PHP-FPM, sync scripts,
# syslog-forward-to-stdout and the periodic sync loop. All state and config
# live under /data (mount a volume there).

FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      wget \
      unzip \
      nginx \
      php-fpm \
      php-curl \
      php-sqlite3 \
      supervisor \
      busybox-static \
      openssl \
      tzdata \
 && rm -rf /var/lib/apt/lists/*

# --- application sources (copy the whole repo layout we need) ---
COPY scripts/           /opt/app/scripts/
COPY html/              /opt/app/html/
COPY addons/mikrotik/   /opt/app/mikrotik/
# Only code goes into the image — never .env / compose.yaml (secrets).
COPY docker/bin/        /opt/docker/bin/
COPY docker/conf/       /opt/docker/conf/

# web root code + CLI scripts
RUN set -eux; \
    cp -a /opt/app/html/. /var/www/html/; \
    rm -f /var/www/html/index.nginx-debian.html /var/www/html/routeros/.gitkeep; \
    cp /opt/app/scripts/*.sh /usr/local/bin/; \
    chmod +x /usr/local/bin/sync_mikrotik_repo.sh /usr/local/bin/download_ros.sh; \
    rm -f /usr/local/bin/config.sh

# One-line downstream patch: SQLite path from env, so mt_proxy.db (+ WAL
# sidecars) live under /data/state instead of the ephemeral code layer.
RUN chmod +x /opt/docker/bin/entrypoint.sh /opt/docker/bin/sync-loop.sh \
 && perl -0pi -e 's{define\(\x27DB_PATH\x27,[^\n]*\);}{define("DB_PATH", getenv("MT_PROXY_DB_PATH") ?: __DIR__ . "/mt_proxy.db");}' \
    /var/www/html/mt-proxy/db.php \
 && grep -q 'MT_PROXY_DB_PATH' /var/www/html/mt-proxy/db.php

# Downstream patch #2: the warm-up is a container self-request. SITE_URL is the
# device-facing address (a front reverse proxy may be in front of it, and it may
# even be unreachable from inside the container), so the internal call always
# hits localhost. The sync script passes -O /dev/null explicitly: without it
# wget would save the HTML report as "ros-warmup.php?token=..." into the mirror.
RUN sed -i 's|^WARMUP_URL="${SITE_URL}|WARMUP_URL="http://localhost|' /usr/local/bin/sync_mikrotik_repo.sh \
 && grep -Fq -- 'WARMUP_URL="http://localhost/routeros/ros-warmup.php?token=${WARMUP_TOKEN}"' /usr/local/bin/sync_mikrotik_repo.sh

# PHP-FPM: our pool only, longer exec timeout for the warm-up endpoint
RUN set -eux; \
    etcdir="$(dirname "$(ls -d /etc/php/*/fpm | head -1)")"; \
    ver="$(basename "$etcdir")"; \
    rm -f "$etcdir"/fpm/pool.d/www.conf; \
    install -m 644 /opt/docker/conf/php-fpm-container.conf "$etcdir"/fpm/pool.d/container.conf; \
    sed -i 's/^[; ]*max_execution_time = .*/max_execution_time = 600/' "$etcdir"/fpm/php.ini; \
    mkdir -p /run/php; \
    test -x "/usr/sbin/php-fpm${ver}"; \
    sed "s|@PHP_FPM_BIN@|/usr/sbin/php-fpm${ver}|g" /opt/docker/conf/supervisord.conf.in > /etc/supervisor/supervisord.conf

EXPOSE 80

HEALTHCHECK --interval=60s --timeout=10s --start-period=120s \
    CMD wget -q -T 5 -O /dev/null http://127.0.0.1/healthz || exit 1

ENTRYPOINT ["/opt/docker/bin/entrypoint.sh"]
CMD ["supervisord"]
