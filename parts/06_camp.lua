-- SUPPLY

--==================================================

local function getSuppliesFolder()

    local map =

        getActiveMapModel()

    if not map then

        return nil

    end

    local interactable =

        map:FindFirstChild(

            "Interactable"

        )

    return interactable

        and interactable:FindFirstChild(

            "Supplies"

        )

        or nil

end

local function getTeamSupplyPrefix()

    local team =

        getCurrentTeam()

    if team == "Attackers" then

        return "AttackerSupply"

    end

    if team == "Defenders" then

        return "DefenderSupply"

    end

    return nil

end

local function getCapturePoint(supply)

    local point =

        supply:FindFirstChild(

            "CapturePoint"

        )

    if

        point

        and point:IsA("BasePart")

    then

        return point

    end

    return nil

end

local function getSupplyPrompt(supply)

    local point =

        getCapturePoint(supply)

    if not point then

        return nil

    end

    return point:FindFirstChildWhichIsA(

        "ProximityPrompt",

        true

    )

end

local function getPromptPosition(prompt)

    local parent = prompt.Parent

    if parent:IsA("Attachment") then

        return parent.WorldPosition

    end

    if parent:IsA("BasePart") then

        return parent.Position

    end

    return nil

end

local function isInsideSupplyCamp(supply)
    local map = getActiveMapModel()
    local character = player.Character
    if not supply or not map or not supply:IsDescendantOf(map)
        or not character or not character:FindFirstChild("HumanoidRootPart")
        or not isMatchContext(map) then return false end

    local point = getCapturePoint(supply)

    if not point then
        return false
    end

    -- Check the player's REAL current position against this exact
    -- CapturePoint every time this function is called.
    -- X/Z is intentional: CapturePoint is often a thin floor part,
    -- while HumanoidRootPart sits several studs above it.
    local localPosition = point.CFrame:PointToObjectSpace(
        getRoot().Position
    )

    local half = point.Size / 2
    local margin = 1

    local marginX = math.min(margin, half.X * 0.15)
    local marginZ = math.min(margin, half.Z * 0.15)
    local maxX = half.X - marginX
    local maxZ = half.Z - marginZ

    -- CapturePoint is often a thin floor part, so allow the root to be
    -- several studs above it while still requiring the real X/Z footprint.
    local maxY = half.Y + 6

    return math.abs(localPosition.X) <= maxX
        and math.abs(localPosition.Z) <= maxZ
        and math.abs(localPosition.Y) <= maxY
end

-- Prefer the camp we are already physically standing in.

local function getCurrentTeamCamp()

    local supplies =

        getSuppliesFolder()

    local prefix =

        getTeamSupplyPrefix()

    if not supplies or not prefix then

        return nil

    end

    for _, supply in ipairs(

        supplies:GetChildren()

    ) do

        if

            supply.Name:sub(

                1,

                #prefix

            ) == prefix

            and isInsideSupplyCamp(

                supply

            )

        then

            return supply

        end

    end

    return nil

end

-- Finds the team supply with the shortest actual route.

local function getBestTeamSupply()
    local supplies,prefix=getSuppliesFolder(),getTeamSupplyPrefix()
    if not supplies then return nil,"NO_SUPPLIES" end
    if not prefix then return nil,"NO_TEAM" end
    if CONFIG.CampMode=="Selected" then
        local selected=supplies:FindFirstChild(CONFIG.SelectedCamp)
        if selected and selected.Name:sub(1,#prefix)==prefix and getCapturePoint(selected) then return selected,0 end
        return nil,"SELECTED_CAMP_UNAVAILABLE"
    end
    local currentCamp=getCurrentTeamCamp()
    if currentCamp then return currentCamp,0 end
    local bestSupply,bestDistance=nil,math.huge
    for _,supply in ipairs(supplies:GetChildren()) do
        if supply.Name:sub(1,#prefix)==prefix then
            local prompt=getSupplyPrompt(supply)
            if prompt and prompt.Enabled then
                local target=getPromptPosition(prompt)
                if target then
                    local distance
                    if CONFIG.MovementMode=="TP" then distance=(getRoot().Position-target).Magnitude
                    else
                        local path,_,routeDistance=computePath(target)
                        distance=routeDistance
                        if path then path:Destroy() end
                    end
                    if distance and distance<bestDistance then bestSupply,bestDistance=supply,distance end
                end
            end
        end
    end
    if not bestSupply then return nil,"NO_REACHABLE_SUPPLY" end
    return bestSupply,bestDistance
end

-- Physically enters the exact CapturePoint.

local function runIntoSupplyCamp(supply)
    local map = getActiveMapModel()
    if not CONFIG.AutoCamp then return false, "AUTO_CAMP_OFF" end
    local movementMode = CONFIG.MovementMode
    if not CONFIG.AutoCamp or not isMatchContext(map) then return false, "LOCATION_CHANGED" end

    if isInsideSupplyCamp(supply) then

        return true

    end

    local prompt =

        getSupplyPrompt(supply)

    local point =

        getCapturePoint(supply)

    if not point then

        return false,

            "NO_CAPTURE_POINT"

    end

    local target =

        prompt

        and getPromptPosition(prompt)

        or point.Position

    -- TP lands in the camp footprint; the prompt may be mounted off to its side.
    if movementMode == "TP" then target = point.Position end

    local reached, reason =

        runToPosition(target)

    if not reached then

        return false, reason

    end

    if isInsideSupplyCamp(supply) then

        return true

    end

    if movementMode == "TP" then return false, "TP_OUTSIDE_CAMP" end
    -- Final precise movement into the trigger volume.

    local startedAt = os.clock()

    while

        STATE.enabled

        and os.clock() - startedAt

            < CONFIG.CampEnterTimeout

    do
        if not CONFIG.AutoCamp or not isMatchContext(map) then
            stopMovement()
            return false, "LOCATION_CHANGED"
        end

        if isInsideSupplyCamp(supply) then

            stopMovement()

            return true

        end

        local offset =

            point.Position

            - getRoot().Position

        local direction = Vector3.new(

            offset.X,

            0,

            offset.Z

        )

        if direction.Magnitude > 0.1 then

            getHumanoid():Move(

                direction.Unit,

                false

            )

        end

        RunService.RenderStepped:Wait()

    end

    stopMovement()

    return false,

        "NOT_INSIDE_CAMP"

end

--==================================================

