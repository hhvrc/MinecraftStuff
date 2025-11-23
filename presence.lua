-- presence.lua
-- Plays a presence audio file when a player walks by

local chat = peripheral.wrap("back")
local detector = peripheral.wrap("right")
local speaker = peripheral.wrap("top")

if not chat then error("No chat peripheral on 'back'") end
if not detector then error("No player detector on 'right'") end
if not speaker then error("No speaker on 'top'") end
if not http then error("HTTP API is not enabled in ComputerCraft config") end

local dfpwm = require("cc.audio.dfpwm")

-------------------------------------------------
-- Presence sound config
-------------------------------------------------
local PRESENCE_SOUND_PATH = "/presence_sound.dfpwm"
local PRESENCE_COOLDOWN_MS = 10_000  -- 10 seconds between plays
local DETECTION_RANGE = 5            -- blocks radius

-------------------------------------------------
-- Download presence sound
-------------------------------------------------
local function downloadPresenceSound(url)
    local h, err = http.get(url, nil, true) -- binary mode
    if not h then
        return false, "HTTP GET failed: " .. tostring(err)
    end

    local f = fs.open(PRESENCE_SOUND_PATH, "wb")
    if not f then
        h.close()
        return false, "Failed to open presence sound file for writing"
    end

    while true do
        local chunk = h.read(16 * 1024)
        if not chunk then break end
        f.write(chunk)
    end

    f.close()
    h.close()
    return true
end

-------------------------------------------------
-- Play presence sound (if configured)
-------------------------------------------------
local function playPresenceSound()
    if not fs.exists(PRESENCE_SOUND_PATH) then
        -- No sound configured, just ignore silently
        return
    end

    local file = fs.open(PRESENCE_SOUND_PATH, "rb")
    if not file then
        print("Failed to open presence sound file")
        return
    end

    local decoder = dfpwm.make_decoder()

    while true do
        local chunk = file.read(16 * 1024)
        if not chunk then break end

        local buffer = decoder(chunk)
        speaker.playAudio(buffer)

        -- Assume 48000 Hz mono, 1 byte per sample
        local seconds = #buffer / 48000
        if seconds > 0 then
            sleep(seconds)
        end
    end

    file.close()
end

-------------------------------------------------
-- Player detector loop
-------------------------------------------------
local function presenceLoop()
    local lastPlayMs = 0

    while true do
        -- getPlayersInRange(range) is typical for Advanced Peripherals player detector
        local ok, playersOrErr = pcall(detector.getPlayersInRange, DETECTION_RANGE)

        if ok and type(playersOrErr) == "table" and #playersOrErr > 0 then
            local now = os.epoch("utc")
            if now - lastPlayMs >= PRESENCE_COOLDOWN_MS then
                print("Player detected nearby, playing presence sound")
                playPresenceSound()
                lastPlayMs = now
            end
        end

        sleep(0.5)
    end
end

-------------------------------------------------
-- Chat command loop
-------------------------------------------------
local function chatLoop()
    chat.sendMessage("Presence bot online! Use: !setpresence <url-to-.dfpwm>")

    while true do
        local eventType, playerName, message, playerId = os.pullEvent("chat")
        local raw = message
        local msg = raw:lower()

        -- Set presence sound (global, DFPWM only)
        if msg:sub(1, 12) == "!setpresence" then
            local url = raw:match("^!setpresence%s+(.+)$")
            if not url or url == "" then
                chat.sendMessage("Usage: !setpresence <url-to-.dfpwm>")
            else
                local lower = url:lower()
                if not lower:match("%.dfpwm") then
                    chat.sendMessage("Presence sound must be a .dfpwm file.")
                    chat.sendMessage("Convert any audio file here: https://music.madefor.cc/")
                    chat.sendMessage("After converting, upload the .dfpwm (e.g. to Discord) and paste the direct link.")
                else
                    chat.sendMessage("Downloading new presence sound...")
                    local ok, err = downloadPresenceSound(url)
                    if ok then
                        chat.sendMessage("Presence sound updated successfully!")
                    else
                        chat.sendMessage("Failed to download presence sound: " .. tostring(err))
                    end
                end
            end

        -- Optional: test presence sound manually
        elseif msg == "!testpresence" then
            chat.sendMessage("Playing presence sound test...")
            playPresenceSound()
        end
    end
end

-------------------------------------------------
-- Run both loops
-------------------------------------------------
parallel.waitForAny(chatLoop, presenceLoop)
