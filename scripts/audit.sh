#!/usr/bin/env bash
# scripts/audit.sh — PHP hardening baseline audit
#
# Usage:
#   ./scripts/audit.sh                    Audit the running PHP (php -i)
#   ./scripts/audit.sh -i path/to/ini     Audit a specific ini file in isolation
#   ./scripts/audit.sh -p /path/to/php    Use a custom php binary
#   ./scripts/audit.sh -q                 Quiet mode (FAIL/WARN only)
#   ./scripts/audit.sh -h                 This help
#
# Exit codes: 0 = pass (warnings allowed), 1 = fail, 2 = setup error
#
# Note: -i audits `php -n -c FILE -i`, which loads ONLY that ini file.
#       Overlay configs (e.g. php.ini.d/99-hardening.ini on top of
#       php.ini-production) will show compiled defaults for any directive
#       they don't set — the primary mode (no -i) is what CI should use.

set -u

PHP_BIN="${PHP_BIN:-php}"
INI_FILE=""
QUIET=0
CHECKS=0
FAILS=0
WARNS=0

usage() {
    sed -n '4,15p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while getopts "i:p:qh" opt; do
    case "$opt" in
        i) INI_FILE="$OPTARG" ;;
        p) PHP_BIN="$OPTARG" ;;
        q) QUIET=1 ;;
        h) usage 0 ;;
        *) usage 2 ;;
    esac
done

if ! command -v "$PHP_BIN" >/dev/null 2>&1; then
    echo "ERROR: php binary not found: $PHP_BIN" >&2
    exit 2
fi

PHP_ARGS=("-d" "error_reporting=0")
if [ -n "$INI_FILE" ]; then
    if [ ! -r "$INI_FILE" ]; then
        echo "ERROR: cannot read ini file: $INI_FILE" >&2
        exit 2
    fi
    PHP_ARGS+=("-n" "-c" "$INI_FILE")
fi

PHPINFO=$("$PHP_BIN" "${PHP_ARGS[@]}" -i 2>/dev/null)
if [ -z "$PHPINFO" ]; then
    echo "ERROR: '$PHP_BIN -i' produced no output (broken ini?)" >&2
    exit 2
fi

# --- helpers ---------------------------------------------------------------

directive_exists() {
    printf '%s\n' "$PHPINFO" | awk -F'=> ' -v k="$1" '
        { key = $1; gsub(/^[ \t]+|[ \t]+$/, "", key)
          if (key == k) { found = 1; exit } }
        END { exit (found ? 0 : 1) }
    '
}

get_directive() {
    printf '%s\n' "$PHPINFO" | awk -F'=> ' -v k="$1" '
        { key = $1; gsub(/^[ \t]+|[ \t]+$/, "", key)
          if (key == k) {
              v = $2; gsub(/^[ \t]+|[ \t]+$/, "", v); gsub(/\r/, "", v)
              print v; exit
          } }
    '
}

check() {
    local name="$1" value="$2" expected="$3" level="$4"
    CHECKS=$((CHECKS + 1))
    if [ -z "$value" ] && ! directive_exists "$name"; then
        [ "$QUIET" -eq 0 ] && printf '[SKIP] %s (not present on this PHP build)\n' "$name"
        return 0
    fi
    if [ "$value" = "$expected" ]; then
        [ "$QUIET" -eq 0 ] && printf '[PASS] %s = %s\n' "$name" "$value"
        return 0
    fi
    if [ "$level" = "FAIL" ]; then
        printf '[FAIL] %s = %s (want %s)\n' "$name" "${value:-(empty)}" "$expected"
        FAILS=$((FAILS + 1))
    else
        printf '[WARN] %s = %s (want %s)\n' "$name" "${value:-(empty)}" "$expected"
        WARNS=$((WARNS + 1))
    fi
}

check_set() {
    local name="$1" value="$2" level="$3"
    CHECKS=$((CHECKS + 1))
    if [ -z "$value" ] && ! directive_exists "$name"; then
        [ "$QUIET" -eq 0 ] && printf '[SKIP] %s (not present on this PHP build)\n' "$name"
        return 0
    fi
    case "$value" in
        ""|"no value")
            if [ "$level" = "FAIL" ]; then
                printf '[FAIL] %s is not set\n' "$name"; FAILS=$((FAILS + 1))
            else
                printf '[WARN] %s is not set\n' "$name"; WARNS=$((WARNS + 1))
            fi
            ;;
        *) [ "$QUIET" -eq 0 ] && printf '[PASS] %s is set (%s)\n' "$name" "$value" ;;
    esac
}

check_includes() {
    local name="$1" value="$2" required="$3" level="$4"
    CHECKS=$((CHECKS + 1))
    local val_norm
    val_norm=$(printf '%s' "$value" | tr ',' '\n' | tr -d ' \r')
    local missing=""
    local tok
    while IFS= read -r tok; do
        [ -z "$tok" ] && continue
        if ! printf '%s\n' "$val_norm" | grep -qxF "$tok"; then
            missing="$missing $tok"
        fi
    done <<EOF
$(printf '%s' "$required" | tr ',' '\n' | tr -d ' \r')
EOF
    if [ -z "$missing" ]; then
        [ "$QUIET" -eq 0 ] && printf '[PASS] %s includes required functions\n' "$name"
        return 0
    fi
    if [ "$level" = "FAIL" ]; then
        printf '[FAIL] %s missing:%s\n' "$name" "$missing"; FAILS=$((FAILS + 1))
    else
        printf '[WARN] %s missing:%s\n' "$name" "$missing"; WARNS=$((WARNS + 1))
    fi
}

version_ge() {
    local IFS=.
    local -a a b
    # shellcheck disable=SC2206
    a=($1)
    b=($2)
    local i max x y
    max=${#a[@]}
    [ "${#b[@]}" -gt "$max" ] && max=${#b[@]}
    for ((i = 0; i < max; i++)); do
        x="${a[i]:-0}"; y="${b[i]:-0}"
        x="${x%%[!0-9]*}"; y="${y%%[!0-9]*}"
        x="${x:-0}"; y="${y:-0}"
        if [ "$x" -gt "$y" ]; then return 0; fi
        if [ "$x" -lt "$y" ]; then return 1; fi
    done
    return 0
}

# --- run audit -------------------------------------------------------------

PHP_VERSION=$("$PHP_BIN" "${PHP_ARGS[@]}" -r 'echo PHP_VERSION;' 2>/dev/null)
if [ -z "$PHP_VERSION" ]; then
    echo "ERROR: could not determine PHP version" >&2
    exit 2
fi

printf 'PHP hardening audit — PHP %s\n' "$PHP_VERSION"
printf '%s\n' '-----------------------------------------------------------'

CHECKS=$((CHECKS + 1))
case "$PHP_VERSION" in
    8.5.*) fixed="8.5.12" ;;
    8.4.*) fixed="8.4.27" ;;
    8.3.*) fixed="8.3.36" ;;
    8.2.*) fixed="8.2.35" ;;
    *)     fixed="" ;;
esac

if [ -z "$fixed" ]; then
    [ "$QUIET" -eq 0 ] && printf '[PASS] version %s (branch not in CVE advisory)\n' "$PHP_VERSION"
elif version_ge "$PHP_VERSION" "$fixed"; then
    [ "$QUIET" -eq 0 ] && printf '[PASS] version %s >= %s\n' "$PHP_VERSION" "$fixed"
else
    printf '[WARN] version %s < %s (below fixed baseline)\n' "$PHP_VERSION" "$fixed"
    WARNS=$((WARNS + 1))
fi

# Core hardening
check "expose_php"              "$(get_directive expose_php)"              "Off" FAIL
check "display_errors"          "$(get_directive display_errors)"          "Off" FAIL
check "display_startup_errors"  "$(get_directive display_startup_errors)"  "Off" FAIL
check "log_errors"              "$(get_directive log_errors)"              "On"  FAIL
check "allow_url_include"       "$(get_directive allow_url_include)"       "Off" FAIL
check_set "error_log"           "$(get_directive error_log)"                    WARN

# Sessions
check "session.cookie_httponly"          "$(get_directive session.cookie_httponly)"          "On"  FAIL
check "session.use_strict_mode"          "$(get_directive session.use_strict_mode)"          "On"  FAIL
check "session.use_only_cookies"         "$(get_directive session.use_only_cookies)"         "On"  FAIL
check "session.use_trans_sid"            "$(get_directive session.use_trans_sid)"            "Off" FAIL
check "session.upload_progress.enabled"  "$(get_directive session.upload_progress.enabled)"  "Off" FAIL
check "fatal_error_backtraces"           "$(get_directive fatal_error_backtraces)"           "Off" FAIL
check "session.cookie_secure"            "$(get_directive session.cookie_secure)"            "On"  WARN

# Execution hardening
check_includes "disable_functions" "$(get_directive disable_functions)" \
    "exec,passthru,shell_exec,system,proc_open,popen" FAIL

# Context-dependent (may break apps)
check_set "open_basedir"        "$(get_directive open_basedir)"                WARN
check "allow_url_fopen"         "$(get_directive allow_url_fopen)"         "Off" WARN

# Memory limit
CHECKS=$((CHECKS + 1))
mem_val=$(get_directive memory_limit)
case "$mem_val" in
    ""|"-1")
        printf '[WARN] memory_limit = %s (want a finite value like 128M)\n' "${mem_val:-(unset)}"
        WARNS=$((WARNS + 1))
        ;;
    *)
        [ "$QUIET" -eq 0 ] && printf '[PASS] memory_limit = %s\n' "$mem_val"
        ;;
esac

# --- summary ---------------------------------------------------------------

if [ "$QUIET" -eq 0 ]; then
    loaded=$(get_directive "Loaded Configuration File")
    printf '\n--- context ---\n'
    printf '  php binary:  %s\n' "$PHP_BIN"
    printf '  php version: %s\n' "$PHP_VERSION"
    if [ -n "$INI_FILE" ]; then
        printf '  ini file:    %s (isolated via -n -c)\n' "$INI_FILE"
    else
        printf '  ini file:    %s\n' "${loaded:-<none>}"
    fi
fi

printf '\n--- summary ---\n'
printf '  checks: %d   fail: %d   warn: %d\n' "$CHECKS" "$FAILS" "$WARNS"

if [ "$FAILS" -gt 0 ]; then
    echo "RESULT: FAIL ($FAILS failed check(s))"
    exit 1
fi
if [ "$WARNS" -gt 0 ]; then
    echo "RESULT: PASS (with $WARNS warning(s))"
    exit 0
fi
echo "RESULT: PASS"
exit 0