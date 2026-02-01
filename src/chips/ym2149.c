#include "../../include/ym2149.h"
#include <stdint.h>
#include <string.h>

// Global voice array and interface declaration
ym2149_voice_t ym2149_voices[3];
sound_chip_interface_t ym2149_interface;

// Small delay function (from your existing code)
static void SmallDelay(void) {
    uint8_t i;
    for (i = 0; i < 10; i++) {
        // Simple delay loop
    }
}

// Low-level register write function
void ym2149_write_register(uint8_t reg, uint8_t data) {
    // Write address register first
    *((volatile uint8_t*)YM2149_ADDR_PORT) = reg;
    SmallDelay();
    
    // Then write data register
    *((volatile uint8_t*)YM2149_DATA_PORT) = data;
    SmallDelay();
}

// Initialize YM2149 chip
void ym2149_init(void) {
    // Clear all voices
    memset(ym2149_voices, 0, sizeof(ym2149_voices));
    
    // Initialize to known state
    ym2149_reset();
    
    // Set up default mixer (enable tone on all channels)
    ym2149_write_register(YM2149_MIXER, YM2149_MIX_TONE_A | YM2149_MIX_TONE_B | YM2149_MIX_TONE_C);
    
    // Set default envelope shapes for each channel
    ym2149_write_register(YM2149_LEVEL_A, YM2149_VOLUME_FIXED | 0x0F);  // Max volume
    ym2149_write_register(YM2149_LEVEL_B, YM2149_VOLUME_FIXED | 0x0F);  // Max volume
    ym2149_write_register(YM2149_LEVEL_C, YM2149_VOLUME_FIXED | 0x0F);  // Max volume
    
    // Set noise generator to reasonable default
    ym2149_write_register(YM2149_FREQ_NOISE, 0x1F);  // Middle frequency
}

// Reset YM2149 to silence
void ym2149_reset(void) {
    ym2149_all_off();
}

// Turn off all voices
void ym2149_all_off(void) {
    for (uint8_t i = 0; i < 3; i++) {
        ym2149_note_off(i);
    }
}

// Note on function
void ym2149_note_on(uint8_t voice, uint8_t note, uint8_t velocity, uint8_t channel) {
    if (voice >= 3) return;  // YM2149 only has 3 voices
    
    ym2149_voice_t* v = &ym2149_voices[voice];
    
    // Store note information
    v->active = 1;
    v->midi_note = note;
    v->velocity = velocity;
    v->channel = channel;
    v->start_time = 0;  // Could implement timer if needed
    
    // Convert MIDI note to YM2149 frequency
    v->frequency = ym2149_note_to_freq(note);
    
    // Set frequency (low and high bytes)
    ym2149_set_frequency(voice, v->frequency);
    
    // Set volume based on velocity (0-127 → 0-15)
    v->volume = (velocity * 15) / 127;
    ym2149_set_volume(voice, v->volume);
}

// Note off function
void ym2149_note_off(uint8_t voice) {
    if (voice >= 3) return;
    
    ym2149_voice_t* v = &ym2149_voices[voice];
    v->active = 0;
    
    // Disable the voice by clearing the MSB of frequency register
    uint8_t reg_msb = YM2149_FREQ_A_MSB + (voice * 2);
    uint8_t current_freq;
    
    // Read current frequency (if we had a read function, for now just write with MSB cleared)
    ym2149_write_register(reg_msb, 0x00);  // Clear MSB to disable voice
}

// Set voice volume
void ym2149_set_volume(uint8_t voice, uint8_t volume) {
    if (voice >= 3) return;
    
    ym2149_voice_t* v = &ym2149_voices[voice];
    v->volume = volume;
    
    // Clamp volume to 0-15
    if (volume > 15) volume = 15;
    
    // Get current register value and preserve envelope mode
    uint8_t level_reg = YM2149_LEVEL_A + voice;
    uint8_t current_val = v->envelope_shape;  // Store current envelope setting
    ym2149_write_register(level_reg, current_val | volume);
}

// Set attack time (map to envelope frequency)
void ym2149_set_attack(uint8_t voice, uint8_t attack) {
    if (voice >= 3) return;
    
    ym2149_voice_t* v = &ym2149_voices[voice];
    
    // Map CC value (0-127) to envelope frequency
    uint16_t env_freq = (attack * 255) / 127;
    
    // Set envelope frequency registers
    ym2149_write_register(YM2149_FREQ_ENV_LSB, env_freq & 0xFF);
    ym2149_write_register(YM2149_FREQ_ENV_MSB, (env_freq >> 8) & 0xFF);
    
    // Switch to envelope mode if not already
    uint8_t level_reg = YM2149_LEVEL_A + voice;
    ym2149_write_register(level_reg, YM2149_VOLUME_ENV | v->volume);
}

// Set decay time (part of envelope shaping)
void ym2149_set_decay(uint8_t voice, uint8_t decay) {
    if (voice >= 3) return;
    
    // Map to envelope shape with decay
    uint8_t envelope_shape = YM2149_ENV_TRIANGLE;
    if (decay > 64) {
        envelope_shape = YM2149_ENV_TRIANGLE_DECAY;
    }
    
    ym2149_voices[voice].envelope_shape = envelope_shape;
    ym2149_write_register(YM2149_SHAPE_ENV, envelope_shape);
}

// Set sustain level
void ym2149_set_sustain(uint8_t voice, uint8_t sustain) {
    if (voice >= 3) return;
    
    // Map sustain to volume level (0-127 → 0-15)
    uint8_t vol = (sustain * 15) / 127;
    ym2149_set_volume(voice, vol);
}

// Set release time
void ym2149_set_release(uint8_t voice, uint8_t release) {
    if (voice >= 3) return;
    
    // Map release to envelope decay rate
    uint16_t env_freq = (release * 255) / 127;
    ym2149_write_register(YM2149_FREQ_ENV_LSB, env_freq & 0xFF);
    ym2149_write_register(YM2149_FREQ_ENV_MSB, (env_freq >> 8) & 0xFF);
}

// Set vibrato depth (global effect)
void ym2149_set_vibrato(uint8_t depth) {
    // YM2149 doesn't have hardware vibrato
    // Could implement via frequency modulation in software if needed
}

// Set tremolo rate (global effect)
void ym2149_set_tremolo(uint8_t rate) {
    // YM2149 doesn't have hardware tremolo
    // Could implement via volume modulation if needed
}

// Set pitch bend
void ym2149_set_pitch_bend(int16_t bend) {
    // Apply pitch bend to all active voices
    for (uint8_t i = 0; i < 3; i++) {
        if (ym2149_voices[i].active) {
            uint16_t base_freq = ym2149_note_to_freq(ym2149_voices[i].midi_note);
            uint16_t bent_freq = ym2149_apply_pitch_bend(base_freq, bend);
            ym2149_set_frequency(i, bent_freq);
        }
    }
}

// Set modulation depth
void ym2149_set_modulation(uint8_t depth) {
    // Could implement as vibrato or tremolo effect
    ym2149_set_vibrato(depth);
}

// Set preset
void ym2149_set_preset(uint8_t preset) {
    // Define some basic presets
    switch(preset) {
        case 0:  // Simple square wave
            ym2149_write_register(YM2149_SHAPE_ENV, YM2149_ENV_OFF);
            break;
        case 1:  // Sawtooth
            ym2149_write_register(YM2149_SHAPE_ENV, YM2149_ENV_SAWTOOTH);
            break;
        case 2:  // Triangle
            ym2149_write_register(YM2149_SHAPE_ENV, YM2149_ENV_TRIANGLE);
            break;
        case 3:  // Pulse with decay
            ym2149_write_register(YM2149_SHAPE_ENV, YM2149_ENV_PULSE_DECAY);
            break;
    }
}

// Emergency panic - silence everything
void ym2149_panic(void) {
    ym2149_all_off();
    ym2149_write_register(YM2149_MIXER, 0x00);  // Disable all outputs
}

// Set frequency for a voice
void ym2149_set_frequency(uint8_t voice, uint16_t freq) {
    if (voice >= 3) return;
    
    uint8_t freq_lsb = YM2149_FREQ_A_LSB + (voice * 2);
    uint8_t freq_msb = YM2149_FREQ_A_MSB + (voice * 2);
    
    ym2149_write_register(freq_lsb, freq & 0xFF);
    ym2149_write_register(freq_msb, (freq >> 8) | 0x01);  // Set MSB to enable voice
}

// MIDI note to frequency conversion (simplified)
uint16_t ym2149_note_to_freq(uint8_t note) {
    // Basic frequency lookup table (can be expanded)
    static const uint16_t note_freq[] = {
        0x000, 0x006, 0x00C, 0x013, 0x019, 0x022, 0x02A, 0x033,
        0x03D, 0x048, 0x054, 0x061, 0x070, 0x080, 0x091, 0x0A4,
        0x0B8, 0x0CE, 0x0E5, 0x0FE, 0x119, 0x136, 0x156, 0x178,
        0x19D, 0x1C4, 0x1EF, 0x21D, 0x24F, 0x284, 0x2BD, 0x2FA, 0x33B,
        0x381, 0x3CC, 0x41C, 0x472, 0x4CE, 0x530, 0x59A, 0x60C,
        0x687, 0x70B, 0x79A, 0x835, 0x8DA, 0x98D, 0xA51, 0xB24,
        0xC06, 0xCF9, 0xE00, 0xF15
    };
    
    if (note < sizeof(note_freq)) {
        return note_freq[note];
    }
    return 0;
}

// Apply pitch bend to frequency
uint16_t ym2149_apply_pitch_bend(uint16_t base_freq, int16_t bend) {
    // Simple linear pitch bend (can be improved)
    // bend range: -8192 to +8192, map to -semitone to +semitone
    int16_t bend_amount = bend / 8;  // Simplified calculation
    
    if (bend_amount >= 0) {
        return base_freq + (base_freq * bend_amount) / 100;
    } else {
        return base_freq - (base_freq * (-bend_amount)) / 100;
    }
}

// Initialize YM2149 interface structure
sound_chip_interface_t ym2149_interface = {
    .chip_id = CHIP_YM2149,
    .voice_count = 3,
    .name = "YM2149 PSG",
    
    .init = ym2149_init,
    .reset = ym2149_reset,
    .all_off = ym2149_all_off,
    
    .note_on = ym2149_note_on,
    .note_off = ym2149_note_off,
    
    .set_volume = ym2149_set_volume,
    .set_attack = ym2149_set_attack,
    .set_decay = ym2149_set_decay,
    .set_sustain = ym2149_set_sustain,
    .set_release = ym2149_set_release,
    .set_vibrato = ym2149_set_vibrato,
    .set_tremolo = ym2149_set_tremolo,
    .set_pitch_bend = ym2149_set_pitch_bend,
    .set_modulation = ym2149_set_modulation,
    
    .set_preset = ym2149_set_preset,
    .panic = ym2149_panic,
    
    .voices = (voice_t*)ym2149_voices
};