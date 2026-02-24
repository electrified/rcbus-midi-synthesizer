-- tests/e2e/mame_test.lua
--
-- Minimal MAME Lua watchdog for the null-modem E2E test.
--
-- With the null-modem approach the emulated serial port is wired to a TCP
-- socket on localhost.  All test interaction (CP/M commands, output capture,
-- assertions) is handled by null_modem_terminal.py, which connects to that
-- socket.  This Lua script has one job: exit MAME cleanly when the Python
-- script signals it is done.
--
-- Signalling mechanism
-- --------------------
-- null_modem_terminal.py writes a "done flag" file when its work is finished:
--
--   tests/e2e/results/mame_done.flag
--
-- This script polls for that file once per emulated second (every 60 frames
-- at the rc2014zedp frame rate).  When it sees the file it removes it and
-- calls manager.machine:exit() so that MAME exits cleanly and the shell
-- runner can collect results.
--
-- A frame-count safety cutoff is also provided so that a hung Python script
-- cannot leave MAME running forever.
--
-- Requirements: MAME 0.229+ (tested with 0.264)

local RESULTS_DIR = "tests/e2e/results"
local DONE_FLAG   = RESULTS_DIR .. "/mame_done.flag"

-- Safety cutoff: exit after this many emulated frames regardless.
-- 36000 frames @ ~60 fps ≈ 10 minutes of emulated time.  With -nothrottle
-- this is far longer than any real test run but short enough to avoid wasting
-- CI time if something goes wrong.
local MAX_FRAMES = 36000

-- How often (in frames) to log a heartbeat so CI knows we're alive.
local HEARTBEAT_INTERVAL = 1800  -- ~30 seconds of emulated time

-- ---------------------------------------------------------------------------
-- Initialise
-- ---------------------------------------------------------------------------

os.execute("mkdir -p " .. RESULTS_DIR)
os.execute("mkdir -p " .. RESULTS_DIR .. "/snapshots")

local frame_count = 0

print("[mame_test] null-modem watchdog started")
print("[mame_test] Waiting for done flag: " .. DONE_FLAG)
print("[mame_test] Safety cutoff: " .. MAX_FRAMES .. " frames")

-- ---------------------------------------------------------------------------
-- Per-frame callback
-- ---------------------------------------------------------------------------

emu.register_frame_done(function()
    frame_count = frame_count + 1

    -- Poll for the done flag approximately once per emulated second.
    if frame_count % 60 == 0 then
        local fh = io.open(DONE_FLAG, "r")
        if fh then
            fh:close()
            os.remove(DONE_FLAG)
            print(string.format(
                "[mame_test] Done flag found at frame %d — exiting MAME",
                frame_count))
            manager.machine:exit()
            return
        end
    end

    -- Periodic heartbeat so CI logs show we're still alive
    if frame_count % HEARTBEAT_INTERVAL == 0 then
        local elapsed_sec = frame_count / 60
        local remaining_sec = (MAX_FRAMES - frame_count) / 60
        print(string.format(
            "[mame_test] heartbeat: frame %d (%.0fs elapsed, %.0fs until cutoff)",
            frame_count, elapsed_sec, remaining_sec))
    end

    -- Safety cutoff
    if frame_count >= MAX_FRAMES then
        print(string.format(
            "[mame_test] Safety timeout reached (%d frames / %.0fs) — forcing exit",
            MAX_FRAMES, MAX_FRAMES / 60))
        manager.machine:exit()
    end
end)

-- Guarantee a clean close on any machine-stop event (user closes window, etc.)
local _stop_sub = emu.add_machine_stop_notifier(function()
    print(string.format("[mame_test] Machine stopping at frame %d", frame_count))
    -- Clean up the done flag if it still exists
    os.remove(DONE_FLAG)
end)
