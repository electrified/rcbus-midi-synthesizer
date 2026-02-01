#include "../../include/chip_manager.h"
#include "../../include/ym2149.h"
#include <stdint.h>

// Current chip pointer
sound_chip_interface_t* current_chip = 0;
uint8_t available_chips = 0;

// External chip interfaces
extern sound_chip_interface_t ym2149_interface;

// Initialize chip manager
void chip_manager_init(void) {
    current_chip = 0;
    available_chips = 0;
    
    // Detect available sound chips
    chip_manager_detect_chips();
    
    // Select default chip (YM2149 first if available)
    if (available_chips & CHIP_YM2149) {
        chip_manager_set_chip(CHIP_YM2149);
    }
}

// Detect available sound chips
void chip_manager_detect_chips(void) {
    available_chips = 0;
    
    // Test for YM2149
    if (detect_ym2149()) {
        available_chips |= CHIP_YM2149;
    }
    
    // Test for OPL3 (future implementation)
    if (detect_opl3()) {
        available_chips |= CHIP_OPL3;
    }
}

// Set active sound chip
uint8_t chip_manager_set_chip(uint8_t chip_id) {
    // Turn off current chip before switching
    if (current_chip && current_chip->all_off) {
        current_chip->all_off();
    }
    
    // Initialize and select new chip
    switch (chip_id) {
        case CHIP_YM2149:
            if (available_chips & CHIP_YM2149) {
                current_chip = &ym2149_interface;
                if (current_chip->init) {
                    current_chip->init();
                }
                return 1;  // Success
            }
            break;
            
        case CHIP_OPL3:
            // Future: Initialize OPL3 interface
            // current_chip = &opl3_interface;
            return 0;  // Not implemented yet
            // break;
            
        default:
            return 0;  // Invalid chip ID
    }
    
    return 0;  // Chip not available
}

// Get current chip interface
sound_chip_interface_t* chip_manager_get_current(void) {
    return current_chip;
}

// Test for YM2149 presence
uint8_t detect_ym2149(void) {
    // Simple detection: try to write to YM2149 registers
    // In a real implementation, we'd verify the chip responds
    
    // Test by writing to a register and reading back
    // For now, assume YM2149 is present at default address
    return 1;  // Assume present for now
}

// Test for OPL3 presence
uint8_t detect_opl3(void) {
    // Future: Implement OPL3 detection
    return 0;  // Not implemented yet
}