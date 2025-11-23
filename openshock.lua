local chat = peripheral.wrap("back")
local monitor = peripheral.wrap("left")
local speaker = peripheral.wrap("top")

monitor.clear()
monitor.setCursorPos(0,0)
monitor.write("Chaos is STINKY!")

-------------------------------------------------
-- Player config (players.json)
-------------------------------------------------
local PLAYERS_CONFIG_PATH = "/players.json"
local players = {}

local function loadPlayers()
    if not fs.exists(PLAYERS_CONFIG_PATH) then
        players = {}
        return
    end

    local file = fs.open(PLAYERS_CONFIG_PATH, "r")
    if not file then
        print("Failed to open players.json for reading")
        players = {}
        return
    end

    local data = file.readAll()
    file.close()

    local ok, parsed = pcall(textutils.unserializeJSON, data)
    if ok and parsed then
        players = parsed
    else
        print("players.json corrupted, resetting")
        players = {}
    end
end

local function savePlayers()
    local json = textutils.serializeJSON(players)
    local file = fs.open(PLAYERS_CONFIG_PATH, "w")
    if not file then
        print("Failed to open players.json for writing")
        return
    end
    file.write(json)
    file.close()
end

local function setPlayerAuthToken(playerId, authToken)
    if not players[playerId] then players[playerId] = {} end
    players[playerId].authtoken = authToken
    savePlayers()
end

local function getPlayerAuthToken(playerId)
    return players[playerId] and players[playerId].authtoken or nil
end

local function updateCachedShockers(playerId, shockerIds)
    if not players[playerId] then players[playerId] = {} end
    players[playerId].shockers = shockerIds
    savePlayers()
end

local function getCachedShockers(playerId)
    if players[playerId] and players[playerId].shockers then
        return players[playerId].shockers
    end
    return nil
end

-- Load player config on startup
loadPlayers()

-------------------------------------------------
-- Shock sound config (global)
-------------------------------------------------
local SHOCK_SOUND_PATH = "/shock_sound.dfpwm"
local dfpwm = require("cc.audio.dfpwm")

local function downloadShockSound(url)
    local h, err = http.get(url, nil, true) -- binary
    if not h then
        return false, "HTTP GET failed: " .. tostring(err)
    end

    local f = fs.open(SHOCK_SOUND_PATH, "wb")
    if not f then
        h.close()
        return false, "Failed to open sound file for writing"
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

local function playShockSound()
    if not fs.exists(SHOCK_SOUND_PATH) then
        -- No sound configured, silently ignore
        return
    end

    local file = fs.open(SHOCK_SOUND_PATH, "rb")
    if not file then
        print("Failed to open shock sound file")
        return
    end

    local decoder = dfpwm.make_decoder()

    while true do
        local chunk = file.read(16 * 1024)
        if not chunk then break end

        local buffer = decoder(chunk)
        speaker.playAudio(buffer)

        -- assume 48000 Hz mono, 1 byte/sample
        local seconds = #buffer / 48000
        if seconds > 0 then
            sleep(seconds)
        end
    end

    file.close()
end

-------------------------------------------------
-- OpenShock logic
-------------------------------------------------

-- Fetch user shockers and cache them
local function fetchShockers(userToken, playerId)
    local resp = http.get(
        "https://api.openshock.app/1/shockers/own",
        { ["OpenShockToken"] = userToken }
    )

    if not resp then
        print("Failed to fetch shockers for token")
        return nil
    end

    local parsed = textutils.unserializeJSON(resp.readAll())
    resp.close()

    if not parsed or not parsed.data then return nil end

    local ids = {}
    for _, entry in ipairs(parsed.data) do
        if entry.shockers then
            for _, s in ipairs(entry.shockers) do
                table.insert(ids, s.id)
            end
        end
    end

    updateCachedShockers(playerId, ids)
    return ids
end

-- Send vibration to ALL cached shockers of that player
local function vibrateShockers(userToken, shockers)
    if not shockers or #shockers == 0 then
        print("No cached shockers to vibrate")
        return
    end

    local list = {}
    for _, id in ipairs(shockers) do
        table.insert(list, {
            id = id,
            type = "Vibrate",
            intensity = 100,
            duration = 500,
            exclusive = true
        })
    end

    local payload = textutils.serializeJSON({ shocks = list })

    local resp = http.post(
        "https://api.openshock.app/2/shockers/control",
        payload,
        {
            ["Content-Type"] = "application/json",
            ["OpenShockToken"] = userToken,
            ["User-Agent"] = "ComputerCraftTweaked"
        }
    )

    if resp then
        print("Shock response:", resp.readAll())
        resp.close()
    end
end

-------------------------------------------------
-- Chat loop
-------------------------------------------------

while true do
    local eventType, playerName, message, playerId = os.pullEvent("chat")
    local raw = message
    local msg = raw:lower()

    -- Player sets their token
    if msg:sub(1, 9) == "!settoken" then
        local tokenValue = raw:match("^!settoken%s+(.+)$")
        if not tokenValue or tokenValue == "" then
            chat.sendMessage("Usage: !settoken <token>")
        else
            setPlayerAuthToken(playerId, tokenValue)
            chat.sendMessage("Saved token for " .. playerName)

            -- Immediately fetch and cache shockers
            local ids = fetchShockers(tokenValue, playerId)
            if ids then
                chat.sendMessage("Cached " .. #ids .. " shockers for " .. playerName)
            else
                chat.sendMessage("Failed to fetch shockers for that token.")
            end
        end

    -- Set global shock sound (DFPWM only)
    elseif msg:sub(1, 9) == "!setsound" then
        local url = raw:match("^!setsound%s+(.+)$")
        if not url or url == "" then
            chat.sendMessage("Usage: !setsound <url-to-.dfpwm>")
        else
            local lower = url:lower()
            if not lower:match("%.dfpwm") then
                chat.sendMessage("Shock sound must be in .dfpwm format.")
                chat.sendMessage("Go to https://music.madefor.cc/ to convert your audio,")
                chat.sendMessage("upload the .dfpwm (e.g. to Discord) and paste the direct link here.")
            else
                chat.sendMessage("Downloading new shock sound...")
                local ok, err = downloadShockSound(url)
                if ok then
                    chat.sendMessage("Shock sound updated successfully!")
                else
                    chat.sendMessage("Failed to download shock sound: " .. tostring(err))
                end
            end
        end

    -- Amogus trigger
    elseif msg:find("amogus") then
        chat.sendMessage(playerName .. " said amogus...")

        local token = getPlayerAuthToken(playerId)
        if not token then
            chat.sendMessage(playerName .. ", you haven't set your OpenShock token yet!")
            chat.sendMessage("Paste your token using: !settoken <your_token_here>")
            goto continue
        end

        -- Try cached shockers
        local ids = getCachedShockers(playerId)

        -- If no cache, fetch once
        if not ids then
            chat.sendMessage("Fetching your shockers for the first time...")
            ids = fetchShockers(token, playerId)
            if not ids then
                chat.sendMessage("Failed to get your shockers.")
                goto continue
            end
        end

        -- Vibrate the cached shockers
        vibrateShockers(token, ids)

        -- Play global shock sound if configured
        playShockSound()

        chat.sendMessage("shocked!")
    end

    ::continue::
end
