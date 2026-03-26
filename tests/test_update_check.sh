#!/usr/bin/env bash
# Unit tests for cto-fleet-update-check
# Run: bash tests/test_update_check.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_CMD="$SCRIPT_DIR/bin/cto-fleet-update-check"
PASS=0
FAIL=0
TOTAL=0

setup() {
  TEST_DIR="$(mktemp -d)"
  export CTO_FLEET_STATE_DIR="$TEST_DIR"
  export CTO_FLEET_DIR="$TEST_DIR/fake-cto-fleet"
  mkdir -p "$CTO_FLEET_DIR/bin"
  # Create a minimal cto-fleet-config stub
  cat > "$CTO_FLEET_DIR/bin/cto-fleet-config" << 'STUB'
#!/usr/bin/env bash
echo ""
STUB
  chmod +x "$CTO_FLEET_DIR/bin/cto-fleet-config"
}

teardown() {
  rm -rf "$TEST_DIR"
}

assert_eq() {
  TOTAL=$((TOTAL + 1))
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc"
    echo "    expected: '$expected'"
    echo "    actual:   '$actual'"
  fi
}

assert_contains() {
  TOTAL=$((TOTAL + 1))
  local desc="$1" pattern="$2" actual="$3"
  if echo "$actual" | grep -q "$pattern"; then
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc (pattern '$pattern' not found in output)"
  fi
}

assert_empty() {
  TOTAL=$((TOTAL + 1))
  local desc="$1" actual="$2"
  if [ -z "$actual" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc (expected empty, got '$actual')"
  fi
}

# ─── Test: No VERSION file → silent exit ───────────────────────
echo "Test: no VERSION file"
setup
  result="$("$CHECK_CMD" 2>/dev/null || true)"
  assert_empty "no VERSION file outputs nothing" "$result"
teardown

# ─── Test: JUST_UPGRADED marker ────────────────────────────────
echo "Test: just-upgraded marker"
setup
  echo "1.3.0" > "$CTO_FLEET_DIR/VERSION"
  echo "1.2.0" > "$TEST_DIR/just-upgraded-from"
  result="$("$CHECK_CMD" 2>/dev/null || true)"
  assert_contains "outputs JUST_UPGRADED" "JUST_UPGRADED" "$result"
  assert_contains "contains old version" "1.2.0" "$result"
  assert_contains "contains new version" "1.3.0" "$result"
teardown

# ─── Test: Marker file is deleted after reading ────────────────
echo "Test: marker file cleanup"
setup
  echo "1.3.0" > "$CTO_FLEET_DIR/VERSION"
  echo "1.2.0" > "$TEST_DIR/just-upgraded-from"
  "$CHECK_CMD" >/dev/null 2>&1 || true
  TOTAL=$((TOTAL + 1))
  if [ ! -f "$TEST_DIR/just-upgraded-from" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: marker file deleted after reading"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: marker file still exists"
  fi
teardown

# ─── Test: Cache file created after check ──────────────────────
echo "Test: cache file created"
setup
  echo "1.3.0" > "$CTO_FLEET_DIR/VERSION"
  # Use invalid URL to trigger network failure (no cache should be written)
  export CTO_FLEET_REMOTE_URL="http://127.0.0.1:1/nonexistent"
  "$CHECK_CMD" >/dev/null 2>&1 || true
  TOTAL=$((TOTAL + 1))
  if [ ! -f "$TEST_DIR/last-update-check" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: no cache on network failure"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: cache file should not be written on network failure"
  fi
teardown

# ─── Test: UP_TO_DATE cache → silent exit ──────────────────────
echo "Test: UP_TO_DATE cache hit"
setup
  echo "1.3.0" > "$CTO_FLEET_DIR/VERSION"
  echo "UP_TO_DATE 1.3.0" > "$TEST_DIR/last-update-check"
  touch "$TEST_DIR/last-update-check"  # ensure fresh
  result="$("$CHECK_CMD" 2>/dev/null || true)"
  assert_empty "UP_TO_DATE cache produces no output" "$result"
teardown

# ─── Test: State directory permissions ─────────────────────────
echo "Test: state directory permissions"
setup
  echo "1.3.0" > "$CTO_FLEET_DIR/VERSION"
  echo "1.2.0" > "$TEST_DIR/just-upgraded-from"
  "$CHECK_CMD" >/dev/null 2>&1 || true
  TOTAL=$((TOTAL + 1))
  local_perm="$(stat -c '%a' "$TEST_DIR" 2>/dev/null || stat -f '%Lp' "$TEST_DIR" 2>/dev/null)"
  if [ "$local_perm" = "700" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: state dir is 700"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: state dir permission is $local_perm (expected 700)"
  fi
teardown

# ─── Test: Disabled update check ──────────────────────────────
echo "Test: disabled update check"
setup
  echo "1.3.0" > "$CTO_FLEET_DIR/VERSION"
  cat > "$CTO_FLEET_DIR/bin/cto-fleet-config" << 'STUB'
#!/usr/bin/env bash
if [ "${2:-}" = "update_check" ]; then echo "false"; else echo ""; fi
STUB
  chmod +x "$CTO_FLEET_DIR/bin/cto-fleet-config"
  result="$("$CHECK_CMD" 2>/dev/null || true)"
  assert_empty "disabled check outputs nothing" "$result"
teardown

# ─── Summary ──────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════"
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
echo "═══════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
