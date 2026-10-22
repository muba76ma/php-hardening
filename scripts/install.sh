#!/usr/bin/env bash
# scripts/install.sh — deploy hardening configs to the running PHP
#
# Usage:
#   ./scripts/install.sh               Auto-detect platform, install 99-hardening.ini
#   ./scripts/install.sh -n            Dry-run — print plan, change nothing
#   ./scripts/install.sh -f            Overwrite existing 99-hardening.ini (creates .bak)
#   ./scripts/install.sh -r            Do NOT restart php-fpm after install
#   ./scripts/install.sh -t TARGET     Force target: termux|debian|rhel|docker
#   ./scripts/install.sh -h            This help
#
# Exit codes: 0 = installed, 1 = skipped (already exists), 2 = error

set -eu

DRY_RUN=0
FORCE=0
RESTART=1
TARGET="auto"

usage() { sed -n '4,15p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while getopts "nfrht:" opt; do
    case "$opt" in
        n) DRY_RUN=1 ;;
        f) FORCE=1 ;;
        r) RESTART=0 ;;
        t) TARGET="$OPTARG" ;;
        h) usage 0 ;;
        *) usage 2 ;;
    esac
done

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
SRC="$REPO_ROOT/php.ini.d/99-hardening.ini"
DST_NAME="99-hardening.ini"

run() { if [ "$DRY_RUN" -eq 1 ]; then printf '  [dry-run] %s\n' "$*"; else "$@"; fi; }

[ -r "$SRC" ] || { echo "ERROR: source not found: $SRC" >&2; exit 2; }

detect_target() {
    if [ -n "${PREFIX:-}" ] && [ -d "$PREFIX/etc" ] && command -v termux-info >/dev/null 2>&1; then
        echo termux
    elif [ -f /etc/alpine-release ] || [ -d /usr/local/etc/php/conf.d ]; then
        echo docker
    elif [ -f /etc/debian_version ]; then
        echo debian
    elif [ -f /etc/redhat-release ] || [ -f /etc/fedora-release ]; then
        echo rhel
    else
        echo unknown
    fi
}
[ "$TARGET" = auto ] && TARGET=$(detect_target)

# php --ini on PHP 8.5 wraps the path in double quotes; strip them.
php_scan_dir() {
    php --ini 2>/dev/null \
        | awk -F': ' '/^Scan for additional .ini files in:/ {sub(/^Scan for additional .ini files in: */, ""); gsub(/"/, ""); print; exit}'
}

case "$TARGET" in
    termux)
        SCAN_DIR=$(php_scan_dir)
        case "$SCAN_DIR" in
            ""|"(none)") SCAN_DIR="${PREFIX:-/data/data/com.termux/files/usr}/etc/php/conf.d" ;;
        esac
        DST_DIR="$SCAN_DIR"
        ;;
    debian)
        DST_DIR=$(ls -d /etc/php/8.*/fpm/conf.d 2>/dev/null | head -1 || true)
        [ -z "$DST_DIR" ] && DST_DIR=/etc/php/8.4/fpm/conf.d
        ;;
    rhel)
        DST_DIR=/etc/php.d
        ;;
    docker)
        DST_DIR=/usr/local/etc/php/conf.d
        ;;
    *)
        echo "ERROR: cannot auto-detect platform; use -t {termux|debian|rhel|docker}" >&2
        exit 2
        ;;
esac

DST="$DST_DIR/$DST_NAME"

echo "target:  $TARGET"
echo "source:  $SRC"
echo "dest:    $DST"

if [ -e "$DST" ] && [ "$FORCE" -eq 0 ]; then
    echo "SKIP: destination already exists (use -f to overwrite)"
    exit 1
fi

if [ -e "$DST" ] && [ "$FORCE" -eq 1 ]; then
    BAK="$DST.bak.$(date +%Y%m%d%H%M%S)"
    echo "backup:  $DST -> $BAK"
    run cp -p "$DST" "$BAK"
fi

if [ "$TARGET" = termux ] && [ -n "${PREFIX:-}" ]; then
    run mkdir -p "$PREFIX/var/log"
fi

run mkdir -p "$DST_DIR"
run install -m 0644 "$SRC" "$DST"

if [ "$RESTART" -eq 1 ]; then
    if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet php8.4-fpm 2>/dev/null; then
        run systemctl restart php8.4-fpm && echo "restarted: php8.4-fpm (systemd)"
    elif command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet php-fpm 2>/dev/null; then
        run systemctl restart php-fpm && echo "restarted: php-fpm (systemd)"
    elif pgrep -x php-fpm >/dev/null 2>&1; then
        echo "restart: pkill php-fpm && php-fpm -D"
        run pkill -9 php-fpm || true
        run php-fpm -D
        echo "restarted: php-fpm (daemonized)"
    else
        echo "restart: no php-fpm process running — nothing to restart"
    fi
fi

echo
echo "verify:"
if [ "$DRY_RUN" -eq 0 ]; then
    php --ini 2>/dev/null | grep -E 'Loaded Configuration|Scan for additional|Additional .ini' || true
    echo
    echo "audit (live):"
    "$SCRIPT_DIR/audit.sh" || echo "(audit FAILs expected only if app process hasn't reloaded yet)"
else
    echo "  [dry-run] would run: php --ini && ./scripts/audit.sh"
fi
