#!/bin/bash
# Build script for RC2014 MIDI Synthesizer
# Works around z88dk configuration issues

echo "Building RC2014 MIDI Synthesizer..."

# Set paths
INCDIR="include"
SRCDIR="src"
OUTFILE="midisynth.com"

# Build command (direct compilation to workaround config issues)
zcc +cpm -vn -SO3 -O3 --opt-code-size -clib=sdcc_iy \
     -I$INCDIR \
     $SRCDIR/main.c \
     $SRCDIR/core/synthesizer.c \
     $SRCDIR/core/chip_manager.c \
     $SRCDIR/midi/midi_driver.c \
     $SRCDIR/chips/ym2149.c \
     -o $OUTFILE

if [ $? -eq 0 ]; then
    echo "Build successful: $OUTFILE"
    echo "Size: $(stat -c%s $OUTFILE)"
else
    echo "Build failed!"
    exit 1
fi