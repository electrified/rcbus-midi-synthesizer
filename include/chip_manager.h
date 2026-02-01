#ifndef CHIP_MANAGER_H
#define CHIP_MANAGER_H

#include <stdint.h>
#include "chip_interface.h"

// Chip detection and management
void chip_manager_init(void);
void chip_manager_detect_chips(void);
uint8_t chip_manager_set_chip(uint8_t chip_id);
sound_chip_interface_t* chip_manager_get_current(void);

// Hardware detection functions
extern uint8_t detect_ym2149(void);  // Implemented in ym2149.c
uint8_t detect_opl3(void);           // Implemented here (future)

// Global status
extern uint8_t available_chips;      // Bitmask of detected chips

#endif // CHIP_MANAGER_H