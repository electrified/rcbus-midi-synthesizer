# CLAUDE.md — Development Guide for AI Assistants

## Project Overview

RC2014 Multi-Chip MIDI Synthesizer — a CP/M program for RC2014 Z80 systems that turns a YM2149/AY-3-8910 sound chip into a real-time MIDI synthesizer. Built with z88dk (Z80 C cross-compiler).

## Build Commands

```bash
# Docker build (recommended — no local z88dk needed)
./build_docker.sh          # builds midisynth.com and copies to cheese.img
./build_docker.sh test     # builds the minimal hardware test (mt.com)

# Build the Docker image (one-time, contains z88dk + MAME + cpmtools + sox)
docker build -t rc2014-build .

# Local z88dk build
make all
make clean
```

## E2E Tests

```bash
# One-time setup (downloads RomWBW ROM, installs cpmtools diskdef)
./tests/e2e/setup_e2e.sh

# Run tests (requires MAME, cpmtools, python3)
MAME=/usr/games/mame ./tests/e2e/run_e2e.sh --no-build --headless

# With build step
./tests/e2e/run_e2e.sh --headless
```

### E2E Test Architecture

The tests use MAME's null-modem serial emulation over TCP:

1. `null_modem_terminal.py` starts a **TCP server** on a free port
2. `run_e2e.sh` launches MAME which connects as a **TCP client** via `-bitb socket.127.0.0.1:<port>`
3. The Python script interacts with RomWBW boot loader and CP/M over the serial link
4. `mame_test.lua` is a Lua watchdog that exits MAME when tests are done

**Key detail**: MAME's null-modem device connects as a TCP *client*. The Python test script must be the TCP *server* (bind/listen/accept). The shell runner starts Python first, waits for `server_ready.flag`, then launches MAME.

### E2E Test Flow

1. Wait for `Boot [H=Help]:` (RomWBW boot loader)
2. Send `c` to boot CP/M from ROM
3. Wait for `A>` (CP/M prompt on ROM disk)
4. Switch to `C:` drive (IDE0 hard disk with midisynth)
5. Launch `midisynth`, wait for `Ready.`
6. Run commands: `h` (help), `s` (status), `i` (I/O ports), `t` (audio test), `q` (quit)
7. Assert on serial output text for each command
8. Check WAV audio recording for non-silence

### Common Issues

- **RomWBW ROM CRC mismatch**: MAME warns about wrong checksums when using a RomWBW version newer than 3.0.1. This is harmless — the ROM still boots. The warning can be ignored.
- **RS232 slot detection**: MAME 0.264 uses `bus:4:sio:rs232a`. The slot auto-detection uses `grep -oP 'bus:\S*rs232a'`.
- **Serial line endings**: CP/M expects CR (`\r`), not LF (`\n`). The `send()` method in null_modem_terminal.py transmits raw bytes.
- **Boot command**: Default is `c` (boot CP/M from ROM). The hard disk (IDE0/CF) with midisynth is mapped as `C:`. Override with `BOOT_DISK` env var.
- **Disk image**: `cheese.img` is created from the RomWBW `hd512_blank.img` (baked into the Docker image). No system tracks are needed since we boot from ROM disk.

## Code Architecture

```
src/main.c           — Main loop, interactive command handler, audio test sequence
src/core/
  synthesizer.c      — Voice allocation (3-voice polyphony), system init
  chip_manager.c     — Sound chip detection and selection
src/midi/
  midi_driver.c      — MIDI byte parser (running status), CC routing
src/chips/
  ym2149.c           — YM2149/AY-3-8910 register-level driver, frequency table
include/
  chip_interface.h   — Abstract chip interface (function pointers for note_on/off/etc.)
  synthesizer.h      — Synth API (init, process_midi_byte, panic)
  midi_driver.h      — MIDI state machine, message types
  ym2149.h           — Hardware registers, voice state, frequency defines
  port_config.h      — I/O port addresses (configurable at runtime)
```

### Key Concepts

- **chip_interface.h** defines a vtable-style interface so multiple sound chips (YM2149 now, OPL3 future) share the same API
- **Voice allocation** uses oldest-note stealing when all 3 YM2149 channels are busy
- **MIDI parser** handles running status, 14-bit pitch bend, and routes CC#1-12 to synth parameters
- **Port configuration** is loaded from `ports.conf` at startup and can be reloaded at runtime with `r`

## Hardware Details

- **Target**: RC2014 Z80 @ 7.372 MHz, CP/M 2.2+, 64KB RAM
- **Sound chip**: YM2149 (or AY-3-8910 compatible) at I/O ports 0xD8 (register) / 0xD0 (data)
- **MIDI**: Serial input at 31250 baud (directly from MIDI DIN or via adapter)
- **Frequency table**: Calculated for 1.8432 MHz chip clock, MIDI notes 24–96

## MAME Emulation

```bash
# Interactive (with terminal window)
mame rc2014zedp -bus:5 cf -hard cheese.img -bus:12 ay_sound -window

# Headless with null-modem serial
mame rc2014zedp -bus:5 cf -hard cheese.img -bus:12 ay_sound \
  -bus:4:sio:rs232a null_modem -bitb socket.127.0.0.1:PORT \
  -nothrottle -skip_gameinfo -video none -sound none \
  -wavwrite audio.wav
```

The `cheese.img` file is a RomWBW-format CP/M hard disk image containing `MIDISYNTH.COM`.

## Docker Image

All build and test tools are packaged in a single Docker image (`rc2014-build`), built from the repo's `Dockerfile`. It is an Ubuntu 24.04 image that builds z88dk from source (v2.4 release tarball) and includes MAME, cpmtools, sox, and python3.

The image also includes the RomWBW ROM image and CP/M system tracks needed for MAME E2E tests (no separate `setup_e2e.sh` step required). The `wbw_hd512` cpmtools diskdef is baked in as well.

The `build_docker.sh` script auto-detects whether it's running inside the container (zcc on PATH) or on the host. On the host, it `exec`s itself inside Docker. The `rc2014-build` image must be built first with `docker build -t rc2014-build .`.

## Dependencies

- **Docker**: For the build/test container (the only hard requirement)
- **z88dk**: Z80 C cross-compiler (included in Docker image)
- **MAME 0.264+**: For emulation and E2E tests (included in Docker image)
- **cpmtools**: `cpmls`/`cpmcp` for manipulating CP/M disk images (included in Docker image)
- **Python 3.9+**: E2E test serial terminal (included in Docker image)
- **sox**: For audio silence detection in E2E tests (included in Docker image)
