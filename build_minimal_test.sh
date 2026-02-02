#!/bin/bash
# Build script for Minimal YM2149 Test using z88dk Docker container

set -e

echo "Building Minimal YM2149 Test with z88dk Docker container..."

# Clean previous builds
echo "Cleaning previous build artifacts..."
rm -f *.com *.bin *.lst *.ihx *.hex *.map *.dsk

# Compile minimal test program
echo "Compiling minimal test program..."
docker run --rm -v "$(pwd):/workspace" -w /workspace z88dk/z88dk:latest \
    zcc +cpm -v -O2 \
    test_minimal.c \
    -create-app -o minimal_test

# echo "Creating CP/M disk image for RC2014 MAME emulation..."
# docker run --rm -v "$(pwd):/workspace" -w /workspace z88dk/z88dk:latest \
#     /opt/z88dk/bin/z88dk-appmake +cpmdisk --format z80pack --binfile MINIMAL_TEST.COM --force-com-ext -o minimal_test

echo "Build complete! Output files:"
echo "  - MINIMAL_TEST.COM (CP/M executable)"
# echo "  - minimal_test (CP/M disk image for MAME RC2014)"

# Show file sizes
ls -la MINIMAL_TEST.COM minimal_test

echo ""
echo "Usage:"
echo "  - Real CP/M: copy MINIMAL_TEST.COM to your CP/M system disk and execute 'minimal_test'"
echo "  - MAME RC2014: use 'minimal_test' as disk image file"
echo ""
echo "MAME RC2014 example:"
echo "  mame rc2014 -flop1 minimal_test"
echo ""
echo "This is the simplest possible YM2149 test:"
echo "  - Writes directly to I/O ports 0xD8 and 0xD0"
echo "  - Sets up a continuous tone"
echo "  - No complex logic, just raw I/O writes"