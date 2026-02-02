# RC2014 YM2149 Audio Test Programs

I've created three test programs to help verify your RC2014 YM2149 setup and troubleshoot the audio output issue.

## Test Programs

### 1. Minimal Test (`MINIMAL_TEST.COM`)
**Purpose**: Simplest possible I/O test
- Writes directly to ports 0xD8/0xD0
- Sets up continuous tone
- No complex logic

**Build & Run**:
```bash
./build_minimal_test.sh
mame rc2014 -flop1 minimal_test
```

### 2. Hardware Test (`HW_TEST.COM`)  
**Purpose**: Comprehensive hardware verification
- Tests I/O port accessibility
- Plays 440 Hz tone for 3 seconds
- Provides diagnostic output

**Build & Run**:
```bash
./build_hw_test.sh
mame rc2014 -flop1 hw_test
```

### 3. Tone Test (`TONE_TEST.COM`)
**Purpose**: Multi-frequency tone test
- Tests multiple frequencies (low, middle, high)
- 2-second intervals
- Uses proper YM2149 initialization

**Build & Run**:
```bash
./build_tone_test.sh
mame rc2014 -flop1 tone_test
```

## Troubleshooting Steps

### Start with Minimal Test
1. Run the minimal test first - it's the most basic
2. You should hear a continuous tone immediately
3. If no tone, the issue is likely hardware or I/O port configuration

### Check Hardware Connections
- **YM2149 Chip**: Properly seated in RC2014 bus
- **Audio Output**: Connected to speaker/amplifier
- **Power**: YM2149 receiving proper power
- **Clock**: YM2149 clock signal present

### Verify I/O Port Configuration
The default R5 RC2014 YM2149 uses:
- **Register Port**: 0xD8
- **Data Port**: 0xD0

If you have a different YM2149 version, edit the `#define` statements in the test programs.

### Common Issues

**No Audio Output**:
1. Wrong I/O ports - check your YM2149 variant
2. No audio connection - verify audio output wiring
3. Missing clock signal - YM2149 needs clock to generate audio
4. Volume settings - ensure volume not set to 0

**Garbled Audio**:
1. Wrong frequency values - check register calculations
2. Noise generators enabled - disable noise for clean tone
3. Multiple channels active - enable only one channel for testing

**Program Hangs/Crashes**:
1. I/O port access issues - check if ports are valid
2. Missing YM2149 chip - verify hardware presence
3. Clock issues - YM2149 may hang without clock

## Testing Procedure

### Step 1: Verify Basic I/O
```bash
./build_minimal_test.sh && echo "Run: mame rc2014 -flop1 minimal_test"
```

### Step 2: Test Hardware Response
```bash
./build_hw_test.sh && echo "Run: mame rc2014 -flop1 hw_test"
```

### Step 3: Test Multiple Frequencies
```bash
./build_tone_test.sh && echo "Run: mame rc2014 -flop1 tone_test"
```

### Step 4: Test Full Synthesizer
```bash
./build_docker.sh && echo "Run: mame rc2014 -flop1 midisynth"
```

## Expected Results

**Minimal Test**: Continuous tone plays immediately
**Hardware Test**: Diagnostic output + 3-second 440 Hz tone
**Tone Test**: Three different tones, 2 seconds each
**Full Synthesizer**: MIDI processing, CLI interface

## Next Steps

1. **Start with minimal test** - if it works, basic I/O is functional
2. **Progress to hardware test** - verifies YM2149 initialization
3. **Try full synthesizer** - if simple tests work, issue is in complex code

If none of the tests produce audio, the issue is likely:
- Hardware connections
- Wrong I/O port addresses for your YM2149 variant
- Missing clock or power to YM2149

Let me know what results you get from each test!