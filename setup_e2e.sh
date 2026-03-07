#!/usr/bin/env bash
# setup_e2e.sh
#
# One-time setup script for the MAME e2e test prerequisites.
# Logic matches the Dockerfile.
#
# Usage:
#   ./setup_e2e.sh [all|cpmtools|diskdefs|mame|romwbw]

set -euo pipefail

ROMWBW_VERSION="${ROMWBW_VERSION:-3.5.1}"
MAME_ROM_DIR="/opt/mame-roms/rc2014zedp"

SUDO=""
if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
fi

_ts()  { date '+%H:%M:%S'; }
info() { echo "[$(_ts)]       $*"; }
pass() { echo "[$(_ts)] PASS  $*"; }
fail() { echo "[$(_ts)] FAIL  $*" >&2; exit 1; }

install_cpmtools() {
    info "Installing cpmtools..."
    $SUDO apt-get update -qq
    $SUDO apt-get install -y -qq cpmtools
    pass "cpmtools installed."
}

install_diskdefs() {
    info "Installing wbw_hd512 diskdef..."
    local diskdef_file="/etc/cpmtools/diskdefs"

    # Ensure directory exists if we're not in a typical layout
    if [ ! -d "/etc/cpmtools" ]; then
        $SUDO mkdir -p /etc/cpmtools
    fi

    if [ -f "$diskdef_file" ] && grep -q "diskdef wbw_hd512" "$diskdef_file" 2>/dev/null; then
        info "wbw_hd512 already defined in $diskdef_file"
        return
    fi

    printf '\n\
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
end\n' | $SUDO tee -a "$diskdef_file" > /dev/null
    pass "wbw_hd512 diskdef added to $diskdef_file"
}

install_mame() {
    info "Installing MAME and test dependencies..."
    $SUDO apt-get update -qq
    $SUDO apt-get install -y -qq mame mame-tools sox python3 curl unzip ca-certificates build-essential make
    pass "MAME and dependencies installed."
}

install_romwbw() {
    info "Installing RomWBW $ROMWBW_VERSION ROM and blank disk image..."
    $SUDO mkdir -p "$MAME_ROM_DIR"

    local tmp_zip="/tmp/romwbw.zip"

    info "  Downloading RomWBW package..."
    ( curl -fsSL "https://github.com/wwarthen/RomWBW/releases/download/v${ROMWBW_VERSION}/RomWBW-v${ROMWBW_VERSION}-Package.zip" -o "$tmp_zip" || \
      curl -fsSL "https://github.com/wwarthen/RomWBW/releases/download/v${ROMWBW_VERSION}/RomWBW-${ROMWBW_VERSION}-Package.zip" -o "$tmp_zip" )

    info "  Extracting ROM..."
    local rom_path=$(unzip -Z1 "$tmp_zip" | grep -i 'Binary/RCZ80_std\.rom$' | head -1)
    unzip -p "$tmp_zip" "$rom_path" | $SUDO tee "$MAME_ROM_DIR/rcz80_std_3_0_1.rom" > /dev/null

    info "  Extracting blank HD image..."
    local blank_path=$(unzip -Z1 "$tmp_zip" | grep -i 'Binary/hd512_blank\.img$' | head -1)
    unzip -p "$tmp_zip" "$blank_path" | $SUDO tee "$MAME_ROM_DIR/hd512_blank.img" > /dev/null

    rm -f "$tmp_zip"

    info "  Configuring MAME..."
    mkdir -p "$HOME/.mame"
    if [ ! -f "$HOME/.mame/mame.ini" ]; then
        echo "rompath /opt/mame-roms" > "$HOME/.mame/mame.ini"
    elif ! grep -q "rompath /opt/mame-roms" "$HOME/.mame/mame.ini"; then
        echo "rompath /opt/mame-roms" >> "$HOME/.mame/mame.ini"
    fi

    pass "RomWBW and MAME configuration complete."
}

# MAIN
TARGET="${1:-all}"

case "$TARGET" in
    cpmtools)
        install_cpmtools
        ;;
    diskdefs)
        install_diskdefs
        ;;
    mame)
        install_mame
        ;;
    romwbw)
        install_romwbw
        ;;
    all)
        install_cpmtools
        install_diskdefs
        install_mame
        install_romwbw
        ;;
    *)
        echo "Usage: $0 [all|cpmtools|diskdefs|mame|romwbw]"
        exit 1
        ;;
esac

echo ""
pass "E2E Setup complete."
