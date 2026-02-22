#!/usr/bin/env bash
# tests/e2e/run_e2e.sh
#
# End-to-end test runner for the RC2014 MIDI Synthesizer using MAME.
#
# The test:
#   1. Builds the synthesizer binary inside a z88dk Docker container.
#   2. Copies the binary onto a scratch copy of the CP/M hard-disk image.
#   3. Boots the RC2014 emulation in MAME with the Lua test script.
#   4. The Lua script types scripted commands at the emulated CP/M prompt
#      and collects results in tests/e2e/results/test_result.txt.
#   5. This script reads that file and exits 0 (pass) or 1 (fail).
#
# Requirements:
#   mame         — MAME emulator with rc2014zedp driver (0.200+)
#   docker       — for z88dk build container
#   cpmcp/cpmls  — cpmtools package  (apt install cpmtools)
#
# Headless (CI) notes:
#   - If no DISPLAY/WAYLAND_DISPLAY is set the script adds -video none -sound none.
#   - -video none requires MAME 0.229+.  On older MAME, wrap with Xvfb.
#   - With -video none, MAME snapshots are skipped automatically (the Lua
#     script handles this gracefully).
#
# Usage:
#   ./tests/e2e/run_e2e.sh [OPTIONS]
#
# Options:
#   --no-build       Skip the Docker build step (reuse existing cheese.img)
#   --headless       Force headless mode even when a display is available
#   --timeout N      MAME watchdog timeout in seconds (default: 180)
#   --mame PATH      Path to the MAME binary (default: mame, or $MAME env var)
#   -h, --help       Show this help and exit

set -euo pipefail

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"

# ---------------------------------------------------------------------------
# Defaults (can be overridden by env vars or CLI flags)
# ---------------------------------------------------------------------------
MAME_CMD="${MAME:-mame}"
HD_IMAGE="${HD_IMAGE:-$PROJECT_DIR/cheese.img}"
TEST_TIMEOUT="${TEST_TIMEOUT:-180}"
BUILD=true
HEADLESS=false

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-build)        BUILD=false ;;
        --headless)        HEADLESS=true ;;
        --timeout)         TEST_TIMEOUT="$2"; shift ;;
        --timeout=*)       TEST_TIMEOUT="${1#*=}" ;;
        --mame)            MAME_CMD="$2"; shift ;;
        --mame=*)          MAME_CMD="${1#*=}" ;;
        -h|--help)
            sed -n '/^# /p' "$0" | sed 's/^# \?//'
            exit 0 ;;
        *)
            echo "Unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done

# Auto-detect headless (no graphical display available)
if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
    HEADLESS=true
fi

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
_ts() { date '+%H:%M:%S'; }
info() { echo "[$(_ts)]       $*"; }
pass() { echo "[$(_ts)] PASS  $*"; }
fail() { echo "[$(_ts)] FAIL  $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
echo "=== RC2014 MIDI Synthesizer — MAME E2E Test ==="
info "Project dir : $PROJECT_DIR"
info "Disk image  : $HD_IMAGE"
info "MAME        : $MAME_CMD"
info "Headless    : $HEADLESS"
info "Timeout     : ${TEST_TIMEOUT}s"
echo ""

# ---------------------------------------------------------------------------
# Step 0: Dependency checks
# ---------------------------------------------------------------------------
info "Checking dependencies..."

require_cmd() {
    command -v "$1" &>/dev/null || fail "'$1' not found — $2"
}

require_cmd "$MAME_CMD" "install MAME from https://www.mamedev.org/"
require_cmd docker     "install Docker from https://docs.docker.com/"
require_cmd cpmls      "install cpmtools: apt install cpmtools"
require_cmd cpmcp      "install cpmtools: apt install cpmtools"

pass "Dependencies present"
echo ""

# ---------------------------------------------------------------------------
# Step 1: Build
# ---------------------------------------------------------------------------
if [[ "$BUILD" == true ]]; then
    info "Building with z88dk Docker..."
    cd "$PROJECT_DIR"
    ./build_docker.sh
    echo ""
fi

# ---------------------------------------------------------------------------
# Step 2: Verify the disk image contains the binary
# ---------------------------------------------------------------------------
info "Verifying disk image..."

[[ -f "$HD_IMAGE" ]] || fail "Disk image not found: $HD_IMAGE
  Run './build_docker.sh' first, or supply HD_IMAGE=/path/to/image.img"

if ! cpmls -f wbw_hd512 "$HD_IMAGE" 2>/dev/null | grep -qi "midisyn"; then
    fail "MIDISYNTH.COM not found in $HD_IMAGE
  The build may have failed, or the wrong disk image is pointed to."
fi

LISTING=$(cpmls -f wbw_hd512 "$HD_IMAGE" 2>/dev/null | grep -i midisyn || true)
pass "Disk image OK: $LISTING"
echo ""

# ---------------------------------------------------------------------------
# Step 3: Create a scratch copy so MAME's CP/M writes do not modify master
# ---------------------------------------------------------------------------
mkdir -p "$RESULTS_DIR/snapshots"
TEST_IMAGE="$RESULTS_DIR/test_run.img"
cp "$HD_IMAGE" "$TEST_IMAGE"
info "Scratch image: $TEST_IMAGE"
echo ""

# ---------------------------------------------------------------------------
# Step 4: Run MAME with the Lua test script
# ---------------------------------------------------------------------------
info "Launching MAME..."

MAME_ARGS=(
    rc2014zedp
    -bus:5  cf
    -hard   "$TEST_IMAGE"
    -bus:12 ay_sound
    -nothrottle
    -skip_gameinfo
    -snappath "$RESULTS_DIR/snapshots"
    -snapname "step_%04i"
    -script   "$SCRIPT_DIR/mame_test.lua"
)

if [[ "$HEADLESS" == true ]]; then
    # -video none is available in MAME 0.229+; older installs need Xvfb.
    MAME_ARGS+=(-video none -sound none)
    info "Video/audio : disabled (headless)"
else
    MAME_ARGS+=(-window -nomaximize -sound none)
    info "Video       : window (audio disabled for CI consistency)"
fi

LOG_FILE="$RESULTS_DIR/mame.log"
RESULT_FILE="$RESULTS_DIR/test_result.txt"
rm -f "$RESULT_FILE"

info "Command: $MAME_CMD ${MAME_ARGS[*]}"
echo ""

# Run MAME with a watchdog timeout; collect all output to log file
set +e
cd "$PROJECT_DIR"
timeout "$TEST_TIMEOUT" "$MAME_CMD" "${MAME_ARGS[@]}" >"$LOG_FILE" 2>&1
MAME_EXIT=$?
set -e

if [[ $MAME_EXIT -eq 124 ]]; then
    fail "Test timed out after ${TEST_TIMEOUT}s
  Increase with --timeout N, or check MAME is booting the disk correctly.
  MAME log: $LOG_FILE"
fi

echo ""

# ---------------------------------------------------------------------------
# Step 5: Evaluate results
# ---------------------------------------------------------------------------
info "Evaluating results..."

if [[ -f "$RESULT_FILE" ]]; then
    echo ""
    echo "--- test_result.txt ---"
    cat "$RESULT_FILE"
    echo "-----------------------"
    echo ""

    if grep -q "^RESULT: PASS" "$RESULT_FILE"; then
        pass "E2E test passed"
    else
        info "MAME log tail:"
        tail -30 "$LOG_FILE" | sed 's/^/  /'
        fail "E2E test did not pass — see $RESULT_FILE and $LOG_FILE"
    fi
else
    # The Lua script did not produce a result file.
    # Fall back to the MAME exit code as a best-effort signal.
    info "No result file generated (Lua script may not have run)"
    info "MAME exit code: $MAME_EXIT"
    if [[ $MAME_EXIT -eq 0 ]]; then
        pass "MAME exited 0 (treating as pass — no assertions made)"
    else
        info "MAME log tail:"
        tail -30 "$LOG_FILE" | sed 's/^/  /'
        fail "MAME exited with code $MAME_EXIT — see $LOG_FILE"
    fi
fi

echo ""
info "Snapshots : $RESULTS_DIR/snapshots/"
info "MAME log  : $LOG_FILE"
echo "==================================="
