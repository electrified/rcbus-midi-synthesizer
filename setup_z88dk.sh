#!/bin/bash
# setup_z88dk.sh — Install z88dk Z80 cross-compiler from source
#
# Installs to $HOME/z88dk and writes environment setup to
# $HOME/z88dk/z88dk-env.sh (source it in your shell or .bashrc).
#
# Usage:
#   ./setup_z88dk.sh
#
# After install, activate with:
#   source ~/z88dk/z88dk-env.sh

set -euo pipefail

Z88DK_DIR="${Z88DK_DIR:-$HOME/z88dk}"
Z88DK_VERSION="${Z88DK_VERSION:-v2.4}"
TARBALL_URL="https://github.com/z88dk/z88dk/releases/download/${Z88DK_VERSION}/z88dk-src-${Z88DK_VERSION#v}.tgz"

info() { echo "[setup_z88dk] $*"; }
fail() { echo "[setup_z88dk] ERROR: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Check if already installed
# ---------------------------------------------------------------------------
if [ -x "$Z88DK_DIR/bin/zcc" ]; then
    info "z88dk already installed at $Z88DK_DIR"
    "$Z88DK_DIR/bin/zcc" +cpm -h 2>/dev/null | head -1 || true
    info "To use: source $Z88DK_DIR/z88dk-env.sh"
    exit 0
fi

# ---------------------------------------------------------------------------
# Install build dependencies (apt)
# ---------------------------------------------------------------------------
info "Installing build dependencies…"

DEPS="build-essential pkg-config gawk bison flex libxml2-dev libgmp-dev \
      libboost-dev zlib1g-dev liblzo2-dev m4 dos2unix texinfo curl ca-certificates"

SUDO=""
if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
fi

$SUDO apt-get update -qq
$SUDO apt-get install -y -qq $DEPS

# ---------------------------------------------------------------------------
# Download and Build
# ---------------------------------------------------------------------------
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

info "Downloading z88dk ${Z88DK_VERSION} source…"
curl -fSL "$TARBALL_URL" -o "$WORK/z88dk.tgz" \
    || fail "Could not download $TARBALL_URL"

info "Extracting…"
tar -xzf "$WORK/z88dk.tgz" -C "$WORK"
SRC="$WORK/z88dk"

info "Building z88dk (this takes a few minutes)…"
cd "$SRC"
export BUILD_SDCC=0
export BUILD_SDCC_HTTP=0
export MAKEFLAGS="-j$(nproc)"
chmod +x build.sh
./build.sh

# ---------------------------------------------------------------------------
# Install and Configure
# ---------------------------------------------------------------------------
info "Installing to $Z88DK_DIR…"
rm -rf "$Z88DK_DIR"
mkdir -p "$(dirname "$Z88DK_DIR")"
mv "$SRC" "$Z88DK_DIR"

cat > "$Z88DK_DIR/z88dk-env.sh" <<ENVEOF
# Source this file to add z88dk to your PATH
export PATH="${Z88DK_DIR}/bin:\$PATH"
export ZCCCFG="${Z88DK_DIR}/lib/config"
ENVEOF

info "Done. z88dk installed at $Z88DK_DIR"
info "Activate with: source $Z88DK_DIR/z88dk-env.sh"

"$Z88DK_DIR/bin/zcc" +cpm -h 2>/dev/null | head -1 || true
