#!/bin/bash
# Build script for RC2014 MIDI Synthesizer using Makefile
#
# Usage:
#   ./build_docker.sh [TARGETS] [VARIABLES]
#
# Examples:
#   ./build_docker.sh          Build the full synthesizer and disk image
#   ./build_docker.sh clean    Clean build artifacts
#   ./build_docker.sh all      Build the binary only
#   ./build_docker.sh image HD_IMAGE=test.img
#
# When run outside the container, this script launches Docker automatically.
# When run inside the container (or if zcc is on PATH), it runs make.
#
# Environment variables:
#   HD_IMAGE=<path>    Disk image to create/update (default: cheese.img)
#   BUILD_IMAGE=<img>  Docker image to use (default: rc2014-build:latest)

set -e

# Maintain default from original script
# Use ${VAR-DEFAULT} instead of ${VAR:-DEFAULT} so that an empty string
# passed from the environment (like HD_IMAGE="") is respected.
HD_IMAGE="${HD_IMAGE-cheese.img}"
BUILD_IMAGE="${BUILD_IMAGE:-rc2014-build:latest}"

# ---------------------------------------------------------------------------
# Detect whether we are inside the build container (zcc on PATH) or on the
# host.  When on the host, re-exec the entire script inside the container.
# ---------------------------------------------------------------------------
if ! command -v zcc &>/dev/null; then
    echo "zcc not found on PATH — running inside Docker ($BUILD_IMAGE)"
    # Require the custom image — it contains z88dk built from source
    if ! docker image inspect "$BUILD_IMAGE" &>/dev/null; then
        echo "Image $BUILD_IMAGE not found."
        echo "Build it first with: docker build -t $BUILD_IMAGE ."
        exit 1
    fi
    exec docker run --rm \
        --user "$(id -u):$(id -g)" \
        -v "$(pwd):/workspace" -w /workspace \
        -e HD_IMAGE="$HD_IMAGE" \
        "$BUILD_IMAGE" \
        ./build_docker.sh "$@"
fi

# ---------------------------------------------------------------------------
# From here on we are running inside the container (or a host with zcc).
# ---------------------------------------------------------------------------

# Clean up any previous build artifacts if running the default build or clean/image
if [ $# -eq 0 ]; then
    echo "Cleaning previous build artifacts..."
    make clean
    echo "=== Building MIDI Synthesizer ==="
    make image HD_IMAGE="$HD_IMAGE"
else
    # Pass along arguments, ensuring HD_IMAGE is available as a variable
    make "$@" HD_IMAGE="$HD_IMAGE"
fi

if [ -f "MIDISYNTH.COM" ]; then
    ls -la MIDISYNTH.COM
fi

echo ""
echo "MAME RC2014 example (with CF card + AY sound):"
echo "  mame rc2014zedp -bus:5 cf -hard ${HD_IMAGE} -bus:12 ay_sound -window"
