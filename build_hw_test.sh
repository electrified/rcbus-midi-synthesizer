#!/bin/bash
# Build script for RC2014 YM2149 Hardware Test using z88dk Docker container

set -e

echo "Building RC2014 YM2149 Hardware Test with z88dk Docker container..."

# Clean previous builds
echo "Cleaning previous build artifacts..."
rm -f *.com *.bin *.lst *.ihx *.hex *.map *.dsk

# Compile hardware test program
echo "Compiling hardware test program..."
docker run --rm -v "$(pwd):/workspace" -w /workspace z88dk/z88dk:latest \
    zcc +cpm -vn -SO3 -O3 --opt-code-size \
    test_hw.c \
    -create-app -o hw_test

echo "Creating CP/M disk image for RC2014 MAME emulation..."
docker run --rm -v "$(pwd):/workspace" -w /workspace z88dk/z88dk:latest \
    /opt/z88dk/bin/z88dk-appmake +cpmdisk --format z80pack --binfile HW_TEST.COM --force-com-ext -o hw_test

echo "Build complete! Output files:"
echo "  - HW_TEST.COM (CP/M executable)"
echo "  - hw_test (CP/M disk image for MAME RC2014)"

# Show file sizes
ls -la HW_TEST.COM hw_test

echo ""
echo "Usage:"
echo "  - Real CP/M: copy HW_TEST.COM to your CP/M system disk and execute 'hw_test'"
echo "  - MAME RC2014: use 'hw_test' as disk image file"
echo ""
echo "MAME RC2014 example:"
echo "  mame rc2014 -flop1 hw_test"
echo ""
echo "This test will:"
echo "  1. Test I/O port accessibility"
echo "  2. Play a 440 Hz tone for 3 seconds"
echo "  3. Help verify YM2149 hardware setup"