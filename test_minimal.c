#include <stdio.h>
#include <stdint.h>

// Port definitions (same as BASIC)
#define R 216  // &hd8 - Address port  
#define D 208  // &hd0 - Data port

static void delay(void) {
    volatile uint32_t x;
    for (x = 1; x <= 10000; x++) {
        // Much longer delay to compensate for C execution speed
    }
}

int main(void) {
    printf("=== YM2149 Descending Tones on Channel A ===\n");
    
    while (1) {
        // Line 30: OUT R,7 : REM select the mixer register
        outp(R, 7);
        
        // Line 40: OUT D,62 : REM enable channel A only
        outp(D, 62);
        
        // Line 41: OUT R,8 : REM channel A volume
        outp(R, 8);
        
        // Line 42: OUT D,15 : REM set it to maximum
        outp(D, 15);
        
        // Line 50: OUT R,0 : REM select channel A pitch
        outp(R, 0);
        
        // Lines 55-65: FOR N=1 TO 255 : OUT D,N : GOSUB 100 : NEXT
        for (int n = 1; n <= 255; n++) {
            outp(D, n);  // Set it
            delay();          // GOSUB 100
        }
        
        // Line 90: GOTO 30
        // Loop continues
    }
    
    return 0;
}