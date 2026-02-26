#!/bin/bash
# Build script for RC2014 MIDI Synthesizer using z88dk Docker container
#
# Usage:
#   ./build_docker.sh          Build the full synthesizer
#   ./build_docker.sh test     Build the minimal hardware test
#   ./build_docker.sh all      Build both

set -e

HD_IMAGE="${HD_IMAGE:-cheese.img}"

build_synth() {
    echo "=== Building MIDI Synthesizer ==="

    local extra_cflags=""
    if [ "${NO_HW_IO:-}" = "1" ]; then
        echo "(NO_HW_IO=1: hardware I/O calls disabled)"
        extra_cflags="-DNO_HW_IO"
    fi

    docker run --rm -v "$(pwd):/workspace" -w /workspace z88dk/z88dk:latest \
        zcc +cpm -v -SO3 -O3 --opt-code-size \
        -Iinclude $extra_cflags \
        src/main.c src/core/synthesizer.c src/core/chip_manager.c src/midi/midi_driver.c src/chips/ym2149.c \
        -create-app -o midisynth

    if [ -f "$HD_IMAGE" ]; then
        local dest="${HD_DEST:-0:midisyn.com}"
        echo "Copying MIDISYNTH.COM to $HD_IMAGE as $dest..."
        cpmrm -f wbw_hd512 "$HD_IMAGE" "$dest" 2>/dev/null || true
        cpmcp -f wbw_hd512 "$HD_IMAGE" MIDISYNTH.COM "$dest"
    fi

    ls -la MIDISYNTH.COM
}

build_test() {
    echo "=== Building Minimal Hardware Test ==="

    docker run --rm -v "$(pwd):/workspace" -w /workspace z88dk/z88dk:latest \
        zcc +cpm -v -O2 \
        test_minimal.c \
        -create-app -o minimal_test

    if [ -f "$HD_IMAGE" ]; then
        local dest="${TEST_DEST:-0:mt.com}"
        echo "Copying MINIMAL_TEST.COM to $HD_IMAGE as $dest..."
        cpmrm -f wbw_hd512 "$HD_IMAGE" "$dest" 2>/dev/null || true
        cpmcp -f wbw_hd512 "$HD_IMAGE" MINIMAL_TEST.COM "$dest"
    fi

    ls -la MINIMAL_TEST.COM
}

# Clean previous builds
echo "Cleaning previous build artifacts..."
rm -f *.com *.COM *.bin *.lst *.ihx *.hex *.map *.dsk

case "${1:-synth}" in
    test)
        build_test
        ;;
    all)
        build_synth
        echo ""
        build_test
        ;;
    synth|"")
        build_synth
        ;;
    *)
        echo "Usage: $0 [synth|test|all]"
        exit 1
        ;;
esac

echo ""
echo "MAME RC2014 example (with CF card + AY sound):"
echo "  mame rc2014zedp -bus:5 cf -hard cheese.img -bus:12 ay_sound -window"
