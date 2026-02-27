# Dockerfile — RC2014 MIDI Synthesizer build & test environment
#
# Contains everything needed to compile, package, and E2E-test the
# synthesizer:
#   - z88dk   (Z80 C cross-compiler, copied from official Alpine image)
#   - cpmtools (CP/M disk image manipulation)
#   - MAME    (RC2014 emulation for E2E tests)
#   - sox     (audio analysis for E2E tests)
#   - python3 (E2E test harness)
#
# Build:
#   docker build -t rc2014-build .
#
# Usage (compile only):
#   docker run --rm -v $(pwd):/workspace rc2014-build \
#     zcc +cpm -v -SO3 -O3 --opt-code-size -Iinclude \
#     src/main.c src/core/synthesizer.c src/core/chip_manager.c \
#     src/midi/midi_driver.c src/chips/ym2149.c -create-app -o midisynth
#
# Usage (full E2E):
#   docker run --rm -v $(pwd):/workspace rc2014-build \
#     ./tests/e2e/run_e2e.sh --headless

# ---------------------------------------------------------------------------
# Stage 1: collect z88dk and its musl-linked runtime libraries
# ---------------------------------------------------------------------------
FROM z88dk/z88dk:latest AS z88dk

# Identify shared libraries needed by z88dk binaries at runtime.
# z88dk is compiled on Alpine (musl libc), so these are musl-linked .so files.
# We collect them into /z88dk-libs for copying into the Ubuntu stage, where
# they are installed to a separate directory to avoid conflicting with
# Ubuntu's glibc libs.
RUN mkdir -p /z88dk-libs && \
    for bin in /opt/z88dk/bin/*; do \
        [ -f "$bin" ] && [ -x "$bin" ] && ldd "$bin" 2>/dev/null || true; \
    done \
    | awk '/=>/ && !/ld-musl/ {print $3}' \
    | sort -u \
    | while read -r lib; do [ -f "$lib" ] && cp -L "$lib" /z88dk-libs/; done

# ---------------------------------------------------------------------------
# Stage 2: Ubuntu with all build + test tools
# ---------------------------------------------------------------------------
FROM ubuntu:24.04

# Avoid interactive prompts during apt installs
ENV DEBIAN_FRONTEND=noninteractive

# Install build and test dependencies in a single layer
RUN apt-get update && apt-get install -y --no-install-recommends \
        # musl dynamic linker — needed to run Alpine-compiled z88dk binaries
        musl \
        # z88dk uses the system preprocessor and m4
        m4 \
        make \
        # CP/M disk image tools
        cpmtools \
        # MAME emulator (rc2014zedp driver)
        mame \
        mame-tools \
        # Audio analysis
        sox \
        # E2E test harness
        python3 \
        # ROM download (used by setup_e2e.sh)
        curl \
        unzip \
    && rm -rf /var/lib/apt/lists/*

# Copy z88dk from the official image
COPY --from=z88dk /opt/z88dk /opt/z88dk

# Copy Alpine (musl-linked) shared libraries that z88dk binaries depend on.
# These are placed in a separate directory to avoid conflicting with Ubuntu's
# glibc-linked libraries of the same name (e.g. libxml2, libgmp).
COPY --from=z88dk /z88dk-libs/ /usr/lib/z88dk-libs/

# Tell musl's dynamic linker where to find the Alpine shared libraries
RUN echo "/usr/lib/z88dk-libs" > /etc/ld-musl-x86_64.path

# z88dk environment
ENV Z88DK_PATH="/opt/z88dk" \
    PATH="/opt/z88dk/bin:${PATH}" \
    ZCCCFG="/opt/z88dk/lib/config/"

# MAME path (Ubuntu installs to /usr/games)
ENV MAME=/usr/games/mame

# Install the wbw_hd512 diskdef so cpmtools can work with RomWBW images
RUN printf '\n\
# RomWBW 8320KB Hard Disk Slice (512 directory entry format)\n\
diskdef wbw_hd512\n\
    seclen 512\n\
    tracks 1040\n\
    sectrk 16\n\
    blocksize 4096\n\
    maxdir 512\n\
    skew 0\n\
    boottrk 16\n\
    os 2.2\n\
end\n' >> /etc/cpmtools/diskdefs

# Smoke-test: verify z88dk runs on Ubuntu with musl compat layer
RUN zcc 2>&1 | head -1 && echo "z88dk OK"

WORKDIR /workspace
