# Makefile for RC2014 MIDI Synthesizer

# Compiler and flags
CC = zcc
CFLAGS = +cpm -v -SO3 -O3 --opt-code-size
LDFLAGS = -create-app

# Directories and files
INCDIR = include
SOURCES = src/main.c src/core/synthesizer.c src/core/chip_manager.c src/midi/midi_driver.c src/chips/ym2149.c
OUTPUT = midisynth
COM_FILE = MIDISYNTH.COM

# Disk image settings
HD_IMAGE ?= cheese.img
BLANK_HD_IMAGE = /opt/mame-roms/rc2014zedp/hd512_blank.img
HD_DEST ?= 0:midisyn.com

# Standard build
all: $(COM_FILE)

$(COM_FILE): $(SOURCES)
	@if command -v $(CC) >/dev/null 2>&1; then \
		$(CC) $(CFLAGS) -I$(INCDIR) $(SOURCES) $(LDFLAGS) -o $(OUTPUT); \
	elif [ -f "$(COM_FILE)" ]; then \
		echo "zcc not found, but $(COM_FILE) exists — skipping compilation"; \
	else \
		echo "Error: zcc (z88dk) not found and $(COM_FILE) missing — cannot build"; \
		exit 1; \
	fi

# Disk image targets
# We use a conditional to avoid an empty target if HD_IMAGE is not set
ifneq ($(HD_IMAGE),)
$(HD_IMAGE):
	@if [ -f "$(BLANK_HD_IMAGE)" ]; then \
		echo "Creating disk image from RomWBW blank: $(HD_IMAGE)"; \
		cp "$(BLANK_HD_IMAGE)" "$(HD_IMAGE)"; \
	else \
		echo "Creating blank wbw_hd512 disk image: $(HD_IMAGE)"; \
		dd if=/dev/zero bs=512 count=16640 2>/dev/null | tr '\000' '\345' > "$(HD_IMAGE)"; \
		mkfs.cpm -f wbw_hd512 "$(HD_IMAGE)"; \
	fi
endif

image: $(COM_FILE) $(HD_IMAGE)
	@if [ -z "$(HD_IMAGE)" ]; then \
		echo "No disk image specified (HD_IMAGE), skipping image copy"; \
	elif command -v cpmcp >/dev/null 2>&1; then \
		echo "Copying $(COM_FILE) to $(HD_IMAGE) as $(HD_DEST)..."; \
		cpmrm -f wbw_hd512 "$(HD_IMAGE)" "$(HD_DEST)" 2>/dev/null || true; \
		cpmcp -f wbw_hd512 "$(HD_IMAGE)" $(COM_FILE) "$(HD_DEST)"; \
	else \
		echo "cpmtools not found, skipping image copy"; \
	fi

clean:
	rm -f *.com *.COM *.bin *.lst *.ihx *.hex *.map *.dsk

test:
	@echo "Testing build..."
	$(MAKE) all
	@echo "Build complete. Run: zxcc $(COM_FILE)"

.PHONY: all clean test image
