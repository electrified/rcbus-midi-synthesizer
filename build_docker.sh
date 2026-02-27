#!/bin/bash
# Build script for RC2014 MIDI Synthesizer
#
# Usage:
#   ./build_docker.sh          Build the full synthesizer
#   ./build_docker.sh test     Build the minimal hardware test
#   ./build_docker.sh all      Build both
#
# When run outside the container, this script launches Docker automatically.
# When run inside the container (or if zcc is on PATH), it compiles directly.
#
# Environment variables:
#   NO_HW_IO=1        Disable hardware I/O calls (for testing without real HW)
#   HD_IMAGE=<path>    Disk image to create/update (default: cheese.img, empty to skip)
#   BUILD_IMAGE=<img>  Docker image to use (default: rc2014-build:latest)

set -e

HD_IMAGE="${HD_IMAGE-cheese.img}"
BUILD_IMAGE="${BUILD_IMAGE:-rc2014-build:latest}"

# RomWBW wbw_hd512 slice size: 1040 tracks * 16 sectors * 512 bytes = 8,519,680
WBW_HD512_SIZE=8519680

# ---------------------------------------------------------------------------
# Detect whether we are inside the build container (zcc on PATH) or on the
# host.  When on the host, re-exec the entire script inside the container.
# ---------------------------------------------------------------------------
if ! command -v zcc &>/dev/null; then
    echo "zcc not found on PATH — running inside Docker ($BUILD_IMAGE)"
    # Fall back to the upstream z88dk image if custom image is not available
    if ! docker image inspect "$BUILD_IMAGE" &>/dev/null; then
        echo "Image $BUILD_IMAGE not found, falling back to z88dk/z88dk:latest"
        echo "(Build the full image with: docker build -t $BUILD_IMAGE .)"
        BUILD_IMAGE="z88dk/z88dk:latest"
    fi
    exec docker run --rm \
        -v "$(pwd):/workspace" -w /workspace \
        -e NO_HW_IO="${NO_HW_IO:-}" \
        -e HD_IMAGE="$HD_IMAGE" \
        "$BUILD_IMAGE" \
        ./build_docker.sh "$@"
fi

# ---------------------------------------------------------------------------
# From here on we are running inside the container (or a host with zcc).
# ---------------------------------------------------------------------------

create_disk_image() {
    # Create a blank RomWBW wbw_hd512 disk image filled with 0xE5 (CP/M empty).
    echo "Creating blank wbw_hd512 disk image: $HD_IMAGE ($WBW_HD512_SIZE bytes)"
    dd if=/dev/zero bs=512 count=16640 2>/dev/null | tr '\000' '\345' > "$HD_IMAGE"
    mkfs.cpm -f wbw_hd512 "$HD_IMAGE"
}

build_synth() {
    echo "=== Building MIDI Synthesizer ==="

    local extra_cflags=""
    if [ "${NO_HW_IO:-}" = "1" ]; then
        echo "(NO_HW_IO=1: hardware I/O calls disabled)"
        extra_cflags="-DNO_HW_IO"
    fi

    zcc +cpm -v -SO3 -O3 --opt-code-size \
        -Iinclude $extra_cflags \
        src/main.c src/core/synthesizer.c src/core/chip_manager.c src/midi/midi_driver.c src/chips/ym2149.c \
        -create-app -o midisynth

    if [ -n "$HD_IMAGE" ] && command -v mkfs.cpm &>/dev/null; then
        if [ ! -f "$HD_IMAGE" ]; then
            create_disk_image
        fi

        local dest="${HD_DEST:-0:midisyn.com}"
        echo "Copying MIDISYNTH.COM to $HD_IMAGE as $dest..."
        cpmrm -f wbw_hd512 "$HD_IMAGE" "$dest" 2>/dev/null || true
        cpmcp -f wbw_hd512 "$HD_IMAGE" MIDISYNTH.COM "$dest"
    fi

    ls -la MIDISYNTH.COM
}

build_test() {
    echo "=== Building Minimal Hardware Test ==="

    zcc +cpm -v -O2 \
        test_minimal.c \
        -create-app -o minimal_test

    if [ -n "$HD_IMAGE" ] && command -v mkfs.cpm &>/dev/null; then
        if [ ! -f "$HD_IMAGE" ]; then
            create_disk_image
        fi

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
