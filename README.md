# RC2014 Multi-Chip MIDI Synthesizer

A modular MIDI synthesizer for RC2014/Z80 systems, supporting YM2149 now and OPL3 in the future. Designed to run on CP/M with full real-time CC parameter control from MIDI keyboards.

## Features

- **Multi-Chip Architecture**: Modular design supporting YM2149 PSG now, OPL3 FM later
- **MIDI CC Control**: Full support for 8 knobs + 4 sliders (CC#1-12)
- **Real-time Parameter Control**: Volume, envelope, effects via MIDI Continuous Controllers
- **Voice Allocation**: Intelligent voice management with voice stealing
- **CP/M Compatible**: Compiled for z88dk CP/M environment
- **Interactive Mode**: Command-line interface for chip selection and control

## Hardware Requirements

### Minimum System
- RC2014 Z80-based computer
- CP/M 2.2 or later
- 64KB RAM minimum
- Serial MIDI interface (RC2014 MIDI board)
- YM2149 sound card (address 0x90/0x91)

### Optional Hardware
- OPL3 sound card (future support)
- Rotary knob MIDI keyboard with CC output

## Building

### Prerequisites
- z88dk development kit
- Make utility
- Linux/Unix development environment
- Docker (optional, for containerized builds)

### Build with Docker (Recommended)
The easiest way to build is using the provided Docker script:

```bash
./build_docker.sh
```

This script uses the simple `zcc +cpm -create-app` command to:
- Compile all source files with proper z88dk flags
- Automatically generate the CP/M `.com` executable
- Create a CP/M disk image for RC2014 MAME emulation
- Requires no local z88dk installation

**Output files:**
- `midisynth.com` - CP/M executable (for real hardware)
- `midisynth` - CP/M disk image (for MAME RC2014)

### Manual Build with z88dk
If you have z88dk installed locally:

```bash
make all
```

### Build Options
```bash
make debug      # Debug build
make release    # Optimized release build  
make clean      # Clean build files
make test       # Build and test
```

### Docker Build Requirements
- Docker installed and running
- The `z88dk/z88dk:latest` image will be pulled automatically
- No local z88dk installation needed

## Installation

### For Real CP/M Hardware
1. Compile the synthesizer:
   - With Docker: `./build_docker.sh`
   - Without Docker: `make all`
2. Copy `midisynth.com` to your CP/M system disk
3. Run from CP/M: `A>midisynth`

### For MAME RC2014 Emulation
1. Build the project: `./build_docker.sh`
2. Launch MAME with the generated disk image:
   ```bash
   mame rc2014 -flop1 midisynth
   ```
3. In CP/M: `A>midisynth`

## MIDI CC Mapping

### Knobs (CC#1-8)
- **CC#1-4**: Volume controls (per voice or global)
- **CC#5**: Attack time
- **CC#6**: Decay time
- **CC#7**: Sustain level
- **CC#8**: Release time

### Sliders (CC#9-12)
- **CC#9**: Vibrato depth
- **CC#10**: Tremolo rate
- **CC#11**: Pitch bend
- **CC#12**: Modulation depth

## Usage

### Interactive Commands
- `h` - Show help
- `s` - Show system status
- `p` - Panic (all notes off)
- `1` - Select YM2149 chip
- `2` - Select OPL3 chip (future)
- `q` - Quit program

### MIDI Operation
1. Connect MIDI keyboard to RC2014 MIDI interface
2. Run synthesizer: `A>midisynth`
3. Play notes on keyboard - they should sound immediately
4. Adjust knobs/sliders - parameters change in real-time

## Architecture

### Modular Design
```
┌─────────────┐    ┌──────────────────┐    ┌─────────────┐
│  MIDI       │    │  Abstract       │    │  Chip       │
│  Keyboard   ├───▶│  Sound Chip    ├───▶│  Manager    │
│  (CC + Notes)│    │  Interface     │    │  (Selection)│
└─────────────┘    └──────────────────┘    └─────────────┘
```

### File Structure
- `src/chips/` - Sound chip drivers (YM2149, OPL3)
- `src/midi/` - MIDI interface and parser
- `src/core/` - Voice allocation, chip management
- `include/` - Header files
- `Makefile` - z88dk build system
- `build_docker.sh` - Docker build script (creates .com + disk image)

## Supported Sound Chips

### YM2149 (Current)
- 3-channel PSG synthesis
- Volume, envelope, noise generation
- Compatible with existing RC2014 YM2149 boards

### OPL3 (Future)
- 18-channel FM synthesis
- 4-operator modes
- Stereo output
- Backward compatible with OPL2

## Development

### Adding New Chips
1. Implement chip interface in `src/chips/`
2. Add to chip manager detection
3. Update voice allocation logic
4. Test with existing MIDI CC mapping

### Extending MIDI CC
1. Update `midi_driver.h` control definitions
2. Add handling in `midi_driver.c`
3. Map to chip-specific parameters

## Troubleshooting

### No Sound
- Check YM2149 board connections
- Verify I/O address (default 0x90/0x91)
- Check MIDI interface connection

### MIDI Not Responding
- Verify MIDI keyboard is sending CC messages
- Check RC2014 MIDI board configuration
- Test MIDI interface with other software

### Build Errors
- Ensure z88dk is properly installed (or use Docker build)
- Check C library compatibility (sdcc_iy)
- Verify include paths
- Docker issues: Ensure Docker is running and can pull images

### MAME RC2014 Issues
- Ensure MAME recognizes RC2014 system: `mame -listsystems | grep rc2014`
- Check that the disk image loads properly: look for disk activity in MAME
- Verify CP/M boots: should see `A>` prompt
- Program not found: ensure `midisynth.com` is properly placed on the disk image

## Future Development

- [ ] OPL3 driver implementation
- [ ] 4-operator FM synthesis modes
- [ ] Stereo output support
- [ ] Advanced envelope generators
- [ ] Preset system with load/save
- [ ] Real-time parameter interpolation
- [ ] Voice priority system

## License

MIT License - feel free to use, modify, and distribute.

## Contributing

Contributions welcome! Please fork and submit pull requests for:
- New chip drivers
- MIDI feature enhancements
- Bug fixes and optimizations
- Documentation improvements