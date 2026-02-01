#include "../include/synthesizer.h"
#include "../include/chip_interface.h"
#include "../include/chip_manager.h"
#include "../include/midi_driver.h"
#include <stdio.h>
#include <stdlib.h>

// External chip interface declarations
extern sound_chip_interface_t ym2149_interface;

// Function prototypes
void print_help(void);
void print_chip_status(void);
void process_command(char cmd);

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
    
    return 0;
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
    printf("p/P - Panic (all notes off)\n");
    printf("1   - Select YM2149 sound chip\n");
    printf("2   - Select OPL3 sound chip (not implemented)\n");
    printf("q/Q - Quit program\n");
    printf("\nMIDI CC Controls:\n");
    printf("CC#1-4   : Volume controls (8 knobs)\n");
    printf("CC#5-8   : Envelope controls (remaining knobs)\n");
    printf("CC#9-12  : Global effects (4 sliders)\n");
    printf("\nThe synthesizer processes MIDI input automatically.\n");
    printf("===================================\n");
}

// Print chip status
void print_chip_status(void) {
    printf("\n");
    synthesizer_print_status();
}