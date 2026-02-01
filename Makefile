# Simple Makefile for RC2014 MIDI Synthesizer
CC = zcc
CFLAGS = +cpm -subtype=default -vn -SO3 -O3 --opt-code-size -clib=sdcc_iy
LDFLAGS = -create-app

# Directories
INCDIR = include

# Simple build
all:
	$(CC) $(CFLAGS) -I$(INCDIR) src/main.c src/core/synthesizer.c src/core/chip_manager.c src/midi/midi_driver.c src/chips/ym2149.c -o midisynth.com

clean:
	rm -f *.com *.bin *.lst *.ihx *.hex *.map

test:
	@echo "Testing build..."
	make all
	@echo "Build complete. Run: zxcc midisynth.com"

.PHONY: all clean test