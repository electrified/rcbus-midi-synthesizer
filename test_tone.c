#include <stdio.h>
#include <stdint.h>
#include <unistd.h>

// YM2149 I/O ports for RC2014 R5
#define YM2149_ADDR_PORT     0xD8    // Address register
#define YM2149_DATA_PORT     0xD0    // Data register

// YM2149 Register addresses
#define YM2149_FREQ_A_LSB     0x00     // Channel A frequency low byte
#define YM2149_FREQ_A_MSB     0x01     // Channel A frequency high byte + enable
#define YM2149_LEVEL_A       0x08     // Channel A volume & envelope mode
#define YM2149_MIXER         0x07     // Tone/noise enable per channel

// Mixer control bits
#define YM2149_MIX_TONE_A    0x01     // Enable tone on channel A
#define YM2149_MIX_TONE_B    0x02     // Enable tone on channel B
#define YM2149_MIX_TONE_C    0x04     // Enable tone on channel C

// Volume modes
#define YM2149_VOLUME_FIXED    0x00     // Fixed volume mode

// Small delay function
static void SmallDelay(void) {
    volatile uint8_t i;
    for (i = 0; i < 10; i++) {
        // Simple delay loop
    }
}

// Write to YM2149 register
static void ym2149_write_register(uint8_t reg, uint8_t data) {
    outp(YM2149_ADDR_PORT, reg);
    SmallDelay();
    outp(YM2149_DATA_PORT, data);
    SmallDelay();
}

// Simple tone generation function
static void play_tone(uint16_t frequency) {
    printf("Playing tone with frequency value: 0x%04X (%d)\n", frequency, frequency);
    
    // Set mixer - enable channel A only
    ym2149_write_register(YM2149_MIXER, YM2149_MIX_TONE_A);
    
    // Set frequency (low byte first, then high byte with enable bit)
    ym2149_write_register(YM2149_FREQ_A_LSB, frequency & 0xFF);
    ym2149_write_register(YM2149_FREQ_A_MSB, (frequency >> 8) | 0x01);  // Set MSB with enable
    
    // Set volume to maximum
    ym2149_write_register(YM2149_LEVEL_A, YM2149_VOLUME_FIXED | 0x0F);
}

int main(void) {
    printf("=== RC2014 YM2149 Audio Test ===\n");
    printf("I/O Ports: Register=0x%02X, Data=0x%02X\n", YM2149_ADDR_PORT, YM2149_DATA_PORT);
    printf("\nTesting basic tone generation...\n");
    
    // Test a few different tones
    printf("\n1. Middle C tone (approx 262 Hz):\n");
    play_tone(0x0580);  // Middle C frequency value
    
    printf("Waiting 2 seconds...\n");
    sleep(2);
    
    printf("\n2. Higher tone (approx 523 Hz):\n");
    play_tone(0x02C0);  // One octave higher
    
    printf("Waiting 2 seconds...\n");
    sleep(2);
    
    printf("\n3. Lower tone (approx 131 Hz):\n");
    play_tone(0x0B00);  // One octave lower
    
    printf("Waiting 2 seconds...\n");
    sleep(2);
    
    // Turn off sound
    printf("\nTurning off sound...\n");
    ym2149_write_register(YM2149_MIXER, 0x00);  // All channels off
    ym2149_write_register(YM2149_LEVEL_A, 0x00);  // Volume to 0
    
    printf("Test complete.\n");
    return 0;
}