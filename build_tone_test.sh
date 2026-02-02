#!/bin/bash
# Build script for RC2014 YM2149 Tone Test using z88dk Docker container

set -e

echo "Building RC2014 YM2149 Tone Test with z88dk Docker container..."

# Clean previous builds
echo "Cleaning previous build artifacts..."
rm -f *.com *.bin *.lst *.ihx *.hex *.map *.dsk

# Compile tone test program
echo "Compiling tone test program..."
docker run --rm -v "$(pwd):/workspace" -w /workspace z88dk/z88dk:latest \
    zcc +cpm -vn -SO3 -O3 --opt-code-size \
    -Iinclude \
    test_tone.c \
    -create-app -o tone_test

echo "Creating CP/M disk image for RC2014 MAME emulation..."
docker run --rm -v "$(pwd):/workspace" -w /workspace z88dk/z88dk:latest \
    /opt/z88dk/bin/z88dk-appmake +cpmdisk --format z80pack --binfile TONE_TEST.COM --force-com-ext -o tone_test

echo "Build complete! Output files:"
echo "  - TONE_TEST.COM (CP/M executable)"
echo "  - tone_test (CP/M disk image for MAME RC2014)"

# Show file sizes
ls -la TONE_TEST.COM tone_test

echo ""
echo "Usage:"
echo "  - Real CP/M: copy TONE_TEST.COM to your CP/M system disk and execute 'tone_test'"
echo "  - MAME RC2014: use 'tone_test' as disk image file"
echo ""
echo "MAME RC2014 example:"
echo "  mame rc2014 -flop1 tone_test"