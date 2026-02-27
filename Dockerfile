# Dockerfile — RC2014 MIDI Synthesizer build & test environment
#
# Contains everything needed to compile, package, and E2E-test the
# synthesizer:
#   - z88dk   (Z80 C cross-compiler, built from source)
#   - cpmtools (CP/M disk image manipulation)
#   - MAME    (RC2014 emulation for E2E tests)
#   - RomWBW  (ROM image + CP/M system tracks for MAME)
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

FROM ubuntu:24.04

# Avoid interactive prompts during apt installs
ENV DEBIAN_FRONTEND=noninteractive

# z88dk release to build
ARG Z88DK_VERSION=v2.4

# Install z88dk build dependencies and project runtime tools in a single layer
RUN apt-get update && apt-get install -y --no-install-recommends \
        # z88dk build dependencies (per https://github.com/z88dk/z88dk/wiki/installation)
        build-essential \
        bison \
        flex \
        libxml2-dev \
        libgmp-dev \
        m4 \
        dos2unix \
        texinfo \
        curl \
        ca-certificates \
        # CP/M disk image tools
        cpmtools \
        # MAME emulator (RC2014 driver for E2E tests)
        mame \
        mame-tools \
        # Audio analysis
        sox \
        # E2E test harness
        python3 \
        # ROM download (used by setup_e2e.sh)
        unzip \
    && rm -rf /var/lib/apt/lists/*

# Build z88dk from source (without SDCC — sccz80 is sufficient for CP/M targets)
RUN Z88DK_TARBALL="https://github.com/z88dk/z88dk/releases/download/${Z88DK_VERSION}/z88dk-src-${Z88DK_VERSION#v}.tgz" && \
    curl -fSL "$Z88DK_TARBALL" -o /tmp/z88dk.tgz && \
    tar -xzf /tmp/z88dk.tgz -C /tmp && \
    cd /tmp/z88dk && \
    export BUILD_SDCC=0 && \
    export BUILD_SDCC_HTTP=0 && \
    chmod +x build.sh && \
    ./build.sh 2>&1 | tail -20 && \
    mv /tmp/z88dk /opt/z88dk && \
    rm -f /tmp/z88dk.tgz

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

# ---------------------------------------------------------------------------
# RomWBW ROM and CP/M system tracks for MAME E2E tests
# ---------------------------------------------------------------------------
ARG ROMWBW_VERSION=3.5.1
ARG MAME_ROM_DIR=/opt/mame-roms/rc2014zedp

RUN mkdir -p "$MAME_ROM_DIR" && \
    # Try both URL patterns (with and without 'v' prefix in the asset name)
    ( curl -fsSL "https://github.com/wwarthen/RomWBW/releases/download/v${ROMWBW_VERSION}/RomWBW-v${ROMWBW_VERSION}-Package.zip" \
          -o /tmp/romwbw.zip || \
      curl -fsSL "https://github.com/wwarthen/RomWBW/releases/download/v${ROMWBW_VERSION}/RomWBW-${ROMWBW_VERSION}-Package.zip" \
          -o /tmp/romwbw.zip ) && \
    # Extract the RC2014 Z80 standard ROM
    ROM_PATH=$(unzip -Z1 /tmp/romwbw.zip | grep -i 'Binary/RCZ80_std\.rom$' | head -1) && \
    unzip -p /tmp/romwbw.zip "$ROM_PATH" > "$MAME_ROM_DIR/rcz80_std_3_0_1.rom" && \
    # Extract blank HD image (pre-formatted wbw_hd512 CP/M disk, no system tracks needed)
    BLANK_PATH=$(unzip -Z1 /tmp/romwbw.zip | grep -i 'Binary/hd512_blank\.img$' | head -1) && \
    unzip -p /tmp/romwbw.zip "$BLANK_PATH" > "$MAME_ROM_DIR/hd512_blank.img" && \
    rm -f /tmp/romwbw.zip

# Configure MAME to find the ROMs
RUN mkdir -p /root/.mame && \
    echo "rompath /opt/mame-roms" > /root/.mame/mame.ini

# Smoke-test: verify z88dk runs
RUN zcc 2>&1 | head -1 && echo "z88dk OK"

WORKDIR /workspace
