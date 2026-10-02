-- Shared GUI evidence for joining, movement, troops, and match completion.
local function getGameScreen(name)
    local playerGui = player:FindFirstChild("PlayerGui")
    return playerGui and playerGui:FindFirstChild(name)
end

local function isGameScreenEnabled(name)
    local screen = getGameScreen(name)
    return screen ~= nil and screen:IsA("ScreenGui") and screen.Enabled
end

local function getMatchUI()
    return getGameScreen("MatchUI")
end

local function getSupplyMenu()
    local matchUI = getMatchUI()
    return matchUI and matchUI:FindFirstChild("SupplyPoint")
end

local function getSupplyAction()
    local menu = getSupplyMenu()
    local button = menu and menu:FindFirstChild("Spawn")
    local label = button and button:FindFirstChild("Text")
    return label and label.Text:gsub("<[^>]->", ""):match("^%s*(.-)%s*$") or nil
end

local function isTroopSpawnInProgress()
    if getSupplyAction() == "Cancel" then return true, true end
    local matchUI = getMatchUI()
    local spawn = matchUI and matchUI:FindFirstChild("SpawnTroops")
    local text = spawn and spawn:FindFirstChild("Text")
    local progress = spawn and spawn:FindFirstChild("SpawnProgress")
    return (text and text.Visible) or (progress and progress.Visible) or false,
        text ~= nil and progress ~= nil
end

local function isPlayerRespawning()
    return not player:FindFirstChild("PlayerGui")
        or isGameScreenEnabled("Death") or isGameScreenEnabled("Spawn")
end

local function isTransitionOverlayActive()
    local screen = getGameScreen("Transition")
    if not screen or not screen.Enabled then return false end
    local frame = screen:FindFirstChild("Frame")
    if not frame then return true end -- Rebuilding; do not authorize movement.
    if not frame.Visible then return false end
    local camera = workspace.CurrentCamera
    if not camera then return true end
    -- The audit keeps Transition.Enabled=true with its frame offscreen.
    local inset = GuiService:GetGuiInset()
    local position, size = frame.AbsolutePosition, frame.AbsoluteSize
    return size.X > 0 and size.Y > 0
        and position.X + size.X > -inset.X and position.Y + size.Y > -inset.Y
        and position.X < camera.ViewportSize.X - inset.X
        and position.Y < camera.ViewportSize.Y - inset.Y
end

local function hasEnteredMatchLifecycle()
    return isGameScreenEnabled("MatchUI") or isGameScreenEnabled("Spawn")
        or isGameScreenEnabled("Death")
end

local function getGamePhase()
    if isGameScreenEnabled("MatchResult") then return "RESULT" end
    -- These audited modals have their own input flow; they are not Continue.
    if isGameScreenEnabled("LevelUp") or isGameScreenEnabled("Summon") then return "OVERLAY" end
    if isTransitionOverlayActive() then return "TRANSITION" end
    if isGameScreenEnabled("Death") then return "DEATH" end
    if isGameScreenEnabled("Spawn") then return "SPAWN" end
    if isGameScreenEnabled("PickTeam") then return "PICK_TEAM" end
    if isGameScreenEnabled("MatchUI") then return "MATCH" end
    if isGameScreenEnabled("HUD") then return "LOBBY" end
    return "UNKNOWN"
end

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
    -- An arbitrary streamed child is not evidence that a map is ready.
    return nil
end

local function getActiveMapName()

    local map = getActiveMapModel()

    return map and map.Name or nil

end

-- A completed map can linger while its result/return UI is processing.
local function getJoinableMap()
    local map = getActiveMapModel()
    return map ~= STATE.finishedMap and map or nil
end

-- Detects whether the real character is currently

-- standing in the lobby or inside the active map.

local function getCurrentArea(gamePhase)
    gamePhase = gamePhase or getGamePhase()
    if gamePhase == "RESULT" then return "RESULT" end
    if gamePhase == "TRANSITION" or gamePhase == "OVERLAY" or gamePhase == "PICK_TEAM"
        or gamePhase == "SPAWN" or gamePhase == "DEATH" then return "TRANSITION" end
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
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local gamePhase = getGamePhase()
    local location = STATE.location
    if location and location.map == map and location.character == character and location.root == root
        and location.gamePhase == gamePhase and now < location.nextCheckAt then
        return location.confirmed, map, location.raw
    end
    local area = getCurrentArea(gamePhase)
    if not location or location.map ~= map or location.character ~= character or location.root ~= root
        or location.gamePhase ~= gamePhase or location.raw ~= area then
        location = { map = map, character = character, root = root, gamePhase = gamePhase, raw = area, since = now }
        STATE.location = location
    end
    location.nextCheckAt = now + CONFIG.ActiveMapCheckInterval
    location.confirmed = nil
    if (area == "LOBBY" or (map and area == map.Name))
        and now - location.since >= CONFIG.AreaConfirmTime then
        location.confirmed = area
    end
    -- Unknown/transitional positions never authorize lobby or troop actions.
    return location.confirmed, map, area
end

local function isMatchContext(map)
    if not STATE.enabled or not map then return false end
    if getGamePhase() ~= "MATCH" then return false end
    local character = player.Character
    local humanoid = character and character:FindFirstChild("Humanoid")
    if not humanoid or humanoid.Health <= 0 or not character:FindFirstChild("HumanoidRootPart") then
        return false
    end
    local area, currentMap = getLocation()
    return currentMap == map and area == map.Name
end

--==================================================

-- Camp movement must not compete with supply interaction or native spawning.
local function isCampInteractionActive()
    local menu = getSupplyMenu()
    return STATE.pendingSlot ~= nil or isTroopSpawnInProgress() or (menu and menu.Visible) or false
end

local function canNavigateCamp(map)
    return CONFIG.AutoCamp and isMatchContext(map) and not isCampInteractionActive()
end

