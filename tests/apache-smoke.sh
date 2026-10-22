#!/usr/bin/env bash
# tests/apache-smoke.sh — validate apache/php-hardening.conf syntax
#
# Requires apache2/httpd + mod_headers + mod_proxy_fcgi.
# On Termux apache2 may be absent -> SKIP.

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
CONF="$REPO_ROOT/apache/php-hardening.conf"

[ -r "$CONF" ] || { echo "missing: $CONF" >&2; exit 2; }

if command -v apache2ctl >/dev/null 2>&1; then
    APACHE_CTL=apache2ctl
    APACHE_CONF=/etc/apache2/apache2.conf
elif command -v httpd >/dev/null 2>&1; then
    APACHE_CTL=httpd
    APACHE_CONF=/etc/httpd/conf/httpd.conf
elif command -v apachectl >/dev/null 2>&1; then
    APACHE_CTL=apachectl
    APACHE_CONF="${PREFIX:-}/etc/apache2/httpd.conf"
else
    echo "SKIP: apache not installed" >&2
    exit 0
fi

# Ensure required modules are loaded (Debian only; RHEL ships them statically)
if command -v a2enmod >/dev/null 2>&1; then
    for mod in headers proxy proxy_fcgi; do
        if [ ! -L "/etc/apache2/mods-enabled/${mod}.load" ]; then
            echo "SKIP: mod_${mod} not enabled (run: a2enmod ${mod})" >&2
            exit 0
        fi
    done
fi

# Create a temp config that loads the snippet and does configtest
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

# Debian: drop into conf-available via a symlink trick
if [ "$APACHE_CTL" = apache2ctl ]; then
    LN="/etc/apache2/conf-enabled/99-php-hardening-smoke.conf"
    if [ -w /etc/apache2/conf-enabled ]; then
        ln -sf "$CONF" "$LN"
        trap "rm -f '$TMP' '$LN'" EXIT
        apache2ctl configtest 2>&1 | tail -2
        echo "apache-smoke: PASS"
        exit 0
    fi
fi

# Fallback: verify by grep alone (no configtest possible)
echo "SKIP: cannot install conf for configtest (need root)"
echo "  verifying structure only:"
grep -qE '^ServerTokens +Prod' "$CONF" || { echo "missing: ServerTokens Prod" >&2; exit 1; }
grep -qE '^ServerSignature +Off' "$CONF" || { echo "missing: ServerSignature Off" >&2; exit 1; }
grep -qE '^TraceEnable +Off' "$CONF" || { echo "missing: TraceEnable Off" >&2; exit 1; }
grep -qE 'Header always set X-Content-Type-Options' "$CONF" || { echo "missing: X-Content-Type-Options" >&2; exit 1; }
echo "apache-smoke: PASS (structure only)"
