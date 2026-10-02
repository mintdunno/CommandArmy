-- ACTIVE MAP / AREA

--==================================================

local function getActiveMapModel()
    local activeMap = workspace:FindFirstChild("ActiveMap")
    if not activeMap then return nil end
    local children = activeMap:GetChildren()
    for _, child in ipairs(children) do
        local interactable = child:FindFirstChild("Interactable")
        if interactable and interactable:FindFirstChild("Supplies") then return child end
    end
    for _, child in ipairs(children) do
        if child:FindFirstChild("Interactable") then return child end
    end
    for _, child in ipairs(children) do
        if child:IsA("Model") then return child end
    end
    return children[1]
end

local function getActiveMapName()

    local map = getActiveMapModel()

    return map and map.Name or nil

end

-- Detects whether the real character is currently

-- standing in the lobby or inside the active map.

local function getCurrentArea()
    if STATE.continueVisible then return "UNKNOWN" end
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then return "UNKNOWN" end
    local lobby = workspace:FindFirstChild("Lobby")
    local map = getActiveMapModel()
    local excluded = { character }
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.RespectCanCollide = true
    -- Ignore non-collidable triggers/VFX and find the actual floor.
    for _ = 1, 8 do
        params.FilterDescendantsInstances = excluded
        local result = workspace:Raycast(root.Position, Vector3.new(0, -500, 0), params)
        if not result then return "UNKNOWN" end
        local hit = result.Instance
        local rig
        local ancestor = hit.Parent
        while ancestor and ancestor ~= workspace do
            if ancestor:IsA("Model") and (ancestor:FindFirstChildWhichIsA("Humanoid")
                or ancestor:FindFirstChildWhichIsA("AnimationController")) then
                rig = ancestor
                break
            end
            ancestor = ancestor.Parent
        end
        if rig then
            table.insert(excluded, rig)
        else
            if lobby and hit:IsDescendantOf(lobby) then return "LOBBY" end
            if map and hit:IsDescendantOf(map) then return map.Name end
            return "UNKNOWN"
        end
    end
    return "UNKNOWN"
end

local function getLocation()
    if STATE.continueVisible then return nil, getActiveMapModel(), "UNKNOWN" end
    local now = os.clock()
    local map = getActiveMapModel()
    local character = player.Character
    local location = STATE.location
    if location and location.map == map and location.character == character
        and now < location.nextCheckAt then
        return location.confirmed, map, location.raw
    end
    local area = getCurrentArea()
    if not location or location.map ~= map or location.character ~= character
        or location.raw ~= area then
        location = { map = map, character = character, raw = area, since = now }
        STATE.location = location
    end
    location.nextCheckAt = now + CONFIG.ActiveMapCheckInterval
    location.confirmed = nil
    if area ~= "UNKNOWN" and now - location.since >= CONFIG.AreaConfirmTime then
        location.confirmed = area
    end
    -- Unknown/transitional positions never authorize lobby or troop actions.
    return location.confirmed, map, area
end

local function isMatchContext(map)
    if not STATE.enabled or not map then return false end
    local area, currentMap = getLocation()
    return currentMap == map and area == map.Name
end

--==================================================

