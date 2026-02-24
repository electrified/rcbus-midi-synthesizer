#!/usr/bin/env bash
# tests/e2e/setup_e2e.sh
#
# One-time setup script for the MAME e2e test prerequisites.
# Safe to re-run — all steps are idempotent.
#
# What it does:
#   1. Downloads RomWBW ROM images into MAME's rompath so the rc2014zedp
#      driver can boot.  RomWBW 3.5.1 (latest stable) is downloaded by
#      default and installed under the 3.0.1 MAME ROM name.  MAME will
#      warn about a CRC mismatch but boots normally.  Set ROMWBW_VERSION
#      to override.
#
#   2. Installs the wbw_hd512 CP/M disk format definition into cpmtools so
#      cpmls/cpmcp can read RomWBW hard-disk images.  Writes to
#      ~/.cpmtools/diskdefs (user-level, no root required) unless the
#      definition is already present in /etc/cpmtools/diskdefs.
#
# Requirements:
#   mame   — MAME emulator with rc2014zedp driver (0.229+)
#   curl   — to download the RomWBW release package
#   unzip  — to extract the ROM from the package
#
# Usage:
#   ./tests/e2e/setup_e2e.sh
#   ROMWBW_VERSION=3.4.1 ./tests/e2e/setup_e2e.sh   # use a different version

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# RomWBW release version to download.
# MAME 0.264 ships with ROM definitions for versions up to 3.0.1, but
# the exact release no longer needs to be present on GitHub — any
# version's RCZ80_std.rom will boot (MAME only warns about a CRC
# mismatch when the ROM does not match the built-in hash).
#
# Supported versions and the MAME ROM names they produce:
#   3.5.1  →  rcz80_std_3_0_1.rom  (latest stable, CRC won't match but boots)
#   3.0.1  →  rcz80_std_3_0_1.rom  (matches MAME 0.264 CRC, release removed)
#   3.0.0  →  rcz80_std_3_0_0.rom
#   2.9.1  →  rcz80_std_2_9_1.rom
#   2.9.0  →  rc_std_2_9_0.rom
ROMWBW_VERSION="${ROMWBW_VERSION:-3.5.1}"

# The MAME BIOS slot we target.  Even when downloading a newer RomWBW
# release the ROM file is installed under the 3.0.1 name so that MAME
# finds it without extra -bios flags.
MAME_BIOS_VERSION="${MAME_BIOS_VERSION:-3.0.1}"

# RomWBW GitHub release package URL.
# Releases ≥ 3.4.0 use a "v" prefix in the asset filename;
# older releases do not.  Try both patterns.
ROMWBW_PKG_URL_V="https://github.com/wwarthen/RomWBW/releases/download/v${ROMWBW_VERSION}/RomWBW-v${ROMWBW_VERSION}-Package.zip"
ROMWBW_PKG_URL_PLAIN="https://github.com/wwarthen/RomWBW/releases/download/v${ROMWBW_VERSION}/RomWBW-${ROMWBW_VERSION}-Package.zip"

# Name of the RC2014 Z80 standard ROM inside the RomWBW package (Binary/).
ROM_IN_PKG="RCZ80_std.rom"

# MAME ROM filename (as listed in MAME's rc2014_rom_ram_512k device XML).
MAME_ROM_NAME="rcz80_std_$(echo "$MAME_BIOS_VERSION" | tr '.' '_').rom"

# Special case: 2.9.0 uses a different prefix (rc_ not rcz80_)
if [[ "$MAME_BIOS_VERSION" == "2.9.0" ]]; then
    MAME_ROM_NAME="rc_std_2_9_0.rom"
    ROM_IN_PKG="RC_std.rom"
fi

# CRC32 values from MAME's XML, used to verify the downloaded ROM.
# When the downloaded version differs from MAME_BIOS_VERSION the CRC
# will not match — this is expected and MAME still boots (with a warning).
declare -A KNOWN_CRCS=(
    [rcz80_std_3_0_1.rom]="6d6b60c5"
    [rcz80_std_3_0_0.rom]="15b802f8"
    [rcz80_std_2_9_1.rom]="f7c52c5f"
    [rc_std_2_9_0.rom]="2045d238"
)
EXPECTED_CRC="${KNOWN_CRCS[$MAME_ROM_NAME]:-}"

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Derive MAME's primary rompath: honour $MAME env, then search PATH.
MAME_CMD="${MAME:-$(command -v mame 2>/dev/null || command -v /usr/games/mame 2>/dev/null || echo mame)}"

# The first entry of MAME's rompath (from `mame -showconfig`).
if command -v "$MAME_CMD" &>/dev/null; then
    MAME_ROMPATH_RAW=$("$MAME_CMD" -showconfig 2>/dev/null | awk -F'[ \t]+' '/^rompath/{print $2}' | cut -d';' -f1)
    # Expand $HOME / ~ in the path
    MAME_ROMPATH="${MAME_ROMPATH_RAW/\$HOME/$HOME}"
    MAME_ROMPATH="${MAME_ROMPATH/\~/$HOME}"
else
    MAME_ROMPATH="$HOME/mame/roms"
fi

# ROMs for rc2014zedp (a clone of rc2014) can live in either the machine
# directory or the device directory; use the machine directory for simplicity.
ROM_DIR="$MAME_ROMPATH/rc2014zedp"

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
_ts()  { date '+%H:%M:%S'; }
info() { echo "[$(_ts)]       $*"; }
pass() { echo "[$(_ts)] PASS  $*"; }
fail() { echo "[$(_ts)] FAIL  $*" >&2; exit 1; }
skip() { echo "[$(_ts)] SKIP  $*"; }

echo "=== RC2014 MIDI Synthesizer — E2E Test Setup ==="
echo ""

# ---------------------------------------------------------------------------
# Step 1: RomWBW ROM for MAME
# ---------------------------------------------------------------------------
info "Step 1: RomWBW ROM for MAME (rc2014zedp driver)"
info "  Version    : $ROMWBW_VERSION"
info "  ROM name   : $MAME_ROM_NAME"
info "  ROM dir    : $ROM_DIR"

ROM_DEST="$ROM_DIR/$MAME_ROM_NAME"

if [[ -f "$ROM_DEST" ]]; then
    skip "ROM already present: $ROM_DEST"
else
    # Check all MAME rompaths before downloading — it may be elsewhere.
    FOUND_ROM=""
    if command -v "$MAME_CMD" &>/dev/null; then
        ALL_ROMPATHS=$("$MAME_CMD" -showconfig 2>/dev/null | awk -F'[ \t]+' '/^rompath/{print $2}')
        IFS=';' read -ra ROMPATH_ENTRIES <<< "$ALL_ROMPATHS"
        for entry in "${ROMPATH_ENTRIES[@]}"; do
            entry="${entry/\$HOME/$HOME}"
            entry="${entry/\~/$HOME}"
            for subdir in rc2014zedp rc2014 rc2014_rom_ram_512k; do
                candidate="$entry/$subdir/$MAME_ROM_NAME"
                if [[ -f "$candidate" ]]; then
                    FOUND_ROM="$candidate"
                    break 2
                fi
            done
        done
    fi

    if [[ -n "$FOUND_ROM" ]]; then
        skip "ROM found elsewhere in MAME rompath: $FOUND_ROM"
        skip "Symlinking to expected location: $ROM_DEST"
        mkdir -p "$ROM_DIR"
        ln -sf "$FOUND_ROM" "$ROM_DEST"
    else
        info "  Downloading RomWBW $ROMWBW_VERSION package..."

        require_cmd() {
            command -v "$1" &>/dev/null || fail "'$1' not found — $2"
        }
        require_cmd curl  "install with: apt install curl"
        require_cmd unzip "install with: apt install unzip"

        TMPDIR_DL=$(mktemp -d)
        trap 'rm -rf "$TMPDIR_DL"' EXIT

        PKG_ZIP="$TMPDIR_DL/romwbw.zip"
        # Try both URL patterns (with and without 'v' prefix in the asset name).
        DOWNLOADED=false
        for url in "$ROMWBW_PKG_URL_V" "$ROMWBW_PKG_URL_PLAIN"; do
            info "  Trying: $url"
            if curl -fsSL --retry 3 --retry-delay 2 -o "$PKG_ZIP" "$url" 2>/dev/null; then
                DOWNLOADED=true
                break
            fi
        done
        if [[ "$DOWNLOADED" != true ]]; then
            fail "Download failed — check your internet connection or try a different ROMWBW_VERSION"
        fi

        # List zip contents for diagnosis, then find the ROM.
        ROM_PATH_IN_ZIP=$(unzip -Z1 "$PKG_ZIP" | grep -i "Binary/${ROM_IN_PKG}$" | head -1 || true)
        if [[ -z "$ROM_PATH_IN_ZIP" ]]; then
            # Fallback: search anywhere in the zip for the ROM filename.
            ROM_PATH_IN_ZIP=$(unzip -Z1 "$PKG_ZIP" | grep -i "/${ROM_IN_PKG}$" | head -1 || true)
        fi
        if [[ -z "$ROM_PATH_IN_ZIP" ]]; then
            echo "Contents of RomWBW package (showing .rom files):" >&2
            unzip -Z1 "$PKG_ZIP" | grep -i '\.rom$' >&2 || true
            fail "Could not find '$ROM_IN_PKG' inside the RomWBW package"
        fi

        info "  Extracting: $ROM_PATH_IN_ZIP"
        unzip -p "$PKG_ZIP" "$ROM_PATH_IN_ZIP" > "$TMPDIR_DL/$MAME_ROM_NAME"

        # Verify CRC32 if we have an expected value and crc32 is available.
        if [[ -n "$EXPECTED_CRC" ]] && command -v crc32 &>/dev/null; then
            ACTUAL_CRC=$(crc32 "$TMPDIR_DL/$MAME_ROM_NAME" 2>/dev/null || true)
            if [[ -n "$ACTUAL_CRC" && "${ACTUAL_CRC,,}" != "${EXPECTED_CRC,,}" ]]; then
                if [[ "$ROMWBW_VERSION" != "$MAME_BIOS_VERSION" ]]; then
                    info "  CRC32 mismatch (expected $EXPECTED_CRC, got $ACTUAL_CRC)"
                    info "  This is expected when ROMWBW_VERSION ($ROMWBW_VERSION) differs from MAME_BIOS_VERSION ($MAME_BIOS_VERSION)"
                    info "  MAME will warn about the CRC but the ROM still boots."
                else
                    fail "CRC32 mismatch for $MAME_ROM_NAME: expected $EXPECTED_CRC, got $ACTUAL_CRC"
                fi
            else
                info "  CRC32 OK: $ACTUAL_CRC"
            fi
        fi

        mkdir -p "$ROM_DIR"
        mv "$TMPDIR_DL/$MAME_ROM_NAME" "$ROM_DEST"
        pass "ROM installed: $ROM_DEST"

        # Also extract CP/M system tracks from the pre-built bootable
        # disk image.  These are needed to make cheese.img bootable in
        # the e2e tests (the cheese.img created by build_docker.sh only
        # has the data area, not the system tracks).
        SYSTRACKS_FILE="$ROM_DIR/hd512_cpm22_systracks.bin"
        if [[ ! -f "$SYSTRACKS_FILE" ]]; then
            HD512_IMG_IN_ZIP=$(unzip -Z1 "$PKG_ZIP" | grep -i "Binary/hd512_cpm22.img$" | head -1 || true)
            if [[ -n "$HD512_IMG_IN_ZIP" ]]; then
                info "  Extracting CP/M system tracks for bootable hard disk images…"
                # System tracks = first boottrk * sectrk * seclen = 32 * 8 * 512 = 131072 bytes
                unzip -p "$PKG_ZIP" "$HD512_IMG_IN_ZIP" | head -c 131072 > "$SYSTRACKS_FILE"
                SYSTRACKS_SIZE=$(wc -c < "$SYSTRACKS_FILE")
                if [[ "$SYSTRACKS_SIZE" -eq 131072 ]]; then
                    pass "CP/M system tracks extracted: $SYSTRACKS_FILE (${SYSTRACKS_SIZE} bytes)"
                else
                    info "WARNING: system tracks file unexpected size: ${SYSTRACKS_SIZE} (expected 131072)"
                fi
            else
                info "WARNING: Could not find hd512_cpm22.img in RomWBW package"
                info "         E2E tests will not be able to boot from the hard disk."
            fi
        fi
    fi
fi
echo ""

# ---------------------------------------------------------------------------
# Step 2: wbw_hd512 CP/M disk format definition for cpmtools
# ---------------------------------------------------------------------------
info "Step 2: wbw_hd512 disk format definition for cpmtools"

WBW_HD512_DEF='# RomWBW 512-byte-sector hard-disk image (used by rc2014zedp in MAME)
diskdef wbw_hd512
    seclen 512
    tracks 71
    sectrk 8
    blocksize 4096
    maxdir 128
    skew 0
    boottrk 32
    os 2.2
end'

# Check if the definition is already available.
diskdef_present() {
    # cpmtools searches: $CPMTOOLS_DISKDEFS, /etc/cpmtools/diskdefs, built-in path.
    for f in \
        "${CPMTOOLS_DISKDEFS:-}" \
        "$HOME/.cpmtools/diskdefs" \
        /etc/cpmtools/diskdefs \
        /usr/share/cpmtools/diskdefs \
        /usr/local/share/cpmtools/diskdefs
    do
        [[ -f "$f" ]] || continue
        grep -q "^diskdef wbw_hd512" "$f" && return 0
    done
    return 1
}

if diskdef_present; then
    skip "wbw_hd512 already defined in cpmtools diskdefs"
else
    CPMTOOLS_USER_DEFS="$HOME/.cpmtools/diskdefs"
    info "  Adding wbw_hd512 to $CPMTOOLS_USER_DEFS"
    mkdir -p "$HOME/.cpmtools"
    {
        echo ""
        echo "$WBW_HD512_DEF"
    } >> "$CPMTOOLS_USER_DEFS"
    pass "wbw_hd512 written to $CPMTOOLS_USER_DEFS"
    info "  NOTE: cpmtools reads ~/.cpmtools/diskdefs automatically."
    info "        If cpmls/cpmcp still can't find the format, run:"
    info "          export CPMTOOLS_DISKDEFS=$CPMTOOLS_USER_DEFS"
fi
echo ""

# ---------------------------------------------------------------------------
# Verification
# ---------------------------------------------------------------------------
info "Verifying setup..."

ERRORS=0

# Check ROM
if [[ -f "$ROM_DEST" ]]; then
    ROM_SIZE=$(wc -c < "$ROM_DEST")
    if [[ "$ROM_SIZE" -eq 524288 ]]; then
        pass "ROM present and correct size (${ROM_SIZE} bytes): $ROM_DEST"
    else
        info "WARNING: ROM exists but unexpected size: ${ROM_SIZE} bytes (expected 524288)"
        ERRORS=$(( ERRORS + 1 ))
    fi
else
    info "WARNING: ROM not found at $ROM_DEST"
    ERRORS=$(( ERRORS + 1 ))
fi

# Check diskdef is reachable by cpmtools
if command -v cpmls &>/dev/null; then
    # Test by trying to list a non-existent file in wbw_hd512 format; if the
    # format is unknown cpmls exits with "unknown format", otherwise it exits
    # with a filesystem error — both are non-zero, but the error text differs.
    if cpmls -f wbw_hd512 /dev/null 2>&1 | grep -qi "unknown format\|invalid format"; then
        info "WARNING: cpmtools does not recognise wbw_hd512 format"
        info "         Try: export CPMTOOLS_DISKDEFS=$HOME/.cpmtools/diskdefs"
        ERRORS=$(( ERRORS + 1 ))
    else
        pass "wbw_hd512 format recognised by cpmtools"
    fi
fi

echo ""
if [[ $ERRORS -eq 0 ]]; then
    echo "=== Setup complete. Run ./tests/e2e/run_e2e.sh to execute the tests. ==="
else
    echo "=== Setup completed with $ERRORS warning(s). Review the messages above. ===" >&2
    exit 1
fi
