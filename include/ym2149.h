#ifndef YM2149_H
#define YM2149_H

#include <stdint.h>
#include "chip_interface.h"
#include "port_config.h"

// YM2149 Register definitions
#define YM2149_ADDR_PORT     ym2149_ports.addr_port    // Address register (configurable)
#define YM2149_DATA_PORT     ym2149_ports.data_port    // Data register (configurable)

// YM2149 Register addresses
#define YM2149_FREQ_A_LSB     0x00     // Channel A frequency low byte
#define YM2149_FREQ_A_MSB     0x01     // Channel A frequency high byte (4 bits)
#define YM2149_FREQ_B_LSB     0x02     // Channel B frequency low byte
#define YM2149_FREQ_B_MSB     0x03     // Channel B frequency high byte (4 bits)
#define YM2149_FREQ_C_LSB     0x04     // Channel C frequency low byte
#define YM2149_FREQ_C_MSB     0x05     // Channel C frequency high byte (4 bits)
#define YM2149_FREQ_NOISE    0x06     // Noise generator frequency
#define YM2149_MIXER         0x07     // Tone/noise enable per channel
#define YM2149_LEVEL_A       0x08     // Channel A volume & envelope mode
#define YM2149_LEVEL_B       0x09     // Channel B volume & envelope mode
#define YM2149_LEVEL_C       0x0A     // Channel C volume & envelope mode
#define YM2149_FREQ_ENV_LSB  0x0B     // Envelope frequency low byte
#define YM2149_FREQ_ENV_MSB  0x0C     // Envelope frequency high byte
#define YM2149_SHAPE_ENV     0x0D     // Envelope shape
#define YM2149_IO_A         0x0E     // Port A I/O data
#define YM2149_IO_B         0x0F     // Port B I/O data

// Mixer control bits (active-low: 0=enable, 1=disable)
#define YM2149_MIX_TONE_A_OFF   0x01  // Disable tone on channel A
#define YM2149_MIX_TONE_B_OFF   0x02  // Disable tone on channel B
#define YM2149_MIX_TONE_C_OFF   0x04  // Disable tone on channel C
#define YM2149_MIX_NOISE_A_OFF  0x08  // Disable noise on channel A
#define YM2149_MIX_NOISE_B_OFF  0x10  // Disable noise on channel B
#define YM2149_MIX_NOISE_C_OFF  0x20  // Disable noise on channel C

// Common mixer presets
#define YM2149_MIX_ALL_TONE     0x38  // Enable all tones, disable all noise
#define YM2149_MIX_ALL_OFF      0x3F  // Disable everything

// Volume/envelope modes
#define YM2149_VOLUME_FIXED    0x00     // Fixed volume mode
#define YM2149_VOLUME_ENV      0x10     // Envelope controlled volume

// Envelope shapes
#define YM2149_ENV_OFF        0x00     // No envelope (constant level)
#define YM2149_ENV_DECAY      0x01     // \_______ (decay)
#define YM2149_ENV_TRIANGLE   0x02     // /\\____ (triangle)
#define YM2149_ENV_SAWTOOTH   0x03     // /|_____ (sawtooth)
#define YM2149_ENV_PULSE      0x04     // __|____ (pulse)
#define YM2149_ENV_SAW_DECAY  0x05     // /\\____ (saw + decay)
#define YM2149_ENV_TRIANGLE_DECAY 0x06   // /\\____ (triangle + decay)
#define YM2149_ENV_PULSE_DECAY 0x07     // __|____ (pulse + decay)

// YM2149 chip-specific voice extras (separate from base voice_t)
typedef struct {
    uint8_t volume;              // Current volume (0-15)
    uint8_t envelope_enabled;    // Envelope mode active
    uint8_t envelope_shape;      // Current envelope shape
    uint16_t frequency;          // Current frequency value
} ym2149_voice_extra_t;

// Frequency table range
#define YM2149_MIDI_NOTE_MIN  24   // C1
#define YM2149_MIDI_NOTE_MAX  96   // C7

// Function declarations
void ym2149_init(void);
void ym2149_reset(void);
void ym2149_all_off(void);

// Voice control
void ym2149_note_on(uint8_t voice, uint8_t note, uint8_t velocity, uint8_t channel);
void ym2149_note_off(uint8_t voice);

// Parameter control (CC mapping)
void ym2149_set_volume(uint8_t voice, uint8_t volume);
void ym2149_set_attack(uint8_t voice, uint8_t attack);
void ym2149_set_decay(uint8_t voice, uint8_t decay);
void ym2149_set_sustain(uint8_t voice, uint8_t sustain);
void ym2149_set_release(uint8_t voice, uint8_t release);
void ym2149_set_vibrato(uint8_t depth);
void ym2149_set_tremolo(uint8_t rate);
void ym2149_set_pitch_bend(int16_t bend);
void ym2149_set_modulation(uint8_t depth);

// Chip-specific
void ym2149_set_preset(uint8_t preset);
void ym2149_panic(void);

// Low-level register access
void ym2149_write_register(uint8_t reg, uint8_t data);
void ym2149_set_frequency(uint8_t voice, uint16_t freq);

// Frequency conversion
uint16_t ym2149_note_to_freq(uint8_t note);
uint16_t ym2149_apply_pitch_bend(uint16_t base_freq, int16_t bend);

// Chip detection
uint8_t detect_ym2149(void);

// Utility
void delay_ms(uint16_t ms);

// Test functions
void ym2149_play_test_sequence(void);
void ym2149_play_arpeggio(void);
void ym2149_play_scale(void);

// External interface
extern sound_chip_interface_t ym2149_interface;
extern voice_t ym2149_voices[3];               // Base voice state (used via chip_interface)
extern ym2149_voice_extra_t ym2149_voice_extra[3];  // Chip-specific extras

#endif // YM2149_H