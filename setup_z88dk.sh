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

# Core build tools
DEPS="build-essential bison flex m4 dos2unix texinfo curl"

# libgmp-dev: required by appmake for TI calculator target signing.
# If unavailable, we try to provide just the header + symlink manually.
DEPS="$DEPS libgmp-dev"

# libxml2-dev: required by z80svg (optional graphics tool).
# If unavailable, the build still produces all tools we need (zcc, z80asm, appmake).
DEPS="$DEPS libxml2-dev"

if command -v sudo >/dev/null 2>&1; then
    sudo apt-get update -qq 2>/dev/null || true
    sudo apt-get install -y -qq $DEPS 2>/dev/null \
        || info "Some deps failed to install — will attempt workarounds"
else
    apt-get update -qq 2>/dev/null || true
    apt-get install -y -qq $DEPS 2>/dev/null \
        || info "Some deps failed to install — will attempt workarounds"
fi

# ---------------------------------------------------------------------------
# Workaround: ensure gmp.h and libgmp.so exist even without libgmp-dev
# The runtime library (libgmp10) is usually pre-installed; we just need
# the header and the unversioned .so symlink for the linker.
# ---------------------------------------------------------------------------
if ! echo '#include <gmp.h>' | gcc -fsyntax-only -xc - 2>/dev/null; then
    info "gmp.h not found — attempting manual workaround…"
    GMP_SO=$(find /usr/lib -name "libgmp.so.*" 2>/dev/null | head -1)
    if [ -z "$GMP_SO" ]; then
        fail "libgmp runtime not found. Install libgmp-dev or libgmp10."
    fi
    # Try to fetch just the -dev .deb for the header
    GMP_DEB_URL=$(apt-cache show libgmp-dev 2>/dev/null \
        | grep '^Filename:' | head -1 | awk '{print $2}')
    if [ -n "$GMP_DEB_URL" ]; then
        MIRROR="http://us.archive.ubuntu.com/ubuntu"
        WORK_GMP=$(mktemp -d)
        info "Fetching gmp.h from ${MIRROR}/${GMP_DEB_URL}…"
        curl -fsSL "${MIRROR}/${GMP_DEB_URL}" -o "$WORK_GMP/libgmp-dev.deb" || true
        if [ -f "$WORK_GMP/libgmp-dev.deb" ]; then
            dpkg -x "$WORK_GMP/libgmp-dev.deb" "$WORK_GMP/extracted"
            GMP_H=$(find "$WORK_GMP/extracted" -name "gmp.h" | head -1)
            if [ -n "$GMP_H" ]; then
                info "Installing gmp.h to /usr/include/"
                if command -v sudo >/dev/null 2>&1; then
                    sudo cp "$GMP_H" /usr/include/gmp.h
                else
                    cp "$GMP_H" /usr/include/gmp.h
                fi
            fi
        fi
        rm -rf "$WORK_GMP"
    fi
    # Ensure the unversioned .so symlink exists
    if [ ! -e "$(dirname "$GMP_SO")/libgmp.so" ]; then
        info "Creating libgmp.so symlink → $GMP_SO"
        if command -v sudo >/dev/null 2>&1; then
            sudo ln -sf "$GMP_SO" "$(dirname "$GMP_SO")/libgmp.so"
        else
            ln -sf "$GMP_SO" "$(dirname "$GMP_SO")/libgmp.so"
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Download source tarball
# ---------------------------------------------------------------------------
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

info "Downloading z88dk ${Z88DK_VERSION} source…"
curl -fSL "$TARBALL_URL" -o "$WORK/z88dk.tgz" \
    || fail "Could not download $TARBALL_URL"

info "Extracting…"
tar -xzf "$WORK/z88dk.tgz" -C "$WORK"

# The tarball extracts to a directory named z88dk
SRC="$WORK/z88dk"
[ -d "$SRC" ] || fail "Expected $SRC after extraction"

# ---------------------------------------------------------------------------
# Build z88dk
# We skip SDCC by default — the sccz80 compiler is sufficient for CP/M
# targets. Set BUILD_SDCC=1 to include SDCC (adds ~10 min build time).
# The z80svg tool requires libxml2-dev; if missing the build errors out
# at that stage but all essential tools are already compiled.
# ---------------------------------------------------------------------------
info "Building z88dk (this takes a few minutes)…"
cd "$SRC"
export BUILD_SDCC="${BUILD_SDCC:-0}"
export BUILD_SDCC_HTTP="${BUILD_SDCC_HTTP:-0}"
chmod +x build.sh
./build.sh 2>&1 | tee /tmp/z88dk-build.log | tail -5 || {
    # Check if the failure was just z80svg (optional) — core tools may be fine
    if [ -x "$SRC/bin/zcc" ] && [ -x "$SRC/bin/z88dk-z80asm" ] && [ -x "$SRC/bin/z88dk-appmake" ]; then
        info "Build had errors (likely z80svg) but core tools are OK — continuing"
    else
        fail "z88dk build failed. See /tmp/z88dk-build.log"
    fi
}

# ---------------------------------------------------------------------------
# Install to Z88DK_DIR
# ---------------------------------------------------------------------------
info "Installing to $Z88DK_DIR…"
rm -rf "$Z88DK_DIR"
mv "$SRC" "$Z88DK_DIR"

# ---------------------------------------------------------------------------
# Write env helper
# ---------------------------------------------------------------------------
cat > "$Z88DK_DIR/z88dk-env.sh" <<ENVEOF
# Source this file to add z88dk to your PATH
export PATH="${Z88DK_DIR}/bin:\$PATH"
export ZCCCFG="${Z88DK_DIR}/lib/config"
ENVEOF

info "Done. z88dk installed at $Z88DK_DIR"
info ""
info "Activate with:"
info "  source $Z88DK_DIR/z88dk-env.sh"
info ""
"$Z88DK_DIR/bin/zcc" +cpm -h 2>/dev/null | head -1 || true
