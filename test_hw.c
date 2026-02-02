#include <stdio.h>
#include <stdint.h>

// YM2149 I/O ports for RC2014 R5
#define YM2149_ADDR_PORT     0xD8
#define YM2149_DATA_PORT     0xD0

// YM2149 Register addresses
#define YM2149_FREQ_A_LSB     0x00
#define YM2149_FREQ_A_MSB     0x01
#define YM2149_LEVEL_A       0x08
#define YM2149_MIXER         0x07



// Small delay
static void SmallDelay(void) {
    volatile uint16_t i;
    for (i = 0; i < 1000; i++) {
        // Delay loop
    }
}

// Test I/O port accessibility
static void test_io_ports(void) {
    printf("=== Testing I/O Port Access ===\n");
    
    printf("Testing address port (0x%02X)...\n", YM2149_ADDR_PORT);
    
    // Try to write to address register
    outp(YM2149_ADDR_PORT, 0x00);
    SmallDelay();
    
    // Try to read from address port (should read back last written value)
    uint8_t addr_readback = inp(YM2149_ADDR_PORT);
    printf("Address port readback: 0x%02X\n", addr_readback);
    
    printf("Testing data port (0x%02X)...\n", YM2149_DATA_PORT);
    
    // Try to write to data register
    outp(YM2149_DATA_PORT, 0x00);
    SmallDelay();
    
    // Try to read from data port
    uint8_t data_readback = inp(YM2149_DATA_PORT);
    printf("Data port readback: 0x%02X\n", data_readback);
    
    printf("I/O port test complete.\n\n");
}

// Write to YM2149 register using assembly
static void ym2149_write_register(uint8_t reg, uint8_t data) {
    outp(YM2149_ADDR_PORT, reg);
    SmallDelay();
    outp(YM2149_DATA_PORT, data);
    SmallDelay();
}

// Simple tone test
static void play_test_tone(void) {
    printf("=== YM2149 Tone Test ===\n");
    printf("Initializing YM2149...\n");
    
    // Reset YM2149 to known state
    ym2149_write_register(0x07, 0x3F);  // All channels disabled
    ym2149_write_register(0x08, 0x00);  // Volume 0
    ym2149_write_register(0x09, 0x00);
    ym2149_write_register(0x0A, 0x00);
    
    printf("Setting up channel A for tone...\n");
    
    // Set mixer - enable channel A tone only
    ym2149_write_register(0x07, 0x38);  // Enable tone on A, disable noise
    
    // Set volume to maximum
    ym2149_write_register(0x08, 0x0F);  // Channel A, volume 15
    
    printf("Playing 440 Hz tone (A4)...\n");
    
    // Set frequency for 440 Hz (A4)
    ym2149_write_register(0x00, 0x9D);  // Low byte
    ym2149_write_register(0x01, 0x01);  // High byte with enable
    
    printf("Tone should now be playing for 3 seconds...\n");
    
    // Simple delay loop (no sleep function)
    for (volatile int i = 0; i < 3000000; i++) {
        // Wait approximately 3 seconds
    }
    
    printf("Turning off tone...\n");
    
    // Turn off the tone
    ym2149_write_register(0x01, 0x00);  // Disable channel A
    ym2149_write_register(0x08, 0x00);  // Volume 0
    
    printf("Tone test complete.\n");
}

int main(void) {
    printf("=== RC2014 YM2149 Hardware Test ===\n");
    printf("Using I/O ports: Addr=0x%02X, Data=0x%02X\n\n", YM2149_ADDR_PORT, YM2149_DATA_PORT);
    
    // Test I/O port accessibility first
    test_io_ports();
    
    // Test YM2149 tone generation
    play_test_tone();
    
    printf("\nTest complete.\n");
    return 0;
}