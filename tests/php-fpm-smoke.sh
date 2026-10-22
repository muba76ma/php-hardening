#!/usr/bin/env bash
# tests/php-fpm-smoke.sh — validate fpm/www.conf syntax
#
# Wraps the pool file in a [global] section so php-fpm -t can resolve
# pid/error_log. On Termux/Android the shm scoreboard may be blocked by
# SELinux -> "Cannot create lock - Permission denied (13)". In that case
# this test SKIPs (exit 0) rather than fails: the config is still valid,
# it's the platform that can't run fpm. CI on ubuntu-latest exercises it.

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
POOL="$REPO_ROOT/fpm/www.conf"

[ -r "$POOL" ] || { echo "missing: $POOL" >&2; exit 2; }
command -v php-fpm >/dev/null || { echo "SKIP: php-fpm not installed" >&2; exit 0; }

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

cat > "$TMP" <<WRAP_END
[global]
pid = ${TMPDIR:-/tmp}/php-fpm-smoke.pid
error_log = ${TMPDIR:-/tmp}/php-fpm-smoke.log
daemonize = no

include = $POOL
WRAP_END

OUT=$(php-fpm -y "$TMP" -t 2>&1 || true)

if printf '%s\n' "$OUT" | grep -q 'test is successful'; then
    echo "$OUT" | tail -1
    echo "php-fpm-smoke: PASS"
    exit 0
fi

if printf '%s\n' "$OUT" | grep -q 'Cannot create lock'; then
    echo "php-fpm-smoke: SKIP (platform blocks fpm shm; config content not exercised)"
    echo "  -> validated in CI on ubuntu-latest"
    exit 0
fi

printf '%s\n' "$OUT" >&2
echo "php-fpm-smoke: FAIL" >&2
exit 1
