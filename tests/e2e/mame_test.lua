-- tests/e2e/mame_test.lua
--
-- MAME Lua E2E test script for the RC2014 MIDI Synthesizer.
--
-- Invoked by run_e2e.sh via MAME's -script flag:
--
--   mame rc2014zedp -bus:5 cf -hard cheese.img -bus:12 ay_sound \
--        -nothrottle -script tests/e2e/mame_test.lua
--
-- How it works:
--   Frame counting drives a linear sequence of scripted keystrokes sent to
--   the emulated terminal via emu.keypost().  At key points screenshots are
--   taken with manager.machine.video:snapshot().  Results are written to
--   tests/e2e/results/test_result.txt so the shell runner can check them.
--
-- Timing:
--   All timing is in *emulated* frames (the RC2014 terminal runs at ~60 Hz
--   in MAME).  With -nothrottle, wall-clock time is typically much shorter.
--
-- Requirements: MAME 0.200+

-- ---------------------------------------------------------------------------
-- Configuration
-- ---------------------------------------------------------------------------

local RESULTS_DIR = "tests/e2e/results"
local RESULT_FILE = RESULTS_DIR .. "/test_result.txt"

-- Emulated-frame budgets (60 frames ≈ 1 emulated second)
local FRAMES_BOOT    = 600   -- 10 s: CP/M BIOS init + CF card read + A> prompt
local FRAMES_STARTUP = 240   -- 4 s:  midisynth binary loads and prints banner
local FRAMES_CMD     = 120   -- 2 s:  simple command completes and prints output
local FRAMES_AUDIO   = 600   -- 10 s: full audio test sequence (tones + scale + arp)

-- ---------------------------------------------------------------------------
-- Build the ordered test sequence
-- Each entry: { frame = <absolute frame>, keys = <string or nil>, desc = <string> }
-- A nil 'keys' value means "exit MAME" (no more input to send).
-- ---------------------------------------------------------------------------

local sequence = {}

local function build_sequence()
    local f = FRAMES_BOOT

    local function step(keys, desc, extra_frames)
        table.insert(sequence, { frame = f, keys = keys, desc = desc })
        f = f + (extra_frames or FRAMES_CMD)
    end

    -- Boot: type the program name at the CP/M A> prompt
    step("midisyn\r", "boot: launch midisynth",  FRAMES_STARTUP)

    -- Interactive commands (each produces a known text response)
    step("h",         "cmd: help",    FRAMES_CMD)
    step("s",         "cmd: status",  FRAMES_CMD)
    step("i",         "cmd: ioports", FRAMES_CMD)

    -- Audio test – generates actual YM2149 register writes through the whole
    -- test_sequence / scale / arpeggio chain; allow extra frames.
    step("t",         "cmd: audio",   FRAMES_AUDIO)

    -- Quit; the program calls exit(0) which returns to the CP/M prompt
    step("q",         "cmd: quit",    FRAMES_CMD)

    -- Sentinel: exit MAME
    table.insert(sequence, { frame = f, keys = nil, desc = "exit MAME" })
end

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

local frame_count = 0
local step_index  = 1
local result_file = nil

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function log(msg)
    local line = string.format("[e2e frame=%-6d] %s", frame_count, msg)
    print(line)
    if result_file then
        result_file:write(line .. "\n")
        result_file:flush()
    end
end

local function take_snapshot()
    -- Wrapped in pcall so that headless (-video none) mode does not crash the
    -- script; snapshot() is a no-op when there is no video output.
    local ok, err = pcall(function()
        manager.machine.video:snapshot()
    end)
    if not ok then
        log("snapshot skipped: " .. tostring(err))
    end
end

-- ---------------------------------------------------------------------------
-- MAME callbacks
-- ---------------------------------------------------------------------------

emu.register_start(function()
    build_sequence()

    -- Create results directory (MAME is invoked from the project root)
    os.execute("mkdir -p " .. RESULTS_DIR)
    os.execute("mkdir -p " .. RESULTS_DIR .. "/snapshots")

    result_file = io.open(RESULT_FILE, "w")
    if not result_file then
        print("[e2e] WARNING: cannot write " .. RESULT_FILE)
    end

    log("test started — " .. #sequence .. " steps")
    log(string.format("timing — boot:%d startup:%d cmd:%d audio:%d frames",
        FRAMES_BOOT, FRAMES_STARTUP, FRAMES_CMD, FRAMES_AUDIO))
end)

emu.register_frame_done(function()
    frame_count = frame_count + 1

    -- Nothing left to do once all steps are dispatched
    if step_index > #sequence then
        return
    end

    local step = sequence[step_index]
    if frame_count < step.frame then
        return
    end

    -- Time to execute this step
    log("step " .. step_index .. "/" .. #sequence .. ": " .. step.desc)

    if step.keys == nil then
        -- Final sentinel: write result and exit
        log("all steps complete")
        if result_file then
            result_file:write("RESULT: PASS\n")
            result_file:close()
            result_file = nil
        end
        manager.machine:exit()
        return
    end

    -- Snapshot the screen before sending input so we can see the state the
    -- emulator was in when each command was issued.
    take_snapshot()

    emu.keypost(step.keys)
    step_index = step_index + 1
end)

emu.register_stop(function()
    -- Guarantee the result file is closed even if MAME is killed externally.
    if result_file then
        if step_index > #sequence then
            result_file:write("RESULT: PASS\n")
        else
            local pending = sequence[step_index]
            result_file:write(string.format(
                "RESULT: INCOMPLETE — stopped at step %d/%d (%s)\n",
                step_index, #sequence,
                pending and pending.desc or "?"))
        end
        result_file:close()
        result_file = nil
    end
end)
