#include "../../include/midi_driver.h"
#include "../../include/chip_interface.h"
#include "../../include/synthesizer.h"
#include <stdint.h>

// Global MIDI state
midi_state_t midi_state;
midi_cc_control_t midi_cc_controls[12];

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

// Check if MIDI data is available
uint8_t midi_driver_available(void) {
    // This will need to be implemented based on your MIDI interface
    // For now, return 0 (no data available)
    // TODO: Implement UART status checking for RC2014 MIDI board
    return 0;
}

// Read one byte from MIDI interface
uint8_t midi_driver_read_byte(void) {
    // This will need to be implemented based on your MIDI interface
    // For now, return 0 (no data)
    // TODO: Implement UART read for RC2014 MIDI board
    return 0;
}

// Process all available MIDI input
void midi_driver_process_input(void) {
    while (midi_driver_available()) {
        uint8_t byte = midi_driver_read_byte();
        midi_process_byte(byte);
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
                    uint8_t voice = find_voice_by_note(data1, channel);
                    if (voice != 0xFF) {
                        current_chip->note_off(voice);
                    }
                } else {
                    uint8_t voice = allocate_voice(data1, data2, channel);
                    if (voice != 0xFF) {
                        current_chip->note_on(voice, data1, data2, channel);
                    }
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
                                    current_chip->set_volume(i, data2 * 15 / 127);
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