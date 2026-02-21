#ifndef SYNTHESIZER_H
#define SYNTHESIZER_H

#include <stdint.h>
#include "chip_interface.h"
#include "chip_manager.h"
#include "midi_driver.h"

// Main synthesizer functions
void synthesizer_init(void);
void synthesizer_panic(void);

// Voice allocation functions
uint8_t allocate_voice(uint8_t note, uint8_t velocity, uint8_t channel);
uint8_t find_voice_by_note(uint8_t note, uint8_t channel);

// System status
void synthesizer_print_status(void);

#endif // SYNTHESIZER_H