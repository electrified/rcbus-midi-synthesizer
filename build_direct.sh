#!/bin/bash
# Build using direct compilation (no config file needed)

echo "Building RC2014 MIDI Synthesizer (direct method)..."

# Direct compilation approach - like your existing opl2.asm
zcc -mz80 -vn -SO3 -O3 --opt-code-size -clib=sdcc_iy -Iinclude \
    src/main.c \
    src/core/synthesizer.c \
    src/core/chip_manager.c \
    src/midi/midi_driver.c \
    src/chips/ym2149.c \
    -create-app -o midisynth.com

if [ $? -eq 0 ]; then
    echo "SUCCESS: Built midisynth.com"
    ls -la midisynth.com
else
    echo "BUILD FAILED"
    exit 1
fi