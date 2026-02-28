#include "../include/synthesizer.h"
#include "../include/chip_interface.h"
#include "../include/chip_manager.h"
#include "../include/midi_driver.h"
#include "../include/ym2149.h"
#include "../include/port_config.h"
#include <stdio.h>
#include <stdlib.h>
#include <conio.h>

// Function prototypes
void print_help(void);
void print_chip_status(void);
void process_command(char cmd);
void run_audio_test(void);

// Main function
int main(void) {
    printf("\n=== RC2014 Multi-Chip MIDI Synthesizer ===\n");
    printf("Version 1.0 - YM2149 + OPL3 Ready\n\n");

    // Initialize synthesizer system
    synthesizer_init();

    printf("\nReady. Type 'h' for help.\n\n");

    // Main loop: process MIDI and check for keyboard commands
    while (1) {
        // Process any pending MIDI input (BIOS mode)
        midi_driver_process_input();

        // Check for keyboard command (non-blocking)
        if (kbhit()) {
            char cmd = getch();
            if (cmd == '\n' || cmd == '\r') {
                continue;
            }
            // In keyboard MIDI mode, route keys to MIDI handler
            // unless it's the escape key (0x1B) to exit keyboard mode
            if (midi_get_mode() == MIDI_MODE_KEYBOARD) {
                if (cmd == 0x1B || cmd == '`') {
                    // ESC or backtick exits keyboard MIDI mode
                    midi_set_mode(MIDI_MODE_NONE);
                    synthesizer_panic();
                    printf("\nKeyboard MIDI mode off.\n");
                } else {
                    midi_keyboard_process_key(cmd);
                }
            } else {
                process_command(cmd);
            }
        }
    }
}

// Process user commands
void process_command(char cmd) {
    switch (cmd) {
        case 'h':
        case 'H':
            print_help();
            break;

        case 's':
        case 'S':
            print_chip_status();
            break;

        case 'p':
        case 'P':
            synthesizer_panic();
            break;

        case '1':
            printf("Switching to YM2149...\n");
            if (chip_manager_set_chip(CHIP_YM2149)) {
                printf("YM2149 selected successfully.\n");
            } else {
                printf("Failed to select YM2149.\n");
            }
            break;

        case '2':
            printf("OPL3 not yet implemented.\n");
            break;

        case 't':
        case 'T':
            run_audio_test();
            break;

        case 'i':
        case 'I':
            printf("Current I/O ports:\n");
            printf("  Register port: 0x%02X\n", ym2149_ports.addr_port);
            printf("  Data port: 0x%02X\n", ym2149_ports.data_port);
            break;

        case 'r':
        case 'R':
            printf("Reloading port configuration...\n");
            if (port_config_load_from_file("ports.conf")) {
                printf("Configuration loaded successfully.\n");
                printf("  Register port: 0x%02X\n", ym2149_ports.addr_port);
                printf("  Data port: 0x%02X\n", ym2149_ports.data_port);
            } else {
                printf("Failed to load ports.conf - using defaults.\n");
            }
            break;

        case 'k':
        case 'K':
            // Enter keyboard MIDI mode
            midi_set_mode(MIDI_MODE_KEYBOARD);
            printf("Keyboard MIDI mode on.\n");
            printf("Keys: z-m/q-u=notes [/]=octave -/+=vel space=off ESC=exit\n");
            break;

        case 'm':
        case 'M':
            // Toggle BIOS MIDI mode
            if (midi_get_mode() == MIDI_MODE_BIOS) {
                midi_set_mode(MIDI_MODE_NONE);
                synthesizer_panic();
                printf("BIOS MIDI mode off.\n");
            } else {
                midi_set_mode(MIDI_MODE_BIOS);
                printf("BIOS MIDI mode on (AUX serial port).\n");
            }
            break;

        case '0':
        case 'q':
        case 'Q':
            printf("Exiting synthesizer...\n");
            synthesizer_panic();
            exit(0);
            break;

        default:
            printf("Unknown command: '%c'. Type 'h' for help.\n", cmd);
            break;
    }
}

// Print help information
void print_help(void) {
    printf("\n=== RC2014 MIDI Synthesizer Commands ===\n");
    printf("h/H - Show this help\n");
    printf("s/S - Show system status\n");
    printf("i/I - Show current I/O ports\n");
    printf("r/R - Reload port configuration\n");
    printf("t/T - Test audio output (YM2149 only)\n");
    printf("k/K - Keyboard MIDI mode (ESC to exit)\n");
    printf("m/M - Toggle BIOS MIDI mode (AUX serial)\n");
    printf("p/P - Panic (all notes off)\n");
    printf("1   - Select YM2149 sound chip\n");
    printf("2   - Select OPL3 sound chip (not implemented)\n");
    printf("q/Q - Quit program\n");
    printf("\nKeyboard MIDI keys (in 'k' mode):\n");
    printf("  z s x d c v g b h n j m = C..B (lower oct)\n");
    printf("  q 2 w 3 e r 5 f 6 y 7 u = C..B (upper oct)\n");
    printf("  [ ] = octave down/up, -/+ = velocity\n");
    printf("  space = note off, ESC/` = exit mode\n");
    printf("===================================\n");
}

// Print chip status
void print_chip_status(void) {
    printf("\n");
    synthesizer_print_status();
}

// Run audio test sequence
void run_audio_test(void) {
    printf("\n=== Audio Test Mode ===\n");

    if (!current_chip) {
        printf("No sound chip selected! Please select a chip first.\n");
        return;
    }

    if (current_chip->chip_id != CHIP_YM2149) {
        printf("Audio test only implemented for YM2149 chip.\n");
        printf("Current chip: %s\n", current_chip->name);
        return;
    }

    printf("Testing YM2149 audio output...\n");
    printf("You should hear audio tones if your hardware is working.\n");
    printf("Press Ctrl+C to interrupt if needed.\n\n");

    // Run full test sequence
    ym2149_play_test_sequence();

    delay_ms(500);

    printf("\nRunning scale test...\n");
    ym2149_play_scale();

    delay_ms(500);

    printf("\nRunning arpeggio test...\n");
    ym2149_play_arpeggio();

    printf("\n=== Audio Test Complete ===\n");
}
