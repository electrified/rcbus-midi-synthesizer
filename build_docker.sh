#!/bin/bash
# Build script for RC2014 MIDI Synthesizer using z88dk Docker container

set -e

echo "Building RC2014 MIDI Synthesizer with z88dk Docker container..."

# Clean previous builds
echo "Cleaning previous build artifacts..."
rm -f *.com *.bin *.lst *.ihx *.hex *.map *.dsk

# Compile and create CP/M .com file using z88dk Docker container
echo "Compiling source files and creating CP/M executable..."
docker run --rm -v "$(pwd):/workspace" -w /workspace z88dk/z88dk:latest \
    zcc +cpm -subtype=z80pack -vn -SO3 -O3 --opt-code-size -clib=sdcc_iy \
    -Iinclude \
    src/main.c src/core/synthesizer.c src/core/chip_manager.c src/midi/midi_driver.c src/chips/ym2149.c \
    -create-app -o midisynth

echo "Creating CP/M disk image for RC2014 MAME emulation..."
docker run --rm -v "$(pwd):/workspace" -w /workspace z88dk/z88dk:latest \
    /opt/z88dk/bin/z88dk-appmake +cpmdisk --format z80pack --binfile midisynth_CODE.bin --force-com-ext -o midisynth

echo "Build complete! Output files:"
echo "  - midisynth.com (CP/M executable)"
echo "  - midisynth (CP/M disk image for MAME RC2014)"

# Show file sizes
ls -la midisynth.com midisynth

echo ""
echo "Usage:"
echo "  - Real CP/M: copy midisynth.com to your CP/M system disk and execute 'midisynth'"
echo "  - MAME RC2014: use 'midisynth' as the disk image file"
echo ""
echo "MAME RC2014 example:"
echo "  mame rc2014 -flop1 midisynth"