#!/usr/bin/env bash
# tests/audit.sh — self-test for scripts/audit.sh
#
# Positive control: hardened ini must PASS (exit 0)
# Negative control: minimal ini must FAIL (exit 1) — proves audit is not a no-op

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
AUDIT="$REPO_ROOT/scripts/audit.sh"
HARDENED="$REPO_ROOT/php.ini.d/99-hardening.ini"

[ -x "$AUDIT" ] || { echo "missing or not executable: $AUDIT" >&2; exit 2; }
[ -r "$HARDENED" ] || { echo "missing: $HARDENED" >&2; exit 2; }
command -v php >/dev/null || { echo "SKIP: php not installed" >&2; exit 0; }

echo "--- positive control: 99-hardening.ini must PASS ---"
if ! "$AUDIT" -i "$HARDENED" >/dev/null 2>&1; then
    "$AUDIT" -i "$HARDENED" 2>&1 | tail -5
    echo "audit.sh FAIL: hardened ini did not pass" >&2
    exit 1
fi
echo "audit.sh PASS on hardened ini"

echo "--- negative control: bare ini must FAIL ---"
TMP=$(mktemp --suffix=.ini)
trap 'rm -f "$TMP"' EXIT
printf '; deliberately empty — compiled defaults should fail audit\n' > "$TMP"

if "$AUDIT" -i "$TMP" >/dev/null 2>&1; then
    echo "audit.sh FAIL: audit passed an unhardened ini (audit is a no-op!)" >&2
    exit 1
fi
echo "audit.sh PASS on unhardened ini (correctly failed)"
echo "audit-smoke: PASS"
