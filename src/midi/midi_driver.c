#include "../../include/midi_driver.h"
#include "../../include/chip_interface.h"
#include "../../include/synthesizer.h"
#include <stdint.h>
#include <stdio.h>

// Global MIDI state
midi_state_t midi_state;
midi_cc_control_t midi_cc_controls[12];

// Current MIDI input mode
static uint8_t midi_mode = MIDI_MODE_NONE;

// Keyboard MIDI state
static uint8_t kb_current_octave = 5;    // Default octave (C5 = MIDI 60)
static uint8_t kb_current_velocity = 100; // Default velocity
static uint8_t kb_last_note = 0xFF;       // Last note played (for note-off)

// Direct Z80-SIO hardware I/O for auxiliary serial port (Channel B).
//
// HBIOS RST 08H was found to corrupt CP/M console I/O state, so we
// bypass HBIOS entirely and read the SIO registers directly.
//
// RC2014 Z80-SIO port map (base 0x80):
//   0x80 = Channel A data    0x81 = Channel A control
//   0x82 = Channel B data    0x83 = Channel B control
//
// RR0 bit 0 = Rx Character Available.
// Writing 0x00 to the control port selects RR0 for the next read.

// Check SIO Channel B Rx status — returns 0 if empty, 1 if data available
static uint8_t bios_auxist(void) __naked {
    __asm
        xor a               ; A = 0 → select RR0
        out (0x83), a       ; SIO Ch.B control: point to RR0
        in a, (0x83)        ; read RR0
        and 1               ; isolate bit 0 (Rx Char Available)
        ld l, a             ; return in L
        ret
    __endasm;
}

// Read one byte from SIO Channel B data register
static uint8_t bios_auxin(void) __naked {
    __asm
        in a, (0x82)        ; read SIO Ch.B data register
        ld l, a             ; return in L
        ret
    __endasm;
}

// Initialize MIDI driver
void midi_driver_init(void) {
    // Clear MIDI state
    midi_state.status = 0;
    midi_state.channel = 0;
    midi_state.command = 0;
    midi_state.data1 = 0;
    midi_state.data2 = 0;
    midi_state.expected_bytes = 0;
    midi_state.byte_count = 0;

    midi_mode = MIDI_MODE_NONE;
    kb_current_octave = 5;
    kb_current_velocity = 100;
    kb_last_note = 0xFF;

    // Initialize CC controls mapping
    // 8 rotary knobs
    for (uint8_t i = 0; i < 8; i++) {
        midi_cc_controls[i].cc_number = i + 1;  // CC#1-8 for knobs
        midi_cc_controls[i].value = 0;
        midi_cc_controls[i].is_knob = 1;
        midi_cc_controls[i].name = "Knob";
    }

    // 4 sliders
    for (uint8_t i = 0; i < 4; i++) {
        midi_cc_controls[i + 8].cc_number = i + 9;  // CC#9-12 for sliders
        midi_cc_controls[i + 8].value = 0;
        midi_cc_controls[i + 8].is_knob = 0;
        midi_cc_controls[i + 8].name = "Slider";
    }
}

// Set MIDI input mode
void midi_set_mode(uint8_t mode) {
    midi_mode = mode;
}

// Get current MIDI input mode
uint8_t midi_get_mode(void) {
    return midi_mode;
}

// Check if MIDI data is available (BIOS mode)
uint8_t midi_driver_available(void) {
    if (midi_mode != MIDI_MODE_BIOS) {
        return 0;
    }
    return bios_auxist();
}

// Read one byte from MIDI interface (BIOS mode)
uint8_t midi_driver_read_byte(void) {
    if (midi_mode != MIDI_MODE_BIOS) {
        return 0;
    }
    return bios_auxin();
}

// Process one pending MIDI byte (if available).
// Only one byte per call so the main loop always returns to kbhit()
// for console command processing.  At 7.3 MHz the loop iterates fast
// enough to keep up with 31250-baud MIDI (≈3125 bytes/sec).
void midi_driver_process_input(void) {
    if (midi_mode != MIDI_MODE_BIOS) {
        return;
    }
    if (midi_driver_available()) {
        uint8_t byte = midi_driver_read_byte();
        midi_process_byte(byte);
    }
}

// Keyboard MIDI mode: map a key press to MIDI note/CC messages
// Key mapping (piano-style on QWERTY keyboard):
//   z s x d c v g b h n j m  = C C# D D# E F F# G G# A A# B (lower octave)
//   q 2 w 3 e r 5 t 6 y 7 u  = C C# D D# E F F# G G# A A# B (upper octave)
//   [ / ]  = octave down / panic / octave up
//   - / +  = velocity down / up
void midi_keyboard_process_key(char key) {
    int8_t note_offset = -1;  // -1 = not a note key
    uint8_t upper = 0;        // 1 = upper octave row

    // Lower octave row (z-m keys)
    switch (key) {
        case 'z': note_offset = 0; break;   // C
        case 's': note_offset = 1; break;   // C#
        case 'x': note_offset = 2; break;   // D
        case 'd': note_offset = 3; break;   // D#
        case 'c': note_offset = 4; break;   // E
        case 'v': note_offset = 5; break;   // F
        case 'g': note_offset = 6; break;   // F#
        case 'b': note_offset = 7; break;   // G
        case 'h': note_offset = 8; break;   // G#
        case 'n': note_offset = 9; break;   // A
        case 'j': note_offset = 10; break;  // A#
        case 'm': note_offset = 11; break;  // B
    }

    // Upper octave row (q-u keys)
    if (note_offset < 0) {
        upper = 1;
        switch (key) {
            case 'q': note_offset = 0; break;   // C
            case '2': note_offset = 1; break;   // C#
            case 'w': note_offset = 2; break;   // D
            case '3': note_offset = 3; break;   // D#
            case 'e': note_offset = 4; break;   // E
            case 'r': note_offset = 5; break;   // F
            case '5': note_offset = 6; break;   // F#
            case 'f': note_offset = 7; break;   // G  (using 'f' since 't' conflicts)
            case '6': note_offset = 8; break;   // G#
            case 'y': note_offset = 9; break;   // A
            case '7': note_offset = 10; break;  // A#
            case 'u': note_offset = 11; break;  // B
        }
    }

    if (note_offset >= 0) {
        // Release previous note if one is held
        if (kb_last_note != 0xFF) {
            midi_process_message(MIDI_NOTE_OFF, kb_last_note, 0);
        }

        // Calculate MIDI note number
        uint8_t octave = kb_current_octave;
        if (upper) octave++;
        uint8_t midi_note = (octave * 12) + note_offset;

        // Clamp to valid MIDI range
        if (midi_note > 127) midi_note = 127;

        // Send note-on
        midi_process_message(MIDI_NOTE_ON, midi_note, kb_current_velocity);
        kb_last_note = midi_note;
        printf("Note: %d vel: %d\n", midi_note, kb_current_velocity);
        return;
    }

    // Non-note keys
    switch (key) {
        case '[':  // Octave down
            if (kb_current_octave > 0) {
                kb_current_octave--;
                printf("Octave: %d\n", kb_current_octave);
            }
            break;
        case ']':  // Octave up
            if (kb_current_octave < 9) {
                kb_current_octave++;
                printf("Octave: %d\n", kb_current_octave);
            }
            break;
        case '-':  // Velocity down
            if (kb_current_velocity > 10) {
                kb_current_velocity -= 10;
            } else {
                kb_current_velocity = 1;
            }
            printf("Velocity: %d\n", kb_current_velocity);
            break;
        case '=':  // Velocity up
            if (kb_current_velocity < 118) {
                kb_current_velocity += 10;
            } else {
                kb_current_velocity = 127;
            }
            printf("Velocity: %d\n", kb_current_velocity);
            break;
        case ' ':  // Space = note off (release current note)
            if (kb_last_note != 0xFF) {
                midi_process_message(MIDI_NOTE_OFF, kb_last_note, 0);
                printf("Note off: %d\n", kb_last_note);
                kb_last_note = 0xFF;
            }
            break;
        case '/':  // Panic
            if (kb_last_note != 0xFF) {
                midi_process_message(MIDI_NOTE_OFF, kb_last_note, 0);
                kb_last_note = 0xFF;
            }
            synthesizer_panic();
            break;
    }
}

// Process incoming MIDI byte
void midi_process_byte(uint8_t byte) {
    // System Realtime (0xF8-0xFF): can appear mid-message, never touch parser state
    if (byte >= 0xF8) {
        // Could handle clock (0xF8), start (0xFA), stop (0xFC) here if needed
        return;
    }

    // Check for status byte (MSB set)
    if (byte & 0x80) {
        // System Common (0xF0-0xF7): clear running status
        if (byte >= 0xF0) {
            midi_state.status = 0;
            midi_state.byte_count = 0;
            midi_state.expected_bytes = 0;
            return;
        }

        // Channel voice message
        midi_state.status = byte;
        midi_state.channel = byte & 0x0F;
        midi_state.command = byte & 0xF0;
        midi_state.byte_count = 0;

        // Determine expected bytes based on command
        switch (midi_state.command) {
            case MIDI_NOTE_OFF:
            case MIDI_NOTE_ON:
            case MIDI_CONTROL_CHANGE:
            case MIDI_PITCH_BEND:
                midi_state.expected_bytes = 2;
                break;
            case MIDI_PROGRAM_CHANGE:
                midi_state.expected_bytes = 1;
                break;
            default:
                midi_state.expected_bytes = 0;  // Unsupported command
                break;
        }
    }
    // Check for running status (data byte without status)
    else if (midi_state.status != 0) {
        midi_state.byte_count++;
        
        if (midi_state.byte_count == 1) {
            midi_state.data1 = byte;
        }
        else if (midi_state.byte_count == 2) {
            midi_state.data2 = byte;
        }
        
        // Check if we have a complete message
        if (midi_state.byte_count >= midi_state.expected_bytes) {
            midi_process_message(midi_state.status, midi_state.data1, midi_state.data2);
            midi_state.byte_count = 0;  // Reset for next message
        }
    }
}

// Process complete MIDI message
void midi_process_message(uint8_t status, uint8_t data1, uint8_t data2) {
    uint8_t channel = status & 0x0F;
    uint8_t command = status & 0xF0;
    
    switch (command) {
        case MIDI_NOTE_ON:
            if (current_chip && current_chip->note_on) {
                if (data2 == 0) {
                    // Note-on with velocity 0 is equivalent to note-off
                    if (current_chip->note_off) {
                        uint8_t voice = find_voice_by_note(data1, channel);
                        if (voice != 0xFF) {
                            current_chip->note_off(voice);
                        }
                    }
                    if (midi_mode == MIDI_MODE_BIOS)
                        printf("MIDI IN: Note Off %d\n", data1);
                } else {
                    uint8_t voice = allocate_voice(data1, data2, channel);
                    if (voice != 0xFF) {
                        current_chip->note_on(voice, data1, data2, channel);
                    }
                    if (midi_mode == MIDI_MODE_BIOS)
                        printf("MIDI IN: Note On %d vel %d\n", data1, data2);
                }
            }
            break;

        case MIDI_NOTE_OFF:
            if (current_chip && current_chip->note_off) {
                uint8_t voice = find_voice_by_note(data1, channel);
                if (voice != 0xFF) {
                    current_chip->note_off(voice);
                }
            }
            if (midi_mode == MIDI_MODE_BIOS)
                printf("MIDI IN: Note Off %d\n", data1);
            break;
            
        case MIDI_CONTROL_CHANGE:
            // Update CC control state
            for (uint8_t i = 0; i < 12; i++) {
                if (midi_cc_controls[i].cc_number == data1) {
                    midi_cc_controls[i].value = data2;
                    break;
                }
            }
            
            // Apply CC to current chip
            if (current_chip) {
                switch (data1) {
                    case 1: case 2: case 3: case 4:  // Volume controls
                        if (current_chip->set_volume) {
                            // Map to first active voice or global
                            for (uint8_t i = 0; i < current_chip->voice_count; i++) {
                                if (current_chip->voices[i].active) {
                                    current_chip->set_volume(i, (uint16_t)data2 * 15 / 127);
                                    break;
                                }
                            }
                        }
                        break;
                        
                    case 5:  // Attack
                        if (current_chip->set_attack) {
                            for (uint8_t i = 0; i < current_chip->voice_count; i++) {
                                if (current_chip->voices[i].active) {
                                    current_chip->set_attack(i, data2);
                                    break;
                                }
                            }
                        }
                        break;
                        
                    case 6:  // Decay
                        if (current_chip->set_decay) {
                            for (uint8_t i = 0; i < current_chip->voice_count; i++) {
                                if (current_chip->voices[i].active) {
                                    current_chip->set_decay(i, data2);
                                    break;
                                }
                            }
                        }
                        break;
                        
                    case 7:  // Sustain
                        if (current_chip->set_sustain) {
                            for (uint8_t i = 0; i < current_chip->voice_count; i++) {
                                if (current_chip->voices[i].active) {
                                    current_chip->set_sustain(i, data2);
                                    break;
                                }
                            }
                        }
                        break;
                        
                    case 8:  // Release
                        if (current_chip->set_release) {
                            for (uint8_t i = 0; i < current_chip->voice_count; i++) {
                                if (current_chip->voices[i].active) {
                                    current_chip->set_release(i, data2);
                                    break;
                                }
                            }
                        }
                        break;
                        
                    case 9:  // Vibrato
                        if (current_chip->set_vibrato) {
                            current_chip->set_vibrato(data2);
                        }
                        break;
                        
                    case 10:  // Tremolo
                        if (current_chip->set_tremolo) {
                            current_chip->set_tremolo(data2);
                        }
                        break;
                        
                    case 11:  // Expression / pitch bend via CC
                        if (current_chip->set_pitch_bend) {
                            // Scale CC value (0-127) to pitch bend range
                            int16_t bend = ((int16_t)data2 - 64) * 128;
                            current_chip->set_pitch_bend(bend);
                        }
                        break;
                        
                    case 12:  // Modulation
                        if (current_chip->set_modulation) {
                            current_chip->set_modulation(data2);
                        }
                        break;
                }
            }
            break;
            
        case MIDI_PROGRAM_CHANGE:
            if (current_chip && current_chip->set_preset) {
                current_chip->set_preset(data1);
            }
            break;
            
        case MIDI_PITCH_BEND:
            if (current_chip && current_chip->set_pitch_bend) {
                int16_t bend = (data2 << 7) | data1;
                current_chip->set_pitch_bend(bend - 8192);  // Center at 0
            }
            break;
    }
}