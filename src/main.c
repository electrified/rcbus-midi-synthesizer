#include "../include/synthesizer.h"
#include "../include/chip_interface.h"
#include "../include/chip_manager.h"
#include "../include/midi_driver.h"
#include "../include/ym2149.h"
#include "../include/port_config.h"
#include <stdio.h>
#include <stdlib.h>

// External chip interface declarations
extern sound_chip_interface_t ym2149_interface;

// Function prototypes
void print_help(void);
void print_chip_status(void);
void process_command(char cmd);
void run_audio_test(void);

// Simple delay function
static void delay_ms(uint16_t ms) {
    for (volatile uint16_t i = 0; i < ms * 100; i++) {
        // Approximate delay - adjust based on CPU speed
    }
}

// Main function
int main(void) {
    printf("\n=== RC2014 Multi-Chip MIDI Synthesizer ===\n");
    printf("Version 1.0 - YM2149 + OPL3 Ready\n\n");
    
    // Initialize synthesizer system
    synthesizer_init();
    
    printf("\nEntering main loop. Type 'h' for help.\n");
    printf("MIDI data will be processed automatically.\n\n");
    
    // Main interactive loop
    char cmd = 0;
    while (1) {
        printf("Synth> ");
        cmd = getchar();
        
        if (cmd != '\n') {
            process_command(cmd);
            // Clear input buffer
            while (getchar() != '\n') {}
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
            
        case '0':
        case 'q':
        case 'Q':
            printf("Exiting synthesizer...\n");
            synthesizer_panic();
            exit(0);
            break;
            
        case '\n':
            // Empty command, do nothing
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
    printf("p/P - Panic (all notes off)\n");
    printf("1   - Select YM2149 sound chip\n");
    printf("2   - Select OPL3 sound chip (not implemented)\n");
    printf("q/Q - Quit program\n");
    printf("\nMIDI CC Controls:\n");
    printf("CC#1-4   : Volume controls (8 knobs)\n");
    printf("CC#5-8   : Envelope controls (remaining knobs)\n");
    printf("CC#9-12  : Global effects (4 sliders)\n");
    printf("\nThe synthesizer processes MIDI input automatically.\n");
    printf("Audio test works even without MIDI keyboard.\n");
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
    
    // Run the test sequence
    ym2149_play_test_sequence();
    
    printf("Would you like to run additional tests? (y/n): ");
    char response = getchar();
    while (getchar() != '\n') {}  // Clear input buffer
    
    if (response == 'y' || response == 'Y') {
        printf("\nRunning scale test...\n");
        ym2149_play_scale();
        
        for (volatile uint8_t i = 0; i < 200; i++) {
            for (volatile uint8_t j = 0; j < 200; j++) {
                // Nested loops for delay
            }
        }
        
        printf("\nRunning arpeggio test...\n");
        ym2149_play_arpeggio();
    }
    
    printf("\n=== Audio Test Complete ===\n");
}