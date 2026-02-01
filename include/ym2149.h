#ifndef YM2149_H
#define YM2149_H

#include <stdint.h>
#include "chip_interface.h"

// YM2149 Register definitions
#define YM2149_ADDR_PORT     0x90    // Address register (based on existing OPL3 project)
#define YM2149_DATA_PORT     0x91    // Data register

// YM2149 Register addresses
#define YM2149_FREQ_A_LSB     0x00     // Channel A frequency low byte
#define YM2149_FREQ_A_MSB     0x01     // Channel A frequency high byte + enable
#define YM2149_FREQ_B_LSB     0x02     // Channel B frequency low byte
#define YM2149_FREQ_B_MSB     0x03     // Channel B frequency high byte + enable
#define YM2149_FREQ_C_LSB     0x04     // Channel C frequency low byte
#define YM2149_FREQ_C_MSB     0x05     // Channel C frequency high byte + enable
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

// Mixer control bits
#define YM2149_MIX_TONE_A    0x01     // Enable tone on channel A
#define YM2149_MIX_TONE_B    0x02     // Enable tone on channel B
#define YM2149_MIX_TONE_C    0x04     // Enable tone on channel C
#define YM2149_MIX_NOISE_A   0x08     // Enable noise on channel A
#define YM2149_MIX_NOISE_B   0x10     // Enable noise on channel B
#define YM2149_MIX_NOISE_C   0x20     // Enable noise on channel C

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

// YM2149-specific voice structure
typedef struct {
    uint8_t active;              // Voice is currently playing
    uint8_t midi_note;           // Current MIDI note
    uint8_t velocity;            // Current velocity
    uint8_t channel;             // MIDI channel
    uint8_t volume;              // Current volume (0-15)
    uint8_t envelope_shape;       // Current envelope shape
    uint16_t frequency;          // Current frequency value
    uint32_t start_time;         // Note start time
    uint8_t freq_reg_lsb;        // Frequency low byte register
    uint8_t freq_reg_msb;        // Frequency high byte register
    uint8_t level_reg;           // Level register
} ym2149_voice_t;

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

// External interface
extern sound_chip_interface_t ym2149_interface;
extern ym2149_voice_t ym2149_voices[3];  // 3 voices for YM2149

#endif // YM2149_H