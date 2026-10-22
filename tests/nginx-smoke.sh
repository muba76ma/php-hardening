#!/usr/bin/env bash
# tests/nginx-smoke.sh — validate nginx/php-hardening.conf syntax
#
# Termux note: this nginx build resolves relative `include` paths against
# the -c file's directory, not -p. Wrapper is placed next to fastcgi_params.
# Debian/Docker run nginx -t against /etc/nginx/, where the relative
# `include fastcgi_params;` resolves normally.

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
CONF="$REPO_ROOT/nginx/php-hardening.conf"

[ -r "$CONF" ] || { echo "missing: $CONF" >&2; exit 2; }
command -v nginx >/dev/null || { echo "SKIP: nginx not installed" >&2; exit 0; }

if [ -n "${PREFIX:-}" ] && [ -f "$PREFIX/etc/nginx/fastcgi_params" ]; then
    WRAP_DIR="$PREFIX/etc/nginx"
elif [ -f /etc/nginx/fastcgi_params ]; then
    WRAP_DIR=/etc/nginx
else
    echo "ERROR: cannot find directory with fastcgi_params" >&2
    exit 2
fi

WRAP="$WRAP_DIR/.php-hardening-smoke.conf"
trap 'rm -f "$WRAP"' EXIT

cat > "$WRAP" <<WRAP_END
events { worker_connections 64; }
http { include $CONF; }
WRAP_END

nginx -t -c "$WRAP"
echo "nginx-smoke: PASS"
