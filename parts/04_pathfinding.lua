-- PATHFINDING

--==================================================

-- Identify NPC rigs structurally, without assuming game-specific troop folders.
-- Player characters and map geometry are not modified.
local function getTroopRig(object)
    local current = object
    while current and current ~= workspace do
        if current:IsA("Model") then
            if current == player.Character or Players:GetPlayerFromCharacter(current) then
                return nil
            end
            local humanoid = current:FindFirstChildWhichIsA("Humanoid")
            local animator = current:FindFirstChildWhichIsA("AnimationController")
            local rootPart = current:FindFirstChild("HumanoidRootPart")
                or current.PrimaryPart
            if humanoid or (animator and rootPart) then return current end
        end
        current = current.Parent
    end
    return nil
end

local function releaseTroopPathPart(part)
    local record = STATE.troopPathModifiers[part]
    if not record then return end
    STATE.troopPathModifiers[part] = nil
    pcall(function()
        if record.created then
            record.modifier:Destroy()
        elseif record.modifier.Parent and record.modifier.PassThrough then
            record.modifier.PassThrough = record.oldPassThrough
        end
    end)
end

local function ignoreTroopPathPart(part)
    if not part:IsA("BasePart") or STATE.troopPathModifiers[part] then return end
    local modifier = part:FindFirstChildWhichIsA("PathfindingModifier")
    local created = modifier == nil
    if created then modifier = Instance.new("PathfindingModifier") end
    STATE.troopPathModifiers[part] = {
        modifier = modifier,
        created = created,
        oldPassThrough = modifier.PassThrough,
    }
    modifier.PassThrough = true
    if created then
        modifier.Name = "CommandArmyTroopPassThrough"
        modifier.Parent = part
    end
end

local function stopTroopPathFilter()
    for _, connection in ipairs(STATE.troopPathConnections) do connection:Disconnect() end
    table.clear(STATE.troopPathConnections)
    -- Disconnect first: destroying owned modifiers also fires descendant events.
    for part in pairs(STATE.troopPathModifiers) do releaseTroopPathPart(part) end
end

local function startTroopPathFilter()
    stopTroopPathFilter()
    if not CONFIG.IgnoreTroopsInPathfinding then return end
    local function refreshRig(rig)
        for _, part in ipairs(rig:GetDescendants()) do
            if part:IsA("BasePart") and part.CanCollide then ignoreTroopPathPart(part) end
        end
    end
    local function onAdded(object)
        if not STATE.enabled then return end
        if object:IsA("Humanoid") or object:IsA("AnimationController") then
            local rig = getTroopRig(object)
            if rig then refreshRig(rig) end
        elseif object:IsA("BasePart") then
            local rig = getTroopRig(object)
            if rig then
                if object.Name == "HumanoidRootPart" then refreshRig(rig)
                elseif object.CanCollide then ignoreTroopPathPart(object) end
            end
        end
    end
    table.insert(STATE.troopPathConnections, workspace.DescendantAdded:Connect(onAdded))
    table.insert(STATE.troopPathConnections, workspace.DescendantRemoving:Connect(function(object)
        if STATE.troopPathModifiers[object] then releaseTroopPathPart(object) end
    end))
    -- One initial scan. Spawned/streamed troops are handled by events thereafter.
    local seen = {}
    for _, object in ipairs(workspace:GetDescendants()) do
        if object:IsA("Humanoid") or object:IsA("AnimationController") then
            local rig = getTroopRig(object)
            if rig and not seen[rig] then
                seen[rig] = true
                refreshRig(rig)
            end
        end
    end
end

local function createPath()

    return PathfindingService:CreatePath({

        AgentRadius = CONFIG.AgentRadius,

        AgentHeight = CONFIG.AgentHeight,

        AgentCanJump =

            CONFIG.AgentCanJump,

        AgentCanClimb =

            CONFIG.AgentCanClimb,

        WaypointSpacing =

            CONFIG.WaypointSpacing,

    })

end

local function computePath(targetPosition)
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChild("Humanoid")
    local map, runId = getActiveMapModel(), STATE.runId
    if not root or not humanoid or humanoid.Health <= 0 or not isMatchContext(map) then
        return nil
    end
    local startPosition = root.Position

    local path = createPath()

    local success, computeError = pcall(function()

        path:ComputeAsync(

            startPosition,

            targetPosition

        )

    end)

    if STATE.runId ~= runId or player.Character ~= character or not root.Parent
        or humanoid.Health <= 0 or not isMatchContext(map) then
        path:Destroy()
        return nil
    end
    if not success then
        path:Destroy()
        return nil, nil, nil, "PATH_COMPUTE_ERROR: " .. tostring(computeError)
    end

    if

        path.Status

            ~= Enum.PathStatus.Success

    then

        path:Destroy()
        return nil

    end

    local waypoints =

        path:GetWaypoints()

    if #waypoints == 0 then

        path:Destroy()
        return nil

    end

    local distance = 0

    local previous = startPosition

    for _, waypoint in ipairs(waypoints) do

        distance +=

            (

                waypoint.Position

                - previous

            ).Magnitude

        previous = waypoint.Position

    end

    return path, waypoints, distance

end

-- Uses actual Humanoid movement so the character

-- runs normally instead of tweening or sliding.

local function walkToWaypoint(position, isBlocked, stillValid)
    local character = player.Character
    local humanoid = character and character:FindFirstChild("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root then return false, "CHARACTER_NOT_READY" end
    local lastPosition = root.Position
    local startedAt = os.clock()
    local lastProgressAt = startedAt
    while STATE.enabled and humanoid.Health > 0 do
        if player.Character ~= character or not root.Parent then
            stopMovement()
            return false, "CHARACTER_CHANGED"
        end
        if stillValid and not stillValid() then
            stopMovement()
            return false, "ROUND_ENDED"
        end
        local offset = position - root.Position
        local direction = Vector3.new(offset.X, 0, offset.Z)
        if direction.Magnitude <= CONFIG.WaypointTolerance
            and math.abs(offset.Y) <= CONFIG.AgentHeight then
            stopMovement()
            return true
        end
        if (root.Position - lastPosition).Magnitude >= CONFIG.StuckDistance then
            lastPosition = root.Position
            lastProgressAt = os.clock()
        end
        -- Blocked is a hint, not a reason to abort while still making progress.
        -- Crowds can invalidate future waypoints for only a frame or two.
        local stalledFor = os.clock() - lastProgressAt
        if stalledFor >= CONFIG.BlockedGraceTime and isBlocked() then
            stopMovement()
            return false, "BLOCKED"
        end
        if stalledFor >= CONFIG.StuckTimeout then
            stopMovement()
            return false, "STUCK"
        end
        if os.clock() - startedAt >= CONFIG.WaypointTimeout then
            stopMovement()
            return false, "WAYPOINT_TIMEOUT"
        end
        if direction.Magnitude > 0.05 then humanoid:Move(direction.Unit, false) end
        RunService.RenderStepped:Wait()
    end
    stopMovement()
    return false, STATE.enabled and "DEAD" or "STOPPED"
end

local function runToPosition(targetPosition)
    local map = getActiveMapModel()
    if not CONFIG.AutoCamp then return false, "AUTO_CAMP_OFF" end
    if CONFIG.MovementMode == "TP" then
        if not canNavigateCamp(map) then return false, "LOCATION_CHANGED" end
        local ok, reason = teleportToPosition(targetPosition)
        if not ok then return false, reason end
        if not waitSeconds(0.25) then return false, "STOPPED" end
        if not canNavigateCamp(map) then return false, "LOCATION_CHANGED" end
        local character = player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if not root then return false, "CHARACTER_CHANGED" end
        local offset = root.Position-targetPosition
        if Vector3.new(offset.X,0,offset.Z).Magnitude > CONFIG.WaypointTolerance then
            return false, "TP_POSITION_NOT_CONFIRMED"
        end
        return true
    end
    local character = player.Character
    local campMode, selectedCamp, team = CONFIG.CampMode, CONFIG.SelectedCamp, getCurrentTeam()
    local function stillValid()
        return canNavigateCamp(map) and CONFIG.CampMode == campMode
            and CONFIG.SelectedCamp == selectedCamp and getCurrentTeam() == team
    end
    for attempt = 1, CONFIG.MaxRepaths do
        if not STATE.enabled then return false, "STOPPED" end
        if not stillValid() then return false, "ROUND_ENDED" end
        if player.Character ~= character then return false, "CHARACTER_CHANGED" end
        local humanoid = character and character:FindFirstChild("Humanoid")
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if not humanoid or not root or humanoid.Health <= 0 then
            return false, "CHARACTER_NOT_READY"
        end
        local path, waypoints, _, pathError = computePath(targetPosition)
        if not STATE.enabled or not stillValid() or player.Character ~= character then
            if path then path:Destroy() end
            return false, "MOVEMENT_CANCELLED"
        end
        if not path then return false, pathError or "NO_PATH" end
        local currentWaypoint = 1
        local blockedAt = {}
        local blockedConnection = path.Blocked:Connect(function(index)
            if index >= currentWaypoint then blockedAt[index] = blockedAt[index] or os.clock() end
        end)
        local unblockedConnection = path.Unblocked:Connect(function(index)
            blockedAt[index] = nil
        end)
        STATE.movementConnections[blockedConnection] = true
        STATE.movementConnections[unblockedConnection] = true
        local function releasePath()
            blockedConnection:Disconnect()
            unblockedConnection:Disconnect()
            STATE.movementConnections[blockedConnection] = nil
            STATE.movementConnections[unblockedConnection] = nil
            path:Destroy()
        end
        local repath = false
        -- Include a single-waypoint path; it must not imply arrival by itself.
        for i = (#waypoints > 1 and 2 or 1), #waypoints do
            currentWaypoint = i
            local waypoint = waypoints[i]
            if waypoint.Action == Enum.PathWaypointAction.Jump then humanoid.Jump = true end
            local reached, reason = walkToWaypoint(waypoint.Position, function()
                for index, since in pairs(blockedAt) do
                    if index >= currentWaypoint and index <= currentWaypoint + 1
                        and os.clock() - since >= CONFIG.BlockedGraceTime then return true end
                end
                return false
            end, stillValid)
            if not reached then
                if reason == "BLOCKED" or reason == "STUCK" or reason == "WAYPOINT_TIMEOUT" then
                    repath = true
                    break
                end
                releasePath()
                return false, reason
            end
        end
        releasePath()
        if not repath then return true end
        -- Avoid burning the entire repath budget on a brief moving obstruction.
        if not waitSeconds(math.min(attempt * 0.25, 1)) then return false, "STOPPED" end
    end
    return false, "TOO_MANY_REPATHS"
end

--==================================================

