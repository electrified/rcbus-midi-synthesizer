#ifndef CHIP_INTERFACE_H
#define CHIP_INTERFACE_H

#include <stdint.h>

// Chip type identifiers
#define CHIP_NONE     0
#define CHIP_YM2149   1
#define CHIP_OPL3      2

// Voice state structure
typedef struct {
    uint8_t active;        // Voice is currently playing
    uint8_t midi_note;     // Current MIDI note (0-127)
    uint8_t velocity;      // Current velocity (0-127)
    uint8_t channel;       // MIDI channel (0-15)
    uint32_t start_time;    // Note start time for envelope tracking
} voice_t;

// Abstract sound chip interface
typedef struct {
    uint8_t chip_id;       // CHIP_YM2149, CHIP_OPL3, etc.
    uint8_t voice_count;    // Number of voices available
    const char* name;        // Human-readable chip name
    
    // Core synthesis functions
    void (*init)(void);
    void (*reset)(void);
    void (*all_off)(void);
    
    // Voice control functions
    void (*note_on)(uint8_t voice, uint8_t note, uint8_t velocity, uint8_t channel);
    void (*note_off)(uint8_t voice);
    
    // Parameter control functions (CC mapping)
    void (*set_volume)(uint8_t voice, uint8_t volume);        // CC 1-4
    void (*set_attack)(uint8_t voice, uint8_t attack);        // CC 5
    void (*set_decay)(uint8_t voice, uint8_t decay);          // CC 6
    void (*set_sustain)(uint8_t voice, uint8_t sustain);      // CC 7
    void (*set_release)(uint8_t voice, uint8_t release);      // CC 8
    void (*set_vibrato)(uint8_t depth);                       // CC 9
    void (*set_tremolo)(uint8_t rate);                         // CC 10
    void (*set_pitch_bend)(int16_t bend);                       // CC 11
    void (*set_modulation)(uint8_t depth);                      // CC 12
    
    // Chip-specific functions
    void (*set_preset)(uint8_t preset);
    void (*panic)(void);        // Emergency silence all notes
    
    // Voice state management
    voice_t* voices;          // Pointer to voice array
} sound_chip_interface_t;

// Global chip declarations
extern sound_chip_interface_t* current_chip;

#endif // CHIP_INTERFACE_H