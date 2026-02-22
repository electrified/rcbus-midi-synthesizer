#include "../../include/synthesizer.h"
#include "../../include/midi_driver.h"
#include "../../include/chip_manager.h"
#include <stdio.h>

// Simple voice allocation for current chip
uint8_t allocate_voice(uint8_t note, uint8_t velocity, uint8_t channel) {
    // Suppress unused parameter warnings
    (void)note;
    (void)velocity;
    (void)channel;
    if (!current_chip) return 0xFF;  // No chip selected
    
    // Find free voice
    for (uint8_t i = 0; i < current_chip->voice_count; i++) {
        if (!current_chip->voices[i].active) {
            return i;
        }
    }
    
    // No free voices, use voice stealing (oldest note)
    if (current_chip->voice_count == 0) return 0xFF;

    uint8_t oldest_voice = 0;
    uint32_t oldest_time = current_chip->voices[0].start_time;
    
    for (uint8_t i = 1; i < current_chip->voice_count; i++) {
        if (current_chip->voices[i].start_time < oldest_time) {
            oldest_time = current_chip->voices[i].start_time;
            oldest_voice = i;
        }
    }
    
    return oldest_voice;  // Steal oldest voice
}

uint8_t find_voice_by_note(uint8_t note, uint8_t channel) {
    if (!current_chip) return 0xFF;
    
    for (uint8_t i = 0; i < current_chip->voice_count; i++) {
        if (current_chip->voices[i].active &&
            current_chip->voices[i].midi_note == note &&
            current_chip->voices[i].channel == channel) {
            return i;
        }
    }
    
    return 0xFF;  // Not found
}

// Initialize synthesizer system
void synthesizer_init(void) {
    printf("Initializing RC2014 MIDI Synthesizer...\n");
    
    // Initialize chip manager
    chip_manager_init();
    
    // Initialize MIDI driver
    midi_driver_init();
    
    // Print status
    synthesizer_print_status();
    
    printf("Synthesizer ready. MIDI interface active.\n");
}

// Emergency panic function
void synthesizer_panic(void) {
    if (current_chip && current_chip->panic) {
        current_chip->panic();
    }
    
    printf("SYNTHESIZER PANIC: All notes off!\n");
}

// Print system status
void synthesizer_print_status(void) {
    printf("=== RC2014 MIDI Synthesizer Status ===\n");
    
    // Show detected hardware
    printf("Hardware Detection:\n");
    if (available_chips & CHIP_YM2149) {
        printf("  ✓ YM2149 PSG detected\n");
    } else {
        printf("  ✗ YM2149 PSG not detected\n");
    }
    if (available_chips & CHIP_OPL3) {
        printf("  ✓ OPL3 FM detected\n");
    } else {
        printf("  ✗ OPL3 FM not detected\n");
    }
    printf("\n");
    
    if (current_chip) {
        printf("Active Chip: %s\n", current_chip->name);
        printf("Voice Count: %d\n", current_chip->voice_count);
        
        printf("Active Voices:\n");
        uint8_t active_count = 0;
        for (uint8_t i = 0; i < current_chip->voice_count; i++) {
            if (current_chip->voices[i].active) {
                printf("  Voice %d: Note %d, Vel %d, Ch %d\n",
                       i, current_chip->voices[i].midi_note,
                       current_chip->voices[i].velocity,
                       current_chip->voices[i].channel);
                active_count++;
            }
        }
        if (active_count == 0) {
            printf("  (No active voices)\n");
        }
    } else {
        printf("No sound chip selected!\n");
    }
    
    printf("Available CC Controls:\n");
    for (uint8_t i = 0; i < 12; i++) {
        printf("  CC#%d (%s): %d\n",
               midi_cc_controls[i].cc_number,
               midi_cc_controls[i].name,
               midi_cc_controls[i].value);
    }
    printf("===================================\n");
}