local chat = peripheral.wrap("back")

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

    -- Amogus trigger
    elseif msg:find("amogus") then
        chat.sendMessage(playerName .. " said amogus...")

        local token = getPlayerAuthToken(playerId)
        if not token then
            chat.sendMessage("No token saved! Use: !settoken <token>")
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
        chat.sendMessage("shocked!")
    end

    ::continue::
end
