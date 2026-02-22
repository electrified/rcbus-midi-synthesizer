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
```

## Future Development

- OPL3 FM driver (18-channel, 4-operator)
- Stereo output support
- Preset system with load/save
- Software vibrato/tremolo via frequency and volume modulation
- MIDI clock sync

## License

MIT License
