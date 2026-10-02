-- LOBBY VOTING

--==================================================

local function normalizeMapName(text)
    return (tostring(text or "")
        :gsub("<[^>]*>", "")
        :gsub("&nbsp;", " ")
        :gsub("\194\160", " ")
        :gsub("%s+", " ")
        :gsub("^%s+", "")
        :gsub("%s+$", "")
        :upper())
end

local function getMapVote()
    local lobby = workspace:FindFirstChild("Lobby")
    local interactable = lobby and lobby:FindFirstChild("Interactable")
    return interactable and interactable:FindFirstChild("MapVote") or nil
end

local function getVoteChoices()
    local mapVote = getMapVote()
    local choices = {}
    if not mapVote then return choices, false end
    local displays = {}
    local padCount = 0
    for _, child in ipairs(mapVote:GetChildren()) do
        local index = tonumber(child.Name:match("^Map(%d+)$"))
        if index then table.insert(displays, {index = index, display = child}) end
        if child.Name:match("^Choice%d+$") and getVotePart(child) then padCount += 1 end
    end
    table.sort(displays, function(a, b) return a.index < b.index end)
    local ready = #displays > 0 and (padCount == 0 or #displays >= padCount)
    local validCount = 0
    for _, entry in ipairs(displays) do
        local label = entry.display:FindFirstChild("MapName", true)
        local choice = mapVote:FindFirstChild("Choice" .. entry.index)
        local name = label and (label:IsA("TextLabel") or label:IsA("TextButton"))
            and normalizeMapName(label.Text) or ""
        if name ~= "" and name ~= "LOADING" and name ~= "LOADING..."
            and name ~= "?" and name ~= "???" and getVotePart(choice) then
            validCount += 1
            if not choices[name] then choices[name] = choice end
        else
            ready = false
        end
    end
    if padCount > 0 and validCount < padCount then ready = false end
    return choices, ready
end

local function getBestVote()
    local choices, ready = getVoteChoices()
    local preferences = STATE.lobbyPreferences or {
        priority=CONFIG.MapPriority, enabled=CONFIG.MapEnabled, fallback=CONFIG.MapFallback,
    }
    for _, preferred in ipairs(preferences.priority) do
        local name=normalizeMapName(preferred)
        if preferences.enabled[name]~=false and choices[name] then return name, choices[name], ready end
    end
    if preferences.fallback=="Wait" then return nil, nil, ready end
    local bestName, bestChoice, bestIndex
    for name, choice in pairs(choices) do
        local index=tonumber(choice.Name:match("^Choice(%d+)$")) or math.huge
        if preferences.enabled[name]~=false and (not bestIndex or index<bestIndex) then
            bestName,bestChoice,bestIndex=name,choice,index
        end
    end
    return bestName,bestChoice,ready
end

local function waitForBestVote()
    local startedAt = os.clock()
    local lastName, lastChoice, stableSince
    while STATE.enabled and os.clock() - startedAt < CONFIG.VoteSearchTimeout do
        if not CONFIG.AutoVote then return nil, nil, "AUTO_VOTE_OFF" end
        if getGamePhase() ~= "LOBBY" or getCurrentArea() ~= "LOBBY" then
            return nil, nil, "LOCATION_CHANGED"
        end
        if getJoinableMap() then return nil, nil, "ROUND_STARTED" end
        local mapName, choice, ready = getBestVote()
        if mapName and ready then
            if mapName ~= lastName or choice ~= lastChoice then
                stableSince = os.clock()
                lastName, lastChoice = mapName, choice
            end
            if os.clock() - stableSince >= CONFIG.VoteStableTime then
                return mapName, choice
            end
        else
            lastName, lastChoice, stableSince = nil, nil, nil
        end
        task.wait(0.1)
    end
    if not STATE.enabled then return nil, nil, "STOPPED" end
    -- At the deadline, use any readable choice even if other slots are missing.
    local mapName, choice = getBestVote()
    if mapName then return mapName, choice end
    return nil, nil, "VOTE_BOARD_TIMEOUT"
end

local function voteBestMap()
    if not CONFIG.AutoVote then return false, "AUTO_VOTE_OFF" end
    if not STATE.enabled then return false, "STOPPED" end
    if getJoinableMap() then return true, "ROUND_STARTED" end
    if getCurrentArea() ~= "LOBBY" then return false, "LOCATION_CHANGED" end
    local choicesNow = getVoteChoices()
    local boardReadable = next(choicesNow) ~= nil
    local shouldRequestPlay = not boardReadable and not STATE.lobbyPlayRequested
    if shouldRequestPlay then
        local fired, fireError = pcall(function()
            LobbyTeleportRequest:FireServer(CONFIG.LobbyMarker)
        end)
        if not fired then return false, "PLAY_REMOTE_ERROR: " .. tostring(fireError) end
        STATE.lobbyPlayRequested = true
        if not waitSeconds(CONFIG.PostTeleportDelay) then return false, "STOPPED" end
    end
    local lastReason = "VOTE_BOARD_TIMEOUT"
    for attempt = 1, CONFIG.VoteRetries do
        local mapName, choice, reason = waitForBestVote()
        if reason == "ROUND_STARTED" then return true, reason end
        if not mapName then return false, reason end
        setStatus("Voting", mapName .. " | attempt " .. attempt)
        local reached, moveReason = withControlsDisabled(function()
            return moveToObject(choice, function()
                local currentName, currentChoice = getBestVote()
                return currentName == mapName and currentChoice == choice
            end)
        end)
        if reached then
            return true, moveReason == "ROUND_STARTED" and moveReason or mapName, choice
        end
        lastReason = moveReason
        if not STATE.enabled then return false, "STOPPED" end
        if getJoinableMap() then return true, "ROUND_STARTED" end
        setStatus("Vote retry", tostring(lastReason))
        if not waitSeconds(0.25) then return false, "STOPPED" end
    end
    return false, lastReason
end

--==================================================

-- JOIN MATCH

--==================================================

-- The main worker polls this operation. A timeout cannot turn UNKNOWN or
-- player spawning into permission to send another TeamRequest.
local function joinMatch(map)
    if not CONFIG.AutoJoin then return false, "AUTO_JOIN_OFF" end
    if not STATE.enabled then return false, "STOPPED" end
    if not map or getActiveMapModel() ~= map then return false, "MAP_LOADING" end
    local phase = getGamePhase()
    if phase == "RESULT" then return false, "ROUND_ENDED" end
    if map == STATE.finishedMap and phase ~= "PICK_TEAM" then return false, "WAITING_FOR_NEXT_ROUND" end
    if phase == "PICK_TEAM" then STATE.finishedMap = nil end

    local request = STATE.joinRequest
    if hasEnteredMatchLifecycle() then
        if request then request.accepted = true end
        STATE.roundTeam = getCurrentTeam() or (request and request.team)
        return true, "MATCH_LIFECYCLE_ENTERED"
    end
    if request then
        if request.map ~= map then
            STATE.joinRequest = nil
            return false, "JOIN_MAP_CHANGED"
        end
        -- Only a confirmed lobby, with no lifecycle/transition UI, can
        -- establish rejection/return. PickTeam may remain up during a join.
        local area = getLocation()
        if phase == "LOBBY" and area == "LOBBY" then
            request.lobbySince = request.lobbySince or os.clock()
            if os.clock() - request.sentAt >= CONFIG.JoinTimeout
                and os.clock() - request.lobbySince >= CONFIG.AreaConfirmTime then
                STATE.joinRequest = nil
                return false, "JOIN_RETURNED_TO_LOBBY"
            end
        else
            request.lobbySince = nil
        end
        setStatus("Joining team", request.team .. " | waiting for game state")
        return true, "JOIN_PENDING"
    end

    if phase ~= "PICK_TEAM" and (phase ~= "LOBBY" or getCurrentArea() ~= "LOBBY") then
        return true, "JOIN_TRANSITION"
    end
    local team = CONFIG.Team
    if team ~= "Attackers" and team ~= "Defenders" then return false, "INVALID_TEAM" end
    request = {map=map, team=team, sentAt=os.clock()}
    STATE.joinRequest = request
    STATE.roundTeam = team -- UI changes apply to the next request only.
    setStatus("Joining team", team .. " | waiting for game state")
    local fired, fireError = pcall(function() TeamRequest:FireServer(team) end)
    if not fired then
        STATE.joinRequest = nil
        return false, "TEAM_REMOTE_ERROR: " .. tostring(fireError)
    end
    return true, "JOIN_PENDING"
end

local function runLobbyFlow()
    local area, map = getLocation()
    if area ~= "LOBBY" then return false, "LOCATION_CHANGED" end
    if map and map ~= STATE.finishedMap then
        if not CONFIG.AutoJoin then setStatus("Lobby", "Auto join is OFF"); return true end
        -- An active round can be joined without replaying the lobby teleport.
        return joinMatch(map)
    end
    if not CONFIG.AutoVote then setStatus("Lobby", "Auto vote is OFF"); return true end
    local mapName, choice = getBestVote()
    local character = player.Character
    local humanoid = character and character:FindFirstChild("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local part = getVotePart(choice)
    if STATE.lobbyVoteName == mapName and STATE.lobbyVoteChoice == choice
        and part and part.Parent and root and humanoid
        and isOnVotePart(root, humanoid, part) then
        setStatus("Waiting for map", "On vote pad: " .. mapName)
        return true
    end
    local ok, reason, votedChoice = voteBestMap()
    if ok and reason ~= "ROUND_STARTED" then
        STATE.lobbyVoteName = reason
        STATE.lobbyVoteChoice = votedChoice
        setStatus("On vote pad", reason)
    end
    return ok, reason
end

--==================================================

