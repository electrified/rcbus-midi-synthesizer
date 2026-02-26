#!/bin/bash
# setup_z88dk.sh — Install z88dk Z80 cross-compiler from nightly tarball
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
TARBALL_URL="http://nightly.z88dk.org/z88dk-latest.tgz"

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
sudo apt-get update -qq
sudo apt-get install -y -qq \
    build-essential bison flex libxml2-dev zlib1g-dev m4 \
    dos2unix texinfo curl >/dev/null 2>&1 \
    || info "Some optional deps missing — build may still succeed"

# ---------------------------------------------------------------------------
# Download nightly tarball
# ---------------------------------------------------------------------------
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

info "Downloading z88dk nightly tarball…"
curl -fSL "$TARBALL_URL" -o "$WORK/z88dk.tgz" \
    || fail "Could not download $TARBALL_URL"

info "Extracting…"
tar -xzf "$WORK/z88dk.tgz" -C "$WORK"

# The tarball extracts to a directory named z88dk
SRC="$WORK/z88dk"
[ -d "$SRC" ] || fail "Expected $SRC after extraction"

# ---------------------------------------------------------------------------
# Build z88dk (with SDCC for the sdcc_iy clib used by the project)
# ---------------------------------------------------------------------------
info "Building z88dk (this takes a few minutes)…"
cd "$SRC"
export BUILD_SDCC=1
export BUILD_SDCC_HTTP=1
chmod +x build.sh
./build.sh 2>&1 | tail -5

# ---------------------------------------------------------------------------
# Install to Z88DK_DIR
# ---------------------------------------------------------------------------
info "Installing to $Z88DK_DIR…"
rm -rf "$Z88DK_DIR"
mv "$SRC" "$Z88DK_DIR"

# ---------------------------------------------------------------------------
# Write env helper
# ---------------------------------------------------------------------------
cat > "$Z88DK_DIR/z88dk-env.sh" <<'ENVEOF'
# Source this file to add z88dk to your PATH
export PATH="$HOME/z88dk/bin:$PATH"
export ZCCCFG="$HOME/z88dk/lib/config"
ENVEOF

info "Done. z88dk installed at $Z88DK_DIR"
info ""
info "Activate with:"
info "  source $Z88DK_DIR/z88dk-env.sh"
info ""
"$Z88DK_DIR/bin/zcc" +cpm -h 2>/dev/null | head -1 || true
