#!/usr/bin/env bash
# tests/e2e/run_e2e.sh
#
# End-to-end test runner for the RC2014 MIDI Synthesizer using MAME.
#
# How it works
# ------------
# 1. Builds the synthesizer binary inside a z88dk Docker container.
# 2. Copies the binary onto a scratch copy of the CP/M hard-disk image.
# 3. Boots the RC2014 emulation in MAME with its serial port wired to a
#    null-modem TCP socket (see "Null-modem approach" below).
# 4. null_modem_terminal.py connects to that socket, waits for the CP/M A>
#    prompt, launches midisynth, runs interactive commands (h/s/i/t/q), and
#    verifies the actual text output.
# 5. When done, the Python script writes tests/e2e/results/test_result.txt
#    and signals mame_test.lua to exit MAME via a done-flag file.
# 6. This script reads test_result.txt and exits 0 (pass) or 1 (fail).
# 7. Audio from the YM2149 emulation is recorded via MAME's -wavwrite flag.
#
# Null-modem approach (inspired by https://blog.thestateofme.com/2022/05/25/
#   attaching-a-terminal-emulator-to-a-mame-serial-port/)
# ----------------------------------------------------------------
# Instead of using MAME's built-in terminal emulation (where the only way to
# interact is via emu.keypost() inside a Lua script), we wire the emulated
# serial port to a TCP socket:
#
#   -<RS232_SLOT> null_modem -bitb socket.localhost:<PORT>
#
# This lets null_modem_terminal.py connect to the socket and perform genuine
# bidirectional serial I/O: it can read exactly what CP/M and midisynth print
# and assert on that text, instead of relying on frame-timed blind key-presses.
#
# MAME's built-in terminal window is replaced by "No screens attached to the
# system" — which is fine; all interaction goes through the TCP socket.
#
# Requirements:
#   mame         — MAME emulator with rc2014zedp driver (0.229+, tested with 0.264)
#   python3      — Python 3.9+ (stdlib only, no extra packages needed)
#   docker       — for z88dk build container
#   cpmcp/cpmls  — cpmtools package  (apt install cpmtools)
#   sox          — optional, for audio silence detection (apt install sox)
#
# One-time setup (RC2014 ROM + wbw_hd512 diskdef):
#   ./tests/e2e/setup_e2e.sh
#
# Usage:
#   ./tests/e2e/run_e2e.sh [OPTIONS]
#
# Options:
#   --no-build           Skip the Docker build step (reuse existing cheese.img)
#   --headless           Force headless mode even when a display is available
#   --timeout N          Overall watchdog timeout in seconds (default: 300)
#   --mame PATH          Path to the MAME binary (default: mame or $MAME env var)
#   --serial-port PORT   TCP port for the null-modem socket (default: auto)
#   --rs232-slot SLOT    MAME slot name for the RS232 port (default: auto-detect)
#   --list-slots         Print MAME -listslots output for rc2014zedp and exit
#   -h, --help           Show this help and exit

set -euo pipefail

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"

# ---------------------------------------------------------------------------
# Defaults (overridable by env vars or CLI flags)
# ---------------------------------------------------------------------------
MAME_CMD="${MAME:-$(command -v mame 2>/dev/null || command -v /usr/games/mame 2>/dev/null || echo mame)}"
HD_IMAGE="${HD_IMAGE:-$PROJECT_DIR/cheese.img}"
TEST_TIMEOUT="${TEST_TIMEOUT:-300}"
BUILD=true
HEADLESS=false
SERIAL_PORT="${SERIAL_PORT:-}"      # empty → auto-detect a free port
MIDI_PORT="${MIDI_PORT:-}"          # empty → auto-detect a free port (for AUX/MIDI)
RS232_SLOT="${RS232_SLOT:-}"        # empty → auto-discover via mame -listslots
RS232_SLOT_B="${RS232_SLOT_B:-}"    # empty → auto-discover rs232b via mame -listslots
LIST_SLOTS=false

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-build)         BUILD=false ;;
        --headless)         HEADLESS=true ;;
        --timeout)          TEST_TIMEOUT="$2"; shift ;;
        --timeout=*)        TEST_TIMEOUT="${1#*=}" ;;
        --mame)             MAME_CMD="$2"; shift ;;
        --mame=*)           MAME_CMD="${1#*=}" ;;
        --serial-port)      SERIAL_PORT="$2"; shift ;;
        --serial-port=*)    SERIAL_PORT="${1#*=}" ;;
        --midi-port)        MIDI_PORT="$2"; shift ;;
        --midi-port=*)      MIDI_PORT="${1#*=}" ;;
        --rs232-slot)       RS232_SLOT="$2"; shift ;;
        --rs232-slot=*)     RS232_SLOT="${1#*=}" ;;
        --rs232-slot-b)     RS232_SLOT_B="$2"; shift ;;
        --rs232-slot-b=*)   RS232_SLOT_B="${1#*=}" ;;
        --list-slots)       LIST_SLOTS=true ;;
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
_ts()  { date '+%H:%M:%S'; }
info() { echo "[$(_ts)]       $*"; }
pass() { echo "[$(_ts)] PASS  $*"; }
warn() { echo "[$(_ts)] WARN  $*"; }
fail() { echo "[$(_ts)] FAIL  $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Cleanup trap — ensure MAME and child processes are killed on exit/signal
# ---------------------------------------------------------------------------
MAME_PID=""
PYTHON_PID=""
cleanup() {
    local exit_code=$?
    set +e
    if [[ -n "$PYTHON_PID" ]] && kill -0 "$PYTHON_PID" 2>/dev/null; then
        warn "Cleaning up Python (PID $PYTHON_PID)…"
        kill "$PYTHON_PID" 2>/dev/null
    fi
    if [[ -n "$MAME_PID" ]] && kill -0 "$MAME_PID" 2>/dev/null; then
        warn "Cleaning up MAME (PID $MAME_PID)…"
        kill "$MAME_PID" 2>/dev/null
        sleep 1
        kill -0 "$MAME_PID" 2>/dev/null && kill -9 "$MAME_PID" 2>/dev/null
    fi
    # Remove stale flags
    rm -f "$RESULTS_DIR/mame_done.flag" "$RESULTS_DIR/server_ready.flag" 2>/dev/null
    exit "$exit_code"
}
trap cleanup EXIT INT TERM

# ---------------------------------------------------------------------------
echo "=== RC2014 MIDI Synthesizer — MAME E2E Test (null-modem) ==="
info "Project dir : $PROJECT_DIR"
info "Disk image  : $HD_IMAGE"
info "MAME        : $MAME_CMD"
info "Headless    : $HEADLESS"
info "Timeout     : ${TEST_TIMEOUT}s"
echo ""

# ---------------------------------------------------------------------------
# --list-slots helper: show all slots for rc2014zedp and exit
# ---------------------------------------------------------------------------
if [[ "$LIST_SLOTS" == true ]]; then
    info "Listing MAME slots for rc2014zedp …"
    "$MAME_CMD" rc2014zedp -listslots 2>&1
    exit 0
fi

# ---------------------------------------------------------------------------
# Step 0: Dependency checks
# ---------------------------------------------------------------------------
info "Checking dependencies…"

require_cmd() { command -v "$1" &>/dev/null || fail "'$1' not found — $2"; }

require_cmd "$MAME_CMD" "install MAME from https://www.mamedev.org/"
if [[ "$BUILD" == true ]]; then
    require_cmd docker  "install Docker from https://docs.docker.com/"
fi
require_cmd cpmls       "install cpmtools: apt install cpmtools"
require_cmd cpmcp       "install cpmtools: apt install cpmtools"
require_cmd python3     "install Python 3: apt install python3"

pass "Dependencies present"
echo ""

# ---------------------------------------------------------------------------
# Step 1: Build
# ---------------------------------------------------------------------------
if [[ "$BUILD" == true ]]; then
    info "Building with z88dk Docker…"
    cd "$PROJECT_DIR"
    ./build_docker.sh
    echo ""
fi

# ---------------------------------------------------------------------------
# Step 2: Verify the disk image contains the binary
# ---------------------------------------------------------------------------
info "Verifying disk image…"

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
# Step 4: Discover the RS232 slot (if not provided manually)
# ---------------------------------------------------------------------------
# mame rc2014zedp -listslots emits lines like:
#   rc2014zedp   bus:2:sio:porta:rs232   null_modem   terminal
# We look for a line that contains both "null_modem" and "terminal" to
# identify the console serial port, then extract the slot-name column.

discover_rs232_slot() {
    local machine="rc2014zedp"
    local slot
    # MAME -listslots prints slot names like "bus:4:sio:rs232a" as the
    # second whitespace-delimited field on slot-header lines.  We look
    # for the first RS232 port A slot (rs232a), which supports both
    # null_modem and terminal devices.
    slot=$(
        "$MAME_CMD" "$machine" -listslots 2>/dev/null \
        | grep -oP 'bus:\S*rs232a' \
        | head -1
    )
    echo "$slot"
}

if [[ -z "$RS232_SLOT" ]]; then
    info "Auto-detecting RS232 slot for rc2014zedp…"
    RS232_SLOT="$(discover_rs232_slot)"
    if [[ -z "$RS232_SLOT" ]]; then
        warn "Could not auto-detect RS232 slot."
        warn "Run with --list-slots to inspect available slots, then retry with"
        warn "  --rs232-slot <SLOT_NAME>"
        fail "RS232 slot discovery failed — cannot configure null-modem socket."
    fi
    info "Detected RS232 slot (console): $RS232_SLOT"
else
    info "Using supplied RS232 slot (console): $RS232_SLOT"
fi

# Discover rs232b (AUX/MIDI port) — same SIO board, port B
discover_rs232b_slot() {
    local machine="rc2014zedp"
    "$MAME_CMD" "$machine" -listslots 2>/dev/null \
    | grep -oP 'bus:\S*rs232b' \
    | head -1
}

if [[ -z "$RS232_SLOT_B" ]]; then
    info "Auto-detecting RS232 slot B (MIDI/AUX) for rc2014zedp…"
    RS232_SLOT_B="$(discover_rs232b_slot)"
    if [[ -z "$RS232_SLOT_B" ]]; then
        warn "Could not auto-detect RS232 slot B (MIDI)."
        warn "BIOS MIDI tests will be skipped."
    else
        info "Detected RS232 slot B (MIDI): $RS232_SLOT_B"
    fi
else
    info "Using supplied RS232 slot B (MIDI): $RS232_SLOT_B"
fi
echo ""

# ---------------------------------------------------------------------------
# Step 5: Pick a free TCP port for the null-modem socket
# ---------------------------------------------------------------------------
if [[ -z "$SERIAL_PORT" ]]; then
    SERIAL_PORT=$(python3 -c "
import socket
s = socket.socket()
s.bind(('', 0))
print(s.getsockname()[1])
s.close()
")
    info "Auto-selected TCP port (console): $SERIAL_PORT"
else
    info "Using supplied TCP port (console): $SERIAL_PORT"
fi

# Pick a free TCP port for the MIDI serial port (if rs232b was found)
if [[ -n "$RS232_SLOT_B" ]]; then
    if [[ -z "$MIDI_PORT" ]]; then
        MIDI_PORT=$(python3 -c "
import socket
s = socket.socket()
s.bind(('', 0))
print(s.getsockname()[1])
s.close()
")
        info "Auto-selected TCP port (MIDI): $MIDI_PORT"
    else
        info "Using supplied TCP port (MIDI): $MIDI_PORT"
    fi
else
    MIDI_PORT=0
    info "No MIDI serial port (rs232b not available)"
fi
echo ""

# ---------------------------------------------------------------------------
# Step 6: Build the MAME command line
# ---------------------------------------------------------------------------
MAME_ARGS=(
    rc2014zedp
    -bus:5  cf
    -hard   "$TEST_IMAGE"
    -bus:12 ay_sound
    -nothrottle
    -skip_gameinfo
    -autoboot_script "$SCRIPT_DIR/mame_test.lua"
    # Wire the emulated console serial port to a TCP socket via null-modem device
    "-${RS232_SLOT}" null_modem
    -bitb "socket.127.0.0.1:${SERIAL_PORT}"
)

# Wire the second serial port (AUX/MIDI) if available.
# MAME assigns bitbanger media mount names sequentially: -bitb for the first
# null_modem device, -bitb1 for the second.  Since rs232a (console) is
# instantiated first, it uses -bitb and rs232b (MIDI) uses -bitb1.
if [[ -n "$RS232_SLOT_B" && "$MIDI_PORT" -gt 0 ]]; then
    MAME_ARGS+=(
        "-${RS232_SLOT_B}" null_modem
        -bitb1 "socket.127.0.0.1:${MIDI_PORT}"
    )
    info "MIDI port  : ${RS232_SLOT_B} → TCP ${MIDI_PORT}"
fi

AUDIO_FILE="$RESULTS_DIR/audio.wav"
rm -f "$AUDIO_FILE"
MAME_ARGS+=(-wavwrite "$AUDIO_FILE")

if [[ "$HEADLESS" == true ]]; then
    export SDL_VIDEODRIVER=dummy
    export SDL_AUDIODRIVER=dummy
    # With null-modem the emulated system has no screen, so -video none is fine.
    # We keep the sound backend active (SDL with dummy driver) so that MAME's
    # internal audio mixer runs and -wavwrite actually captures YM2149 output.
    # Using -sound none would disable the audio pipeline entirely, resulting in
    # a silent WAV file.
    MAME_ARGS+=(-video none)
    info "Video       : none (headless, SDL_VIDEODRIVER=dummy)"
    info "Audio       : SDL dummy driver → $AUDIO_FILE via -wavwrite"
else
    # Even in windowed mode MAME will show "No screens attached" — that is
    # expected when null-modem replaces the built-in terminal.
    MAME_ARGS+=(-window -nomaximize -sound sdl)
    info "Video       : window (will show 'No screens attached' — expected)"
    info "Audio       : SDL → speakers + $AUDIO_FILE"
fi

LOG_FILE="$RESULTS_DIR/mame.log"
RESULT_FILE="$RESULTS_DIR/test_result.txt"
READY_FLAG="$RESULTS_DIR/server_ready.flag"
rm -f "$RESULT_FILE" "$RESULTS_DIR/mame_done.flag" "$READY_FLAG"

info "MAME command: $MAME_CMD ${MAME_ARGS[*]}"
echo ""

# ---------------------------------------------------------------------------
# Step 7: Start null-modem terminal server (background), then launch MAME
# ---------------------------------------------------------------------------
# MAME's null-modem device connects as a TCP *client* to the address given
# by -bitb.  The Python script acts as the TCP *server*: it binds to the
# port, writes a "server_ready.flag" file, and blocks on accept().  Once
# the flag appears we know the port is listening and it is safe to start
# MAME.
# ---------------------------------------------------------------------------
info "Starting null_modem_terminal.py as TCP server on port ${SERIAL_PORT}…"
echo "--- serial output begin ---"

SERIAL_HOST=127.0.0.1 \
SERIAL_PORT="$SERIAL_PORT" \
MIDI_PORT="$MIDI_PORT" \
RESULTS_DIR="$RESULTS_DIR" \
MAME_PID=0 \
CONNECT_TIMEOUT=90 \
BOOT_TIMEOUT=120 \
CMD_TIMEOUT=30 \
AUDIO_TIMEOUT=15 \
timeout "$TEST_TIMEOUT" python3 "$SCRIPT_DIR/null_modem_terminal.py" &
PYTHON_PID=$!
info "Python server PID: $PYTHON_PID"

# Wait for the Python server to signal it is listening
info "Waiting for server_ready.flag…"
READY_DEADLINE=$((SECONDS + 15))
while [[ ! -f "$READY_FLAG" ]]; do
    if ! kill -0 "$PYTHON_PID" 2>/dev/null; then
        echo "--- serial output end ---"
        fail "null_modem_terminal.py exited before becoming ready"
    fi
    if [[ $SECONDS -ge $READY_DEADLINE ]]; then
        echo "--- serial output end ---"
        kill "$PYTHON_PID" 2>/dev/null || true
        fail "Timed out waiting for Python server to become ready"
    fi
    sleep 0.2
done
info "Python server is listening — launching MAME"

# Step 7b: Launch MAME
info "Launching MAME in background (connecting to null-modem server on port ${SERIAL_PORT})…"
cd "$PROJECT_DIR"
timeout "$TEST_TIMEOUT" "$MAME_CMD" "${MAME_ARGS[@]}" >"$LOG_FILE" 2>&1 &
MAME_PID=$!
info "MAME PID: $MAME_PID"

# Give MAME a moment to start, then check it didn't crash immediately
sleep 2
if ! kill -0 "$MAME_PID" 2>/dev/null; then
    echo ""
    info "MAME exited immediately — likely a configuration or ROM error."
    info "MAME log:"
    cat "$LOG_FILE" | sed 's/^/  /'
    kill "$PYTHON_PID" 2>/dev/null || true
    fail "MAME failed to start (exited within 2s)"
fi
info "MAME running"

# ---------------------------------------------------------------------------
# Step 8: Wait for Python test script to finish (foreground wait)
# ---------------------------------------------------------------------------
info "Waiting for null_modem_terminal.py to complete tests…"

set +e
wait "$PYTHON_PID"
PYTHON_EXIT=$?
set -e

echo "--- serial output end ---"
echo ""

# ---------------------------------------------------------------------------
# Step 9: Wait for MAME to exit
# ---------------------------------------------------------------------------
# null_modem_terminal.py writes the done flag, which mame_test.lua picks up
# and calls manager.machine:exit().  Give MAME a few seconds to exit cleanly.
info "Waiting for MAME to exit (PID $MAME_PID)…"
MAME_EXITED=false
for _i in $(seq 1 20); do
    if ! kill -0 "$MAME_PID" 2>/dev/null; then
        MAME_EXITED=true
        info "MAME exited cleanly"
        break
    fi
    sleep 1
done

# If MAME is still running, send SIGTERM then SIGKILL
if [[ "$MAME_EXITED" == false ]]; then
    warn "MAME did not exit within 20s — sending SIGTERM"
    kill "$MAME_PID" 2>/dev/null || true
    for _i in $(seq 1 5); do
        if ! kill -0 "$MAME_PID" 2>/dev/null; then
            MAME_EXITED=true
            break
        fi
        sleep 1
    done
fi
if [[ "$MAME_EXITED" == false ]] && kill -0 "$MAME_PID" 2>/dev/null; then
    warn "MAME did not respond to SIGTERM — sending SIGKILL"
    kill -9 "$MAME_PID" 2>/dev/null || true
fi

# Collect MAME exit status (ignore if already gone)
wait "$MAME_PID" 2>/dev/null || true
MAME_PID=""  # Prevent cleanup trap from trying again
echo ""

# ---------------------------------------------------------------------------
# Step 10: Verify audio recording
# ---------------------------------------------------------------------------
info "Checking audio recording…"

AUDIO_MIN_BYTES=88200   # ~0.5 s at 44100 Hz / 16-bit / stereo

if [[ ! -f "$AUDIO_FILE" ]]; then
    warn "No WAV file at $AUDIO_FILE — MAME may not support -wavwrite here."
else
    AUDIO_BYTES=$(wc -c < "$AUDIO_FILE")
    if [[ "$AUDIO_BYTES" -lt "$AUDIO_MIN_BYTES" ]]; then
        warn "WAV is very small (${AUDIO_BYTES} bytes < ${AUDIO_MIN_BYTES} expected)"
        warn "Audio processing may not have run."
    else
        info "WAV file: $AUDIO_FILE (${AUDIO_BYTES} bytes)"
        if command -v sox &>/dev/null; then
            MAX_AMP=$(sox "$AUDIO_FILE" -n stat 2>&1 \
                      | awk -F: '/Maximum amplitude/ { gsub(/ /,"",$2); print $2 }')
            if awk "BEGIN { exit !($MAX_AMP > 0.001) }" 2>/dev/null; then
                pass "Audio non-silent (peak amplitude ${MAX_AMP})"
            else
                warn "Audio appears silent (peak amplitude ${MAX_AMP})"
                warn "YM2149 chip detection may have failed in MAME — check the log."
            fi
        else
            pass "WAV recorded: ${AUDIO_BYTES} bytes (install sox for silence check)"
        fi
    fi
fi
echo ""

# ---------------------------------------------------------------------------
# Step 11: Evaluate test results
# ---------------------------------------------------------------------------
info "Evaluating results…"

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
    info "No result file generated (null_modem_terminal.py may not have run)"
    info "Python exit code: $PYTHON_EXIT"
    if [[ $PYTHON_EXIT -eq 0 ]]; then
        pass "Python exited 0 (treating as pass — no assertions made)"
    else
        info "MAME log tail:"
        tail -30 "$LOG_FILE" | sed 's/^/  /'
        fail "Python script exited $PYTHON_EXIT — see $LOG_FILE"
    fi
fi

SERIAL_LOG_FILE="$RESULTS_DIR/serial_io.log"

echo ""
info "Audio      : $AUDIO_FILE"
info "Serial log : $SERIAL_LOG_FILE"
info "Snapshots  : $RESULTS_DIR/snapshots/"
info "MAME log   : $LOG_FILE"
echo "==================================="
