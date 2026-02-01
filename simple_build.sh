#!/bin/bash
# Simple build command that works with current z88dk
echo "Building RC2014 MIDI Synthesizer..."

# Try a simple build without target specification first
zcc -vn -SO3 -O3 --opt-code-size -clib=sdcc_iy \
     -Iinclude \
     src/main.c src/core/synthesizer.c src/core/chip_manager.c src/midi/midi_driver.c src/chips/ym2149.c \
     -create-app -o midisynth.com

if [ $? -eq 0 ]; then
    echo "Build successful! Created midisynth.com"
    ls -la midisynth.com
else
    echo "Build failed with error code $?"
fi