# RC2014 Multi-Chip MIDI Synthesizer

A modular MIDI synthesizer for RC2014/Z80 systems, currently supporting YM2149 PSG with OPL3 FM planned for the future. Runs on CP/M with real-time MIDI note and CC parameter control.

## Features

- **YM2149 PSG synthesis**: 3-channel square wave with volume envelopes and noise
- **MIDI input**: Note on/off, velocity, pitch bend, program change, running status
- **CC parameter control**: Volume, envelope (ADSR), vibrato, tremolo, modulation via CC#1-12
- **Voice allocation**: 3-voice polyphony with oldest-note voice stealing
- **Hardware detection**: Automatic YM2149 detection via register read/write verification
- **Audio test mode**: Built-in test sequences (tones, scale, arpeggio) - no MIDI keyboard required
- **Configurable I/O ports**: Default 0xD8/0xD0, overridable via `ports.conf` or at runtime

## Hardware Requirements

- RC2014 Z80-based computer (or compatible)
- CP/M 2.2 or later, 64KB RAM
- YM2149 / AY-3-8910 sound card (default I/O ports: 0xD8 register, 0xD0 data)
- Serial MIDI interface (optional - the synth can be tested without one)

## Building

### Docker Build (Recommended)

```bash
./build_docker.sh
```

This compiles with `z88dk/z88dk:latest` via Docker and produces:
- `midisynth.com` — CP/M executable
- `midisynth` — CP/M floppy disk image (z80pack format)

If a `cheese.img` hard disk image is present in the project directory, the script also copies `midisynth.com` onto it using `cpmcp`. Override with environment variables:

```bash
HD_IMAGE=/path/to/disk.img HD_DEST=0:synth.com ./build_docker.sh
```

### Local z88dk Build

If you have z88dk installed locally:

```bash
make all
make clean   # remove build artifacts
```

## Running

### MAME Emulation (RC2014 + CF card + AY sound)

```bash
mame rc2014zedp -bus:5 cf -hard cheese.img -bus:12 ay_sound -window
```

Then at the CP/M prompt:

```
A>midisyn
```

### Real Hardware

Copy `MIDISYNTH.COM` to your CP/M system disk (it will appear as `midisyn.com` due to CP/M's 8.3 filename limit).

## Interactive Commands

| Key   | Action                              |
|-------|-------------------------------------|
| `h`   | Show help                           |
| `s`   | Show system status (chip, voices)   |
| `i`   | Show current I/O port addresses     |
| `r`   | Reload port configuration from file |
| `t`   | Run audio test sequence             |
| `p`   | Panic — all notes off               |
| `1`   | Select YM2149 chip                  |
| `2`   | Select OPL3 chip (not implemented)  |
| `q`   | Quit program                        |

## MIDI CC Mapping

| CC     | Function         | Notes                          |
|--------|------------------|--------------------------------|
| CC#1-4 | Volume           | Applied to first active voice  |
| CC#5   | Attack time      | Envelope frequency             |
| CC#6   | Decay time       | Envelope shape                 |
| CC#7   | Sustain level    | Maps to volume 0-15            |
| CC#8   | Release time     | Envelope frequency             |
| CC#9   | Vibrato depth    | Not yet implemented in hardware|
| CC#10  | Tremolo rate     | Not yet implemented in hardware|
| CC#11  | Pitch bend (CC)  | Secondary to MIDI pitch bend   |
| CC#12  | Modulation depth | Not yet implemented in hardware|

Standard MIDI pitch bend messages are also supported (14-bit resolution).

## Note Range

MIDI notes 24 (C1) through 96 (C7) are supported. Notes outside this range are clamped to the nearest valid value. The frequency table is calculated for a 1.8432 MHz clock.

## Port Configuration

Default I/O ports (R5 RC2014 YM2149 board):
- Register port: `0xD8`
- Data port: `0xD0`

To override, create a `ports.conf` file:

```
addr_port=0xD8
data_port=0xD0
```

Or press `r` at runtime to reload from file, and `i` to display the current ports.

## Minimal Hardware Test

A standalone test program (`test_minimal.c`) is included for verifying basic YM2149 I/O independently of the full synthesizer. It sweeps channel A pitch in a loop — if you hear descending tones, the chip and I/O ports are working.

```bash
./build_docker.sh test
```

Then run `A>mt` at the CP/M prompt.

## E2E Testing (MAME)

Automated end-to-end tests run the synthesizer inside MAME's RC2014 emulation using a null-modem serial connection. The test suite boots RomWBW/CP/M, launches `midisynth`, exercises interactive commands (help, status, I/O ports, audio test), and verifies output over the serial link. Audio is recorded via MAME's `-wavwrite` and checked for non-silence.

### Prerequisites

```bash
# Install dependencies (Debian/Ubuntu)
sudo apt install mame cpmtools python3 sox

# One-time setup: download RomWBW ROM and install cpmtools disk format
./tests/e2e/setup_e2e.sh
```

### Running the Tests

```bash
# Full run (build + test)
./tests/e2e/run_e2e.sh

# Skip build step (reuse existing cheese.img)
./tests/e2e/run_e2e.sh --no-build

# Force headless mode (also auto-detected when no display is available)
./tests/e2e/run_e2e.sh --headless --no-build
```

### How It Works

1. **Build**: Compiles the synthesizer via the z88dk Docker container and copies the binary onto the CP/M hard-disk image.
2. **TCP server**: `null_modem_terminal.py` starts a TCP server on a free port.
3. **MAME launch**: MAME boots `rc2014zedp` with the emulated SIO serial port wired to the TCP server via null-modem (`-bitb socket.127.0.0.1:<port>`).
4. **Boot interaction**: The Python script waits for the RomWBW boot loader, boots from the ROM Disk (which always has CP/M), switches to drive `C:` (the CF hard disk), then waits for the CP/M prompt.
5. **Test commands**: Launches `midisynth`, then sends `h` (help), `s` (status), `i` (I/O ports), `t` (audio test), `q` (quit) and asserts on the serial output.
6. **Audio check**: The WAV file recorded by `-wavwrite` is checked for non-silence (requires `sox`).
7. **Cleanup**: A Lua watchdog (`mame_test.lua`) monitors for a done-flag file and exits MAME cleanly.

### Architecture

```
run_e2e.sh           Shell orchestrator (build, launch, collect results)
  |
  +-- null_modem_terminal.py   TCP server ← MAME connects as client
  |     Handles: boot loader, CP/M prompt, midisynth commands, assertions
  |
  +-- MAME (rc2014zedp)        Emulated RC2014 with CF + AY sound
  |     Serial port → null_modem → TCP socket
  |
  +-- mame_test.lua            Lua watchdog: polls done-flag, exits MAME
```

### Options

| Flag                   | Description                                        |
|------------------------|----------------------------------------------------|
| `--no-build`           | Skip Docker build step                             |
| `--headless`           | Force headless mode (`-video none -sound none`)    |
| `--timeout N`          | Overall watchdog timeout in seconds (default: 300) |
| `--mame PATH`          | Path to MAME binary                                |
| `--serial-port PORT`   | TCP port for null-modem (default: auto)            |
| `--rs232-slot SLOT`    | MAME RS232 slot name (default: auto-detect)        |
| `--list-slots`         | Print MAME slot info and exit                      |

### Environment Variables

| Variable         | Description                                      |
|------------------|--------------------------------------------------|
| `MAME`           | Path to MAME binary                              |
| `HD_IMAGE`       | Path to CP/M hard disk image                     |
| `SERIAL_PORT`    | TCP port for null-modem socket                   |
| `BOOT_DISK`      | RomWBW boot disk number (default: `1` for ROM Disk) |
| `HD_DRIVE`       | CP/M drive letter for IDE0 hard disk (default: `C`) |

## Project Structure

```
src/
  main.c              — Main loop, command handler, audio test
  core/
    synthesizer.c     — Voice allocation, system init, panic
    chip_manager.c    — Chip detection and selection
  midi/
    midi_driver.c     — MIDI byte parser, message dispatch, CC routing
  chips/
    ym2149.c          — YM2149 driver, register I/O, frequency table
include/
  chip_interface.h    — Abstract sound chip interface (voice_t, function pointers)
  synthesizer.h       — Synthesizer API
  chip_manager.h      — Chip manager API
  midi_driver.h       — MIDI driver API and state structs
  ym2149.h            — YM2149 registers, voice extras, frequency defines
  port_config.h       — I/O port configuration
test_minimal.c        — Standalone YM2149 I/O test
build_docker.sh       — Docker-based build script (synth, test, or all)
Makefile              — Local z88dk build
tests/e2e/
  run_e2e.sh          — E2E test orchestrator
  null_modem_terminal.py — TCP server for null-modem serial I/O
  mame_test.lua       — MAME Lua watchdog (polls done-flag, exits MAME)
  setup_e2e.sh        — One-time ROM + diskdef setup
```

## Future Development

- OPL3 FM driver (18-channel, 4-operator)
- Stereo output support
- Preset system with load/save
- Software vibrato/tremolo via frequency and volume modulation
- MIDI clock sync

## License

MIT License
