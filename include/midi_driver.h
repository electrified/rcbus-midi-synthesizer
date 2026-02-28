#ifndef MIDI_DRIVER_H
#define MIDI_DRIVER_H

#include <stdint.h>

// MIDI message status bytes
#define MIDI_NOTE_OFF        0x80
#define MIDI_NOTE_ON         0x90
#define MIDI_CONTROL_CHANGE   0xB0
#define MIDI_PROGRAM_CHANGE  0xC0
#define MIDI_PITCH_BEND      0xE0

// MIDI input mode
#define MIDI_MODE_NONE       0   // No MIDI input (default)
#define MIDI_MODE_BIOS       1   // BIOS serial (CP/M AUX device)
#define MIDI_MODE_KEYBOARD   2   // Console keyboard input

// MIDI status structure
typedef struct {
    uint8_t status;         // Current running status
    uint8_t channel;        // MIDI channel (0-15)
    uint8_t command;        // Command (note on/off, CC, etc.)
    uint8_t data1;          // First data byte
    uint8_t data2;          // Second data byte
    uint8_t expected_bytes;   // How many bytes expected for current message
    uint8_t byte_count;      // Bytes received so far
} midi_state_t;

// MIDI CC mapping for keyboard controls
typedef struct {
    uint8_t cc_number;       // CC number
    uint8_t value;          // Current value (0-127)
    uint8_t is_knob;        // TRUE for rotary knobs, FALSE for sliders
    const char* name;        // Human-readable name
} midi_cc_control_t;

// Function declarations
void midi_driver_init(void);
uint8_t midi_driver_available(void);
uint8_t midi_driver_read_byte(void);
void midi_driver_process_input(void);

// MIDI input mode control
void midi_set_mode(uint8_t mode);
uint8_t midi_get_mode(void);

// Keyboard MIDI mode
void midi_keyboard_process_key(char key);

// MIDI message processing
void midi_process_byte(uint8_t byte);
void midi_process_message(uint8_t status, uint8_t data1, uint8_t data2);

// External state
extern midi_state_t midi_state;
extern midi_cc_control_t midi_cc_controls[12];  // 8 knobs + 4 sliders

#endif // MIDI_DRIVER_H