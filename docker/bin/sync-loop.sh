#!/bin/bash
#
# sync-loop.sh — replaces the host cron entry inside the container.
# First run shortly after start (the web layer must be up for warm-up),
# then every SYNC_INTERVAL_HOURS.

set -u

INTERVAL_HOURS="${SYNC_INTERVAL_HOURS:-3}"
START_DELAY="${SYNC_START_DELAY:-90}"

echo "[sync-loop] first sync in ${START_DELAY}s, interval ${INTERVAL_HOURS}h"
sleep "${START_DELAY}"

while :; do
    started=$(date +%s)
    /usr/local/bin/sync_mikrotik_repo.sh 2>&1 | sed 's/^/[sync] /'
    rc=${PIPESTATUS[0]}
    dur=$(( $(date +%s) - started ))
    next=$(( INTERVAL_HOURS * 3600 - dur ))
    [ "${next}" -lt 60 ] && next=60
    echo "[sync-loop] finished rc=${rc} in ${dur}s, next run in ${next}s"
    sleep "${next}"
done
