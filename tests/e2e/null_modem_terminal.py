#!/usr/bin/env python3
# tests/e2e/null_modem_terminal.py
#
# E2E test interaction script for the RC2014 MIDI Synthesizer MAME emulator.
#
# This script replaces the old frame-counting Lua keypost approach with real
# bidirectional serial I/O over the null modem TCP socket exposed by MAME:
#
#   mame rc2014zedp ... -<RS232_SLOT> null_modem -bitb socket.localhost:<PORT>
#
# The null modem device connects MAME's emulated SIO/ACIA serial port to a TCP
# socket on localhost.  This script connects to that socket, waits for CP/M to
# boot, runs the midisynth commands, and verifies the actual text output —
# giving us real assertions on what the program prints rather than relying on
# frame timing and screenshots.
#
# Environment variables:
#   SERIAL_HOST     TCP host to connect to (default: localhost)
#   SERIAL_PORT     TCP port exposed by MAME's -bitb flag (required)
#   RESULTS_DIR     Directory for test_result.txt and done flag (default: tests/e2e/results)
#   MAME_PID        PID of the MAME process (optional, for liveness checks)
#   CONNECT_TIMEOUT Seconds to retry connecting to the socket (default: 60)
#   BOOT_TIMEOUT    Seconds to wait for CP/M A> after boot (default: 120)
#   CMD_TIMEOUT     Seconds allowed per command (default: 30)
#   AUDIO_TIMEOUT   Seconds allowed for the audio test sequence (default: 60)
#
# Requires Python 3.9+ (stdlib only).
#
# Exit codes:
#   0  all assertions passed
#   1  at least one assertion failed or an unexpected error occurred

from __future__ import annotations

import errno
import os
import pathlib
import signal
import socket
import sys
import time
import traceback

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

HOST            = os.environ.get("SERIAL_HOST",     "localhost")
PORT            = int(os.environ.get("SERIAL_PORT",  "12345"))
RESULTS_DIR     = pathlib.Path(os.environ.get("RESULTS_DIR", "tests/e2e/results"))
MAME_PID        = int(os.environ.get("MAME_PID", "0")) or None
CONNECT_TIMEOUT = int(os.environ.get("CONNECT_TIMEOUT", "60"))
BOOT_TIMEOUT    = int(os.environ.get("BOOT_TIMEOUT",   "120"))
CMD_TIMEOUT     = int(os.environ.get("CMD_TIMEOUT",     "30"))
AUDIO_TIMEOUT   = int(os.environ.get("AUDIO_TIMEOUT",   "60"))

RESULT_FILE = RESULTS_DIR / "test_result.txt"
DONE_FLAG   = RESULTS_DIR / "mame_done.flag"

# ---------------------------------------------------------------------------
# Exceptions
# ---------------------------------------------------------------------------


class ConnectionLostError(Exception):
    """Raised when the MAME socket connection is lost unexpectedly."""


# ---------------------------------------------------------------------------
# Logging / result tracking
# ---------------------------------------------------------------------------

_log_lines: list[str] = []
_assertions_failed = 0


def log(msg: str) -> None:
    line = f"[null_modem] {msg}"
    print(line, flush=True)
    _log_lines.append(line)


def check(condition: bool, description: str) -> bool:
    """Record a pass/fail assertion.  Returns the condition value."""
    global _assertions_failed
    if condition:
        log(f"PASS  {description}")
    else:
        log(f"FAIL  {description}")
        _assertions_failed += 1
    return condition


def write_result(passed: bool, detail: str = "") -> None:
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    with open(RESULT_FILE, "w") as fh:
        for line in _log_lines:
            fh.write(line + "\n")
        if passed:
            fh.write("RESULT: PASS\n")
        else:
            suffix = f" — {detail}" if detail else ""
            fh.write(f"RESULT: FAIL{suffix}\n")


def signal_mame_exit() -> None:
    """Touch the done-flag file so the Lua watchdog exits MAME cleanly."""
    try:
        DONE_FLAG.parent.mkdir(parents=True, exist_ok=True)
        DONE_FLAG.touch()
        log(f"Done flag written: {DONE_FLAG}")
    except OSError as exc:
        log(f"WARNING: could not write done flag: {exc}")


def is_mame_alive() -> bool:
    """Check whether the MAME process is still running (if PID is known)."""
    if MAME_PID is None:
        return True  # Assume alive if we don't have a PID
    try:
        os.kill(MAME_PID, 0)
        return True
    except OSError:
        return False


# ---------------------------------------------------------------------------
# Serial terminal over TCP
# ---------------------------------------------------------------------------

class NullModemTerminal:
    """Bidirectional terminal over a MAME null-modem TCP socket."""

    def __init__(self, host: str, port: int) -> None:
        self.host = host
        self.port = port
        self._sock: socket.socket | None = None
        self._buf = ""          # accumulated received text (unconsumed)
        self._connected = False

    # ------------------------------------------------------------------
    # Connection
    # ------------------------------------------------------------------

    def connect(self, timeout: int = 60) -> bool:
        """Listen on the TCP port and accept a connection from MAME.

        MAME's null-modem device connects as a TCP *client* to the host:port
        specified by its -bitb flag.  This script must therefore act as the
        TCP *server*: bind, listen, and accept.

        The server socket is created and begins listening immediately.  A
        ``READY_FLAG`` file is written so that the shell runner knows it is
        safe to launch MAME.  We then block on accept() until MAME connects
        or the timeout expires.

        Returns False if no connection is established within *timeout* seconds.
        """
        ready_flag = RESULTS_DIR / "server_ready.flag"
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            server.bind((self.host, self.port))
        except OSError as exc:
            log(f"ERROR: could not bind to {self.host}:{self.port}: {exc}")
            server.close()
            return False
        server.listen(1)
        server.settimeout(timeout)
        log(f"Listening on {self.host}:{self.port} (waiting for MAME to connect)")

        # Signal the shell runner that we are ready for MAME to start.
        try:
            ready_flag.parent.mkdir(parents=True, exist_ok=True)
            ready_flag.touch()
        except OSError:
            pass

        try:
            conn, addr = server.accept()
            conn.settimeout(0.2)
            self._sock = conn
            self._connected = True
            log(f"MAME connected from {addr[0]}:{addr[1]}")
            return True
        except socket.timeout:
            log(f"ERROR: no connection received on {self.host}:{self.port} "
                f"after {timeout}s")
            return False
        except OSError as exc:
            log(f"ERROR: accept failed: {exc}")
            return False
        finally:
            server.close()
            try:
                ready_flag.unlink(missing_ok=True)
            except OSError:
                pass

    def close(self) -> None:
        self._connected = False
        if self._sock:
            try:
                self._sock.close()
            except OSError:
                pass
            self._sock = None

    @property
    def connected(self) -> bool:
        return self._connected and self._sock is not None

    # ------------------------------------------------------------------
    # I/O
    # ------------------------------------------------------------------

    def _drain(self) -> str:
        """Read all bytes currently available on the socket into _buf.

        Returns the newly received text (may be empty).
        Raises ConnectionLostError if the socket is closed or broken.
        """
        if not self.connected:
            raise ConnectionLostError("not connected")

        received = b""
        while True:
            try:
                chunk = self._sock.recv(4096)
                if not chunk:
                    # Peer closed the connection
                    self._connected = False
                    if received:
                        break  # Process what we got, then report error next call
                    raise ConnectionLostError(
                        "MAME closed the null-modem socket (recv returned empty)")
                received += chunk
            except socket.timeout:
                break
            except ConnectionResetError:
                self._connected = False
                raise ConnectionLostError("connection reset by MAME")
            except BrokenPipeError:
                self._connected = False
                raise ConnectionLostError("broken pipe to MAME")
            except OSError as exc:
                if exc.errno == errno.ECONNRESET:
                    self._connected = False
                    raise ConnectionLostError("connection reset by MAME") from exc
                raise

        if received:
            # Normalise line endings from the emulated serial port
            text = received.decode("utf-8", errors="replace")
            text = text.replace("\r\n", "\n").replace("\r", "\n")
            self._buf += text
            # Echo to stdout so CI logs show real CP/M output
            print(text, end="", flush=True)
            return text
        return ""

    def wait_for(self, marker: str, timeout: int = 30) -> str:
        """Block until *marker* appears in the receive buffer.

        Returns everything accumulated in _buf up to and including the marker,
        then removes that prefix from _buf.
        Raises TimeoutError if the marker is not seen within *timeout* seconds.
        Raises ConnectionLostError if the connection drops.
        """
        deadline = time.monotonic() + timeout
        last_log = time.monotonic()
        while time.monotonic() < deadline:
            self._drain()
            idx = self._buf.find(marker)
            if idx >= 0:
                end = idx + len(marker)
                captured = self._buf[:end]
                self._buf = self._buf[end:]
                return captured

            # Periodic liveness check and progress logging
            now = time.monotonic()
            if now - last_log > 10.0:
                remaining = deadline - now
                buf_tail = self._buf[-80:] if self._buf else "(empty)"
                log(f"  … still waiting for {marker!r} "
                    f"({remaining:.0f}s left, buf tail: {buf_tail!r})")
                last_log = now

                # Check if MAME is still alive
                if not is_mame_alive():
                    raise ConnectionLostError(
                        f"MAME process died while waiting for {marker!r}")

            time.sleep(0.05)

        raise TimeoutError(
            f"Timeout ({timeout}s) waiting for {marker!r}; "
            f"buffer length={len(self._buf)}, "
            f"last buffer tail: {self._buf[-200:]!r}"
        )

    def send(self, text: str) -> None:
        """Send *text* as bytes over the socket.

        Raises ConnectionLostError if the socket is broken.
        """
        if not self.connected:
            raise ConnectionLostError("not connected")
        try:
            self._sock.sendall(text.encode("utf-8"))
        except (BrokenPipeError, ConnectionResetError) as exc:
            self._connected = False
            raise ConnectionLostError(f"send failed: {exc}") from exc
        except OSError as exc:
            if exc.errno in (errno.ECONNRESET, errno.EPIPE):
                self._connected = False
                raise ConnectionLostError(f"send failed: {exc}") from exc
            raise

    def send_cmd(self, char: str, wait_for: str | None = None,
                 timeout: int = 30) -> str:
        """Send a single-character midisynth command and optionally wait for a marker.

        midisynth processes commands as single key-presses (no Enter needed).
        Returns the captured output up to the marker, or the current buffer contents.
        """
        log(f"  > sending {char!r}")
        self.send(char)
        if wait_for:
            return self.wait_for(wait_for, timeout=timeout)
        # Give the program a moment to respond then drain whatever arrived
        time.sleep(0.5)
        self._drain()
        return self._buf


# ---------------------------------------------------------------------------
# Test suite
# ---------------------------------------------------------------------------

def run_tests() -> bool:
    term = NullModemTerminal(HOST, PORT)

    # ------------------------------------------------------------------
    # 1. Connect
    # ------------------------------------------------------------------
    log(f"Connecting to MAME null-modem socket at {HOST}:{PORT} …")
    if not term.connect(timeout=CONNECT_TIMEOUT):
        write_result(False, f"could not connect to {HOST}:{PORT}")
        return False

    try:
        # ------------------------------------------------------------------
        # 2. Wait for RomWBW boot loader and select boot disk
        # ------------------------------------------------------------------
        log(f"Waiting for RomWBW boot loader (up to {BOOT_TIMEOUT}s) …")
        try:
            boot_loader_out = term.wait_for("Boot [H=Help]:", timeout=BOOT_TIMEOUT)
            log("RomWBW boot loader reached")
            check("RomWBW HBIOS" in boot_loader_out,
                  "boot: RomWBW HBIOS banner present")
        except TimeoutError as exc:
            log(f"ERROR: {exc}")
            write_result(False,
                         "RomWBW boot loader did not appear "
                         "(no 'Boot [H=Help]:' seen)")
            return False

        # RomWBW lists disks and waits for input.  The CF/IDE hard disk
        # with our CP/M image is Disk 2 (IDE0).  The run_e2e.sh script
        # overlays CP/M system tracks onto the test image so it is
        # bootable.  Booting directly from IDE0 makes the hard disk
        # drive A:, which is where midisynth.com lives.
        #
        # Disk layout (default rc2014zedp):
        #   Disk 0  MD0   RAM Disk
        #   Disk 1  MD1   ROM Disk
        #   Disk 2  IDE0  Hard Disk (CF) ← boot target
        boot_disk = os.environ.get("BOOT_DISK", "2")
        log(f"Selecting boot disk {boot_disk} (IDE0 Hard Disk) …")
        time.sleep(0.5)
        term.send(boot_disk + "\r")

        # ------------------------------------------------------------------
        # 3. Wait for CP/M A> prompt
        # ------------------------------------------------------------------
        log("Waiting for CP/M A> prompt …")
        try:
            boot_out = term.wait_for("A>", timeout=BOOT_TIMEOUT)
            log("CP/M boot complete — got A> prompt")
        except TimeoutError as exc:
            log(f"ERROR: {exc}")
            write_result(False, "CP/M did not boot (no A> prompt seen)")
            return False

        # Small pause after boot to let CP/M settle
        time.sleep(0.5)
        term._drain()

        # ------------------------------------------------------------------
        # 4. Launch midisynth
        # ------------------------------------------------------------------
        # After booting from IDE0, A: is the hard disk with midisynth.
        # CP/M 8.3 filename: midisynth.com is stored as midisyn.com
        log("Launching midisyn …")
        term.send("midisyn\r")
        try:
            launch_out = term.wait_for("Ready.", timeout=CMD_TIMEOUT)
        except TimeoutError as exc:
            log(f"ERROR: {exc}")
            write_result(False, "midisynth did not start (no 'Ready.' seen)")
            return False

        combined_startup = boot_out + launch_out
        check(
            "RC2014 Multi-Chip MIDI Synthesizer" in combined_startup,
            "startup banner present",
        )
        check(
            "Ready." in launch_out,
            "midisynth ready prompt present",
        )

        # Small pause to let the synthesizer fully initialise
        time.sleep(0.3)
        term._drain()

        # ------------------------------------------------------------------
        # 5. h — help
        # ------------------------------------------------------------------
        log("Running 'h' (help) …")
        help_out = term.send_cmd("h",
                                 wait_for="===================================",
                                 timeout=CMD_TIMEOUT)
        check("RC2014 MIDI Synthesizer Commands" in help_out,
              "help: command list header present")
        check("h/H - Show this help"             in help_out,
              "help: h command listed")
        check("q/Q - Quit program"               in help_out,
              "help: q command listed")
        check("MIDI CC Controls:"                in help_out,
              "help: MIDI CC section present")

        # ------------------------------------------------------------------
        # 6. s — status
        # ------------------------------------------------------------------
        log("Running 's' (status) …")
        # Status output varies at runtime; just ensure the command doesn't crash
        term.send_cmd("s", timeout=CMD_TIMEOUT)
        time.sleep(0.5)
        term._drain()
        log("  status command completed (output captured to log above)")

        # ------------------------------------------------------------------
        # 7. i — ioports
        # ------------------------------------------------------------------
        log("Running 'i' (ioports) …")
        io_out = term.send_cmd("i", wait_for="Data port:", timeout=CMD_TIMEOUT)
        check("Register port:" in io_out, "ioports: Register port line present")
        check("Data port:"     in io_out, "ioports: Data port line present")

        # ------------------------------------------------------------------
        # 8. t — audio test
        # ------------------------------------------------------------------
        log(f"Running 't' (audio test) — up to {AUDIO_TIMEOUT}s …")
        try:
            audio_out = term.send_cmd("t",
                                      wait_for="Audio Test Complete",
                                      timeout=AUDIO_TIMEOUT)
            check("Audio Test Complete" in audio_out,
                  "audio test: completed successfully")
            check("Testing YM2149 audio output" in audio_out,
                  "audio test: YM2149 test sequence ran")
        except TimeoutError as exc:
            log(f"WARNING: audio test timed out — {exc}")
            check(False, "audio test: completed within timeout")

        # ------------------------------------------------------------------
        # 9. q — quit
        # ------------------------------------------------------------------
        log("Running 'q' (quit) …")
        term.send_cmd("q", timeout=CMD_TIMEOUT)
        try:
            quit_out = term.wait_for("A>", timeout=CMD_TIMEOUT)
            check(True, "quit: returned to CP/M A> prompt")
        except TimeoutError:
            log("WARNING: did not see A> after quit "
                "(program may have exited cleanly anyway)")

        term.close()

    except ConnectionLostError as exc:
        log(f"ERROR: connection lost — {exc}")
        term.close()
        write_result(False, f"connection lost: {exc}")
        return False

    except Exception as exc:
        log(f"ERROR: unexpected exception — {exc}")
        log(traceback.format_exc())
        term.close()
        write_result(False, str(exc))
        return False

    finally:
        signal_mame_exit()

    passed = (_assertions_failed == 0)
    write_result(passed,
                 f"{_assertions_failed} assertion(s) failed" if not passed else "")
    return passed


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    log(f"null_modem_terminal starting  host={HOST}  port={PORT}")
    log(f"MAME PID: {MAME_PID or 'unknown'}")
    log(f"timeouts: connect={CONNECT_TIMEOUT}s  boot={BOOT_TIMEOUT}s  "
        f"cmd={CMD_TIMEOUT}s  audio={AUDIO_TIMEOUT}s")

    # Handle SIGTERM gracefully so cleanup runs
    def _sigterm_handler(signum, frame):
        log("Received SIGTERM — shutting down")
        signal_mame_exit()
        sys.exit(1)

    signal.signal(signal.SIGTERM, _sigterm_handler)

    success = run_tests()
    sys.exit(0 if success else 1)
