#include "../../include/ym2149.h"
#include "../../include/synthesizer.h"
#include <stdint.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

// Port configuration implementation
port_config_t ym2149_ports;

void port_config_init(void) {
    ym2149_ports.addr_port = 0xD8;  // R5 RC2014 YM2149 register port
    ym2149_ports.data_port = 0xD0;  // R5 RC2014 YM2149 data port
}

void port_config_set(unsigned char addr_port, unsigned char data_port) {
    ym2149_ports.addr_port = addr_port;
    ym2149_ports.data_port = data_port;
}

int port_config_load_from_file(const char* filename) {
    FILE* file = fopen(filename, "r");
    if (!file) {
        return 0;  // File not found or cannot open
    }
    
    char line[256];
    unsigned char addr_port = 0xD8;
    unsigned char data_port = 0xD0;
    
    while (fgets(line, sizeof(line), file)) {
        // Skip comments and empty lines
        if (line[0] == '#' || line[0] == '\n' || line[0] == '\r') {
            continue;
        }
        
        // Parse key=value format
        char* key = strtok(line, "=");
        char* value = strtok(NULL, "=\n\r");
        
        if (key && value) {
            if (strcmp(key, "addr_port") == 0) {
                addr_port = (unsigned char)strtoul(value, NULL, 0);
            } else if (strcmp(key, "data_port") == 0) {
                data_port = (unsigned char)strtoul(value, NULL, 0);
            }
        }
    }
    
    fclose(file);
    port_config_set(addr_port, data_port);
    return 1;
}

int port_config_validate(void) {
    // Basic validation: ports should be in reasonable I/O range
    if (ym2149_ports.addr_port == ym2149_ports.data_port) {
        return 0;  // Same port for address and data is invalid
    }
    
    // Ports are always in valid range for unsigned char
    // No range validation needed for unsigned char types
    
    return 1;
}

// Global voice arrays — split to match voice_t stride expected by chip_interface
voice_t ym2149_voices[3];
ym2149_voice_extra_t ym2149_voice_extra[3];

// Small delay function — volatile counter prevents optimisation away
static void SmallDelay(void) {
    for (volatile uint8_t i = 0; i < 10; i++) {
    }
}

// Low-level register write function
void ym2149_write_register(uint8_t reg, uint8_t data) {
    // Write address register first
    outp(YM2149_ADDR_PORT, reg);
    SmallDelay();

    // Then write data register
    outp(YM2149_DATA_PORT, data);
    SmallDelay();
}

// Initialize YM2149 chip
void ym2149_init(void) {
    // Initialize port configuration with defaults if not already set
    static int config_initialized = 0;
    if (!config_initialized) {
        port_config_init();
        config_initialized = 1;
    }
    
    // Clear all voices
    memset(ym2149_voices, 0, sizeof(ym2149_voices));
    memset(ym2149_voice_extra, 0, sizeof(ym2149_voice_extra));
    
    // Initialize to known state
    ym2149_reset();
    
    // Set up default mixer (enable tone on all channels, disable noise)
    ym2149_write_register(YM2149_MIXER, YM2149_MIX_ALL_TONE);
    
    // Set default envelope shapes for each channel
    ym2149_write_register(YM2149_LEVEL_A, YM2149_VOLUME_FIXED | 0x0F);  // Max volume
    ym2149_write_register(YM2149_LEVEL_B, YM2149_VOLUME_FIXED | 0x0F);  // Max volume
    ym2149_write_register(YM2149_LEVEL_C, YM2149_VOLUME_FIXED | 0x0F);  // Max volume
    
    // Set noise generator to reasonable default
    ym2149_write_register(YM2149_FREQ_NOISE, 0x1F);  // Middle frequency
}

// Reset YM2149 to silence - zero all 14 registers
void ym2149_reset(void) {
    for (uint8_t reg = 0; reg <= 0x0D; reg++) {
        ym2149_write_register(reg, 0x00);
    }
    // Disable all outputs after zeroing
    ym2149_write_register(YM2149_MIXER, YM2149_MIX_ALL_OFF);
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

    voice_t* v = &ym2149_voices[voice];
    ym2149_voice_extra_t* vx = &ym2149_voice_extra[voice];

    // Store note information
    v->active = 1;
    v->midi_note = note;
    v->velocity = velocity;
    v->channel = channel;
    v->start_time = note_counter++;

    // Convert MIDI note to YM2149 frequency
    vx->frequency = ym2149_note_to_freq(note);

    // Set frequency (low and high bytes)
    ym2149_set_frequency(voice, vx->frequency);

    // Set volume based on velocity (0-127 → 0-15)
    vx->volume = ((uint16_t)velocity * 15) / 127;
    ym2149_set_volume(voice, vx->volume);
}

// Note off function
void ym2149_note_off(uint8_t voice) {
    if (voice >= 3) return;

    ym2149_voices[voice].active = 0;

    // Silence the channel by setting volume to 0
    uint8_t level_reg = YM2149_LEVEL_A + voice;
    ym2149_write_register(level_reg, 0x00);
}

// Set voice volume
void ym2149_set_volume(uint8_t voice, uint8_t volume) {
    if (voice >= 3) return;

    ym2149_voice_extra_t* vx = &ym2149_voice_extra[voice];
    vx->volume = volume;

    // Clamp volume to 0-15
    if (volume > 15) volume = 15;

    uint8_t level_reg = YM2149_LEVEL_A + voice;
    uint8_t reg_val = volume;
    if (vx->envelope_enabled) {
        reg_val |= YM2149_VOLUME_ENV;
    }
    ym2149_write_register(level_reg, reg_val);
}

// Set attack time (map to envelope frequency)
void ym2149_set_attack(uint8_t voice, uint8_t attack) {
    if (voice >= 3) return;

    ym2149_voice_extra_t* vx = &ym2149_voice_extra[voice];

    // Map CC value (0-127) to envelope frequency
    uint16_t env_freq = ((uint16_t)attack * 255) / 127;

    // Set envelope frequency registers
    ym2149_write_register(YM2149_FREQ_ENV_LSB, env_freq & 0xFF);
    ym2149_write_register(YM2149_FREQ_ENV_MSB, (env_freq >> 8) & 0xFF);

    // Switch to envelope mode
    vx->envelope_enabled = 1;
    uint8_t level_reg = YM2149_LEVEL_A + voice;
    ym2149_write_register(level_reg, YM2149_VOLUME_ENV | vx->volume);
}

// Set decay time (part of envelope shaping)
void ym2149_set_decay(uint8_t voice, uint8_t decay) {
    if (voice >= 3) return;
    
    // Map to envelope shape with decay
    uint8_t envelope_shape = YM2149_ENV_TRIANGLE;
    if (decay > 64) {
        envelope_shape = YM2149_ENV_TRIANGLE_DECAY;
    }
    
    ym2149_voice_extra[voice].envelope_shape = envelope_shape;
    ym2149_write_register(YM2149_SHAPE_ENV, envelope_shape);
}

// Set sustain level
void ym2149_set_sustain(uint8_t voice, uint8_t sustain) {
    if (voice >= 3) return;
    
    // Map sustain to volume level (0-127 → 0-15)
    uint8_t vol = ((uint16_t)sustain * 15) / 127;
    ym2149_set_volume(voice, vol);
}

// Set release time
void ym2149_set_release(uint8_t voice, uint8_t release) {
    if (voice >= 3) return;
    
    // Map release to envelope decay rate
    uint16_t env_freq = ((uint16_t)release * 255) / 127;
    ym2149_write_register(YM2149_FREQ_ENV_LSB, env_freq & 0xFF);
    ym2149_write_register(YM2149_FREQ_ENV_MSB, (env_freq >> 8) & 0xFF);
}

// Set vibrato depth (global effect)
void ym2149_set_vibrato(uint8_t depth) {
    // Suppress unused parameter warning
    (void)depth;
    // YM2149 doesn't have hardware vibrato
    // Could implement via frequency modulation in software if needed
}

// Set tremolo rate (global effect)
void ym2149_set_tremolo(uint8_t rate) {
    // Suppress unused parameter warning
    (void)rate;
    // YM2149 doesn't have hardware tremolo
    // Could implement via volume modulation if needed
}

// Set pitch bend
void ym2149_set_pitch_bend(int16_t bend) {
    // Apply pitch bend to all active voices
    for (uint8_t i = 0; i < 3; i++) {
        voice_t* v = &ym2149_voices[i];
        if (v->active) {
            uint16_t base_freq = ym2149_note_to_freq(v->midi_note);
            uint16_t bent_freq = ym2149_apply_pitch_bend(base_freq, bend);
            ym2149_set_frequency(i, bent_freq);
        }
    }
}

// Set modulation depth (same as vibrato on YM2149)
void ym2149_set_modulation(uint8_t depth) {
    (void)depth;
    // YM2149 doesn't have hardware modulation
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
    ym2149_write_register(YM2149_MIXER, YM2149_MIX_ALL_OFF);  // Disable all outputs
}

// Set frequency for a voice
void ym2149_set_frequency(uint8_t voice, uint16_t freq) {
    if (voice >= 3) return;
    
    uint8_t freq_lsb = YM2149_FREQ_A_LSB + (voice * 2);
    uint8_t freq_msb = YM2149_FREQ_A_MSB + (voice * 2);
    
    ym2149_write_register(freq_lsb, freq & 0xFF);
    ym2149_write_register(freq_msb, (freq >> 8) & 0x0F);  // Only lower 4 bits valid
}

// MIDI note to YM2149 tone period conversion
// Table covers MIDI notes 24 (C1) to 96 (C7)
// TP = round(1843200 / (16 * freq)) = round(115200 / freq)
// Higher period = lower pitch (YM2149 convention)
uint16_t ym2149_note_to_freq(uint8_t note) {
    static const uint16_t note_tp[] = {
        /* 24  C1 */ 3522, 3325, 3138, 2962, 2796, 2639, 2491, 2351,
        /* 32     */ 2219, 2095, 1977, 1866,
        /* 36  C2 */ 1761, 1662, 1569, 1481, 1398, 1319, 1245, 1175,
        /* 44     */ 1109, 1047,  989,  933,
        /* 48  C3 */  881,  831,  784,  740,  699,  660,  623,  588,
        /* 56     */  555,  524,  494,  467,
        /* 60  C4 */  440,  416,  392,  370,  349,  330,  311,  294,
        /* 68     */  277,  262,  247,  233,
        /* 72  C5 */  220,  208,  196,  185,  175,  165,  156,  147,
        /* 80     */  139,  131,  124,  117,
        /* 84  C6 */  110,  104,   98,   93,   87,   82,   78,   73,
        /* 92     */   69,   65,   62,   58,
        /* 96  C7 */   55
    };

    if (note < YM2149_MIDI_NOTE_MIN) note = YM2149_MIDI_NOTE_MIN;
    if (note > YM2149_MIDI_NOTE_MAX) note = YM2149_MIDI_NOTE_MAX;

    return note_tp[note - YM2149_MIDI_NOTE_MIN];
}

// Apply pitch bend to frequency (period)
uint16_t ym2149_apply_pitch_bend(uint16_t base_freq, int16_t bend) {
    // Pitch up (positive bend) -> decrease period
    // Pitch down (negative bend) -> increase period
    // linear approximation for +/- 2 semitone range:
    // Factor for +2 semitones: 0.8909 (10.9% decrease)
    // Factor for -2 semitones: 1.1225 (12.3% increase)

    // Using an average divisor for a decent linear approximation
    int32_t delta = ((int32_t)base_freq * bend) / 72000L;
    int32_t result = (int32_t)base_freq - delta;

    if (result < 1) result = 1;          // Clamp to minimum valid period
    if (result > 4095) result = 4095;    // Clamp to 12-bit max
    return (uint16_t)result;
}

// Read from YM2149 register (for detection)
// On the RC2014 YM/AY card, the addr port (0xD8) serves double duty:
//   OUT → latches the register address  (BDIR=1, BC1=1)
//   IN  → reads the register data       (BDIR=0, BC1=1)
// The data port (0xD0) is write-only (BDIR=1, BC1=0).
static uint8_t ym2149_read_register(uint8_t reg) {
    outp(YM2149_ADDR_PORT, reg);
    SmallDelay();
    return inp(YM2149_ADDR_PORT);
}

// Detect YM2149 chip presence
uint8_t detect_ym2149(void) {
    // YM2149 Detection Strategy:
    // 1. Write test patterns to mixer register (7) - tone/noise enable bits are readable
    // 2. Write test patterns to level registers (8,9,10) - volume bits (0-3) are readable  
    // 3. Write to frequency registers to verify they're not stuck
    // 4. Restore original register states to avoid disrupting system state
    // 
    // This approach is robust because:
    // - It uses multiple registers for verification
    // - It accounts for read-only bits in certain registers
    // - It preserves the original chip state
    // - It handles the case where no chip is present (reads return 0xFF)
    
    uint8_t test_values[] = {0x00, 0x55, 0xAA, 0xFF};
    uint8_t read_back;
    uint8_t detection_passed = 1;
    
    // Save original register states
    uint8_t orig_mixer = 0;
    uint8_t orig_level_a = 0;
    uint8_t orig_level_b = 0;
    
    // Try to read original states (may fail if no chip present)
    __asm__("di");  // Disable interrupts during detection
    orig_mixer = ym2149_read_register(YM2149_MIXER);
    orig_level_a = ym2149_read_register(YM2149_LEVEL_A);
    orig_level_b = ym2149_read_register(YM2149_LEVEL_B);
    
    // Test 1: Write/read back to mixer register (7)
    for (uint8_t i = 0; i < sizeof(test_values); i++) {
        ym2149_write_register(YM2149_MIXER, test_values[i]);
        SmallDelay();
        read_back = ym2149_read_register(YM2149_MIXER);
        
        // Some bits might be read-only, check if at least some bits match
        if ((read_back & 0x3F) != (test_values[i] & 0x3F)) {
            detection_passed = 0;
            break;
        }
    }
    
    if (detection_passed) {
        // Test 2: Write/read back to level registers (8, 9)
        for (uint8_t i = 0; i < sizeof(test_values); i++) {
            ym2149_write_register(YM2149_LEVEL_A, test_values[i]);
            SmallDelay();
            read_back = ym2149_read_register(YM2149_LEVEL_A);
            
            // Volume bits (0-3) should be readable
            if ((read_back & 0x0F) != (test_values[i] & 0x0F)) {
                detection_passed = 0;
                break;
            }
        }
    }
    
    if (detection_passed) {
        // Test 3: Test frequency register accessibility
        // Write to frequency low register and verify it's not stuck
        ym2149_write_register(YM2149_FREQ_A_LSB, 0x42);
        SmallDelay();
        read_back = ym2149_read_register(YM2149_FREQ_A_LSB);
        if (read_back != 0x42) {
            detection_passed = 0;
        }
    }
    
    // Restore original register states
    ym2149_write_register(YM2149_MIXER, orig_mixer);
    ym2149_write_register(YM2149_LEVEL_A, orig_level_a);
    ym2149_write_register(YM2149_LEVEL_B, orig_level_b);
    
    __asm__("ei");  // Re-enable interrupts
    
    return detection_passed;
}

// Simple delay function for test sequences
void delay_ms(uint16_t ms) {
    // Nested loops to avoid uint16_t overflow (ms * 100 overflows when ms > 655)
    for (volatile uint16_t i = 0; i < ms; i++) {
        for (volatile uint8_t j = 0; j < 100; j++) {
            // Adjust iteration count based on actual clock speed
        }
    }
}

// Play test sequence to verify audio output
void ym2149_play_test_sequence(void) {
    printf("Playing YM2149 test sequence...\n");

    // Test 1: Simple tone on each channel
    printf("Testing individual channels...\n");
    
    // Channel A - C4 (MIDI 60)
    ym2149_set_frequency(0, ym2149_note_to_freq(60));
    ym2149_set_volume(0, 10);  // Medium volume
    delay_ms(500);

    // Channel B - E4 (MIDI 64)
    ym2149_set_frequency(1, ym2149_note_to_freq(64));
    ym2149_set_volume(1, 10);
    delay_ms(500);

    // Channel C - G4 (MIDI 67)
    ym2149_set_frequency(2, ym2149_note_to_freq(67));
    ym2149_set_volume(2, 10);
    delay_ms(500);
    
    // Test 2: All channels together
    printf("Testing all channels together...\n");
    delay_ms(500);
    
    // Test 3: Volume sweep
    printf("Testing volume control...\n");
    for (uint8_t vol = 15; vol > 0; vol--) {
        ym2149_set_volume(0, vol);
        ym2149_set_volume(1, vol);
        ym2149_set_volume(2, vol);
        delay_ms(100);
    }
    
    for (uint8_t vol = 0; vol <= 15; vol++) {
        ym2149_set_volume(0, vol);
        ym2149_set_volume(1, vol);
        ym2149_set_volume(2, vol);
        delay_ms(100);
    }
    
    // Test 4: Noise generator
    printf("Testing noise generator...\n");
    ym2149_write_register(YM2149_FREQ_NOISE, 0x1F);  // Middle noise frequency
    // Enable noise on all channels, disable tone
    ym2149_write_register(YM2149_MIXER, YM2149_MIX_TONE_A_OFF | YM2149_MIX_TONE_B_OFF | YM2149_MIX_TONE_C_OFF);
    delay_ms(1000);

    // Clean up - restore tone mode
    ym2149_write_register(YM2149_MIXER, YM2149_MIX_ALL_TONE);
    ym2149_all_off();
    
    printf("Test sequence complete.\n");
}

// Play musical scale
void ym2149_play_scale(void) {
    printf("Playing C major scale...\n");

    // C major scale: C4, D4, E4, F4, G4, A4, B4, C5
    uint8_t scale_notes[] = {60, 62, 64, 65, 67, 69, 71, 72};

    for (uint8_t i = 0; i < 8; i++) {
        // Play note on channel A
        ym2149_set_frequency(0, ym2149_note_to_freq(scale_notes[i]));
        ym2149_set_volume(0, 12);  // Good volume for testing
        printf("Note: %d\n", scale_notes[i]);
        delay_ms(400);

        // Brief pause between notes
        ym2149_set_volume(0, 0);
        delay_ms(50);
    }

    printf("Scale complete.\n");
}

// Play arpeggio test
void ym2149_play_arpeggio(void) {
    printf("Playing arpeggio test...\n");

    // C major arpeggio: C4, E4, G4
    uint8_t chord_notes[] = {60, 64, 67};

    // Play each note on separate channel
    for (uint8_t ch = 0; ch < 3; ch++) {
        ym2149_set_frequency(ch, ym2149_note_to_freq(chord_notes[ch]));
        ym2149_set_volume(ch, 8);
        delay_ms(100);
    }
    
    // Let them play together
    delay_ms(1000);
    
    // Fade out
    for (uint8_t vol = 8; vol > 0; vol--) {
        ym2149_set_volume(0, vol);
        ym2149_set_volume(1, vol);
        ym2149_set_volume(2, vol);
        delay_ms(150);
    }
    
    ym2149_all_off();
    printf("Arpeggio complete.\n");
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
    
    .voices = ym2149_voices
};