-- MATCH LOOP

--==================================================

local function runMatchLoop(map)
    STATE.lastSlot = nil
    STATE.activeSlot = nil
    STATE.zeroSince = nil
    STATE.pendingSlot = nil
    STATE.pendingUntil = 0
    STATE.currentCamp = nil
    STATE.troopActive = false
    STATE.lastAttackAt = 0
    local selectionKey
    local selectedSupply
    local nextCampCheckAt = 0
    local wasInsideCamp = false

    while STATE.enabled and getActiveMapModel() == map do
        local area, currentMap = getLocation()
        if currentMap ~= map or area == "LOBBY" then break end
        if area ~= map.Name then
            stopMovement()
            STATE.troopActive = false
            setStatus("Checking location", "Waiting for map/lobby confirmation")
            waitSeconds(CONFIG.ActiveMapCheckInterval)
            continue
        end
        local character = player.Character
        local humanoid = character and character:FindFirstChild("Humanoid")
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if not humanoid or not root or humanoid.Health <= 0 then
            STATE.troopActive = false
            nextCampCheckAt = 0
            setStatus("Waiting for character", "Camp movement will resume after respawn")
            waitSeconds(CONFIG.CheckInterval)
            continue
        end
        local currentKey = tostring(CONFIG.AutoCamp) .. ":" .. CONFIG.CampMode .. ":" .. CONFIG.SelectedCamp
        if currentKey ~= selectionKey then
            selectionKey = currentKey
            selectedSupply = nil
            STATE.currentCamp = nil
            nextCampCheckAt = 0
            wasInsideCamp = false
        end
        if not CONFIG.AutoCamp and CONFIG.CampMode == "Nearest" then
            selectedSupply = getCurrentTeamCamp()
            STATE.currentCamp = selectedSupply
            if not selectedSupply then
                STATE.troopActive = false
                setStatus("Manual camp movement", "Enter a team camp to use auto troops")
            end
        end
        if selectedSupply and not selectedSupply:IsDescendantOf(map) then
            selectedSupply = nil
            STATE.currentCamp = nil
            nextCampCheckAt = 0
            wasInsideCamp = false
        end
        if not selectedSupply and (CONFIG.AutoCamp or CONFIG.CampMode == "Selected")
            and os.clock() >= nextCampCheckAt then
            local reason
            selectedSupply, reason = getBestTeamSupply()
            STATE.currentCamp = selectedSupply
            if not selectedSupply then
                setStatus("Waiting for camp", tostring(reason) .. " | retrying shortly")
                nextCampCheckAt = os.clock() + CONFIG.CampRetryDelay
            end
        end
        if not STATE.enabled or getActiveMapModel() ~= map then break end
        if selectedSupply then
            local inside = isInsideSupplyCamp(selectedSupply)
            if wasInsideCamp and not inside then nextCampCheckAt = 0 end
            if CONFIG.AutoCamp and not inside and os.clock() >= nextCampCheckAt then
                setStatus("Moving to camp", selectedSupply.Name)
                local entered, reason = withControlsDisabled(function()
                    return runIntoSupplyCamp(selectedSupply)
                end)
                if not STATE.enabled or getActiveMapModel() ~= map then break end
                if entered then
                    nextCampCheckAt = os.clock() + CONFIG.CampCheckInterval
                else
                    -- A failed route is recoverable; keep this camp and this match.
                    STATE.troopActive = false
                    setStatus("Camp retry", tostring(reason) .. " | retry in " .. CONFIG.CampRetryDelay .. "s")
                    nextCampCheckAt = os.clock() + CONFIG.CampRetryDelay
                end
                inside = isInsideSupplyCamp(selectedSupply)
            elseif inside and os.clock() >= nextCampCheckAt then
                nextCampCheckAt = os.clock() + CONFIG.CampCheckInterval
            end
            wasInsideCamp = inside
            if inside then
                local ok, reason = processTroopInsideCamp(selectedSupply)
                if not ok and reason ~= "NOT_INSIDE_CAMP" then
                    setStatus("Cycle error", reason)
                end
            end
        else
            wasInsideCamp = false
        end
        updateTroopAttack()
        waitSeconds(CONFIG.CheckInterval)
    end
    STATE.currentCamp = nil
    STATE.troopActive = false
    return true
end

--==================================================

-- MAIN AUTO LOOP

--==================================================

-- Dismiss the game's Continue screen through input, not by hiding its UI.
local function isContinueText(object)
    if not (object:IsA("TextLabel") or object:IsA("TextButton")) then return false end
    local text = object.Text:lower():gsub("<[^>]*>", "")
        :gsub("&nbsp;", ""):gsub("\194\160", ""):gsub("[%s%p]", "")
    return text:find("clickanywheretocontinue", 1, true) ~= nil
        or text:find("tapanywheretocontinue", 1, true) ~= nil
        or text:find("pressanywheretocontinue", 1, true) ~= nil
end

local function getContinueScreen(label)
    if not label.Parent or label:IsDescendantOf(gui) or not isContinueText(label)
        or label.TextTransparency >= 0.99 then return nil end
    if label.AbsoluteSize.X < 1 or label.AbsoluteSize.Y < 1 then return nil end
    local camera = workspace.CurrentCamera
    if not camera then return nil end
    local inset = GuiService:GetGuiInset()
    local left = math.max(label.AbsolutePosition.X, -inset.X)
    local top = math.max(label.AbsolutePosition.Y, -inset.Y)
    local right = math.min(label.AbsolutePosition.X + label.AbsoluteSize.X,
        camera.ViewportSize.X - inset.X)
    local bottom = math.min(label.AbsolutePosition.Y + label.AbsoluteSize.Y,
        camera.ViewportSize.Y - inset.Y)
    local ancestor = label
    while ancestor and ancestor ~= player.PlayerGui do
        if ancestor:IsA("GuiObject") and not ancestor.Visible then return nil end
        if ancestor:IsA("CanvasGroup") and ancestor.GroupTransparency >= 0.99 then return nil end
        if ancestor:IsA("GuiObject") and ancestor.ClipsDescendants then
            left = math.max(left, ancestor.AbsolutePosition.X)
            top = math.max(top, ancestor.AbsolutePosition.Y)
            right = math.min(right, ancestor.AbsolutePosition.X + ancestor.AbsoluteSize.X)
            bottom = math.min(bottom, ancestor.AbsolutePosition.Y + ancestor.AbsoluteSize.Y)
        end
        if right <= left or bottom <= top then return nil end
        if ancestor:IsA("ScreenGui") then
            return ancestor.Enabled and ancestor or nil
        end
        ancestor = ancestor.Parent
    end
    return nil
end

local function getContinueClickPoint(label, screen)
    local camera = workspace.CurrentCamera
    if not camera then return nil end
    local inset = GuiService:GetGuiInset()
    local position, size = label.AbsolutePosition, label.AbsoluteSize
    -- Try within the actual prompt; do not accidentally click our START/STOP UI.
    for _, fraction in ipairs({0.5, 0.25, 0.75}) do
        local guiPoint = position + Vector2.new(size.X * fraction, size.Y * 0.5)
        local screenPoint = guiPoint + inset
        local ownPosition, ownSize = main.AbsolutePosition, main.AbsoluteSize
        local overOwnPanel = gui.Enabled and main.Visible
            and guiPoint.X >= ownPosition.X and guiPoint.X <= ownPosition.X + ownSize.X
            and guiPoint.Y >= ownPosition.Y and guiPoint.Y <= ownPosition.Y + ownSize.Y
        if screenPoint.X >= 1 and screenPoint.Y >= inset.Y + 1
            and screenPoint.X < camera.ViewportSize.X - 1
            and screenPoint.Y < camera.ViewportSize.Y - 1 and not overOwnPanel then
            local hitLabel, obstructed = false, false
            -- Hit testing also rejects clipped/offscreen text that is still Visible.
            for _, hit in ipairs(player.PlayerGui:GetGuiObjectsAtPosition(guiPoint.X, guiPoint.Y)) do
                if hit == label then hitLabel = true; break end
                if hit:IsDescendantOf(gui)
                    or ((hit:IsA("GuiButton") or hit.Active)
                        and not label:IsDescendantOf(hit) and not hit:IsDescendantOf(label)
                        and not (hit:IsDescendantOf(screen) and not hit:IsA("GuiButton"))) then
                    obstructed = true
                    break
                end
            end
            if hitLabel and not obstructed then return screenPoint end
        end
    end
    return nil
end

local function releaseContinueClick()
    local release = STATE.continueRelease
    STATE.continueRelease = nil
    if release then pcall(release) end
end

local function stopContinueWatcher()
    local worker = STATE.continueWorker
    STATE.continueWorker = nil
    if worker and worker ~= coroutine.running() and coroutine.status(worker) ~= "dead" then
        pcall(task.cancel, worker)
    end
    releaseContinueClick()
    STATE.continueVisible = false
    STATE.location = nil
end

local function startContinueWatcher()
    stopContinueWatcher()
    local runId = STATE.runId
    local senders = {}
    local ok, virtualInput = pcall(function() return UserInputService:CreateVirtualInput() end)
    if ok and virtualInput then
        table.insert(senders, function(point, down)
            virtualInput:SendMouseButton(point, Enum.UserInputType.MouseButton1, down, 0)
        end)
    end
    local hasManager, manager = pcall(function() return game:GetService("VirtualInputManager") end)
    if hasManager and manager then
        table.insert(senders, function(point, down)
            manager:SendMouseButtonEvent(point.X, point.Y, 0, down, game, 0)
        end)
    end
    local nextClickAt, nextWarningAt = 0, 0
    local function scanAndDismiss()
        local prompt, point
        for _, object in ipairs(player.PlayerGui:GetDescendants()) do
            if isContinueText(object) then
                local screen = getContinueScreen(object)
                if screen then
                    -- Pause even if our panel currently covers all click points.
                    prompt = prompt or object
                    local candidate = getContinueClickPoint(object, screen)
                    if candidate then prompt, point = object, candidate; break end
                end
            end
        end
        local visible = prompt ~= nil
        if STATE.continueVisible ~= visible then STATE.location = nil end
        STATE.continueVisible = visible
        if not CONFIG.AutoContinue or not visible or not point or os.clock() < nextClickAt then return end
        -- Respect the user's typing/mouse input and Roblox menus.
        if GuiService.MenuIsOpen or UserInputService:GetFocusedTextBox()
            or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then return end
        if not STATE.enabled or STATE.runId ~= runId or not getContinueScreen(prompt) then return end
        nextClickAt = os.clock() + CONFIG.ContinueClickInterval
        stopMovement()
        for _, send in ipairs(senders) do
            local pressed = pcall(send, point, true)
            if pressed then
                STATE.continueRelease = function() send(point, false) end
                -- Allow InputBegan and button press to process before the release.
                task.wait(0.05)
                releaseContinueClick()
                return -- The next scan verifies whether the prompt actually closed.
            end
        end
        if os.clock() >= nextWarningAt then
            nextWarningAt = os.clock() + 10
            warn("[AUTO] Continue screen detected, but simulated click is unavailable; click it manually.")
        end
    end
    STATE.continueWorker = coroutine.create(function()
        while STATE.enabled and STATE.runId == runId and gui.Parent do
            local scanned, err = pcall(scanAndDismiss)
            if not scanned then
                releaseContinueClick()
                if os.clock() >= nextWarningAt then
                    nextWarningAt = os.clock() + 10
                    warn("[AUTO] Continue screen check: " .. tostring(err))
                end
            end
            task.wait(CONFIG.ContinueCheckInterval)
        end
    end)
    task.spawn(STATE.continueWorker)
end

local function mainLoop()
    startContinueWatcher()
    startTroopPathFilter()
    while STATE.enabled do
        local area, map = getLocation()
        if area == "LOBBY" then
            if STATE.phase ~= "LOBBY" then
                -- Only a confirmed return to the lobby starts a fresh Play/vote cycle.
                STATE.phase = "LOBBY"
                STATE.lobbyPreferences = {
                    priority=copySettings(CONFIG.MapPriority), enabled=copySettings(CONFIG.MapEnabled), fallback=CONFIG.MapFallback,
                }
                STATE.lobbyPlayRequested = false
                STATE.lobbyPlayRequestedAt = 0
                STATE.lobbyVoteName = nil
                STATE.lobbyVoteChoice = nil
                STATE.currentCamp = nil
                STATE.pendingSlot = nil
                STATE.pendingUntil = 0
                STATE.activeSlot = nil
                STATE.zeroSince = nil
                STATE.troopActive = false
                setStatus("Lobby", "Auto vote / join")
            end
            local ok, success, reason = pcall(runLobbyFlow)
            if not STATE.enabled then break end
            if not ok or not success then
                stopMovement()
                pcall(function() Controls:Enable() end)
                if reason ~= "LOCATION_CHANGED" then
                    setStatus("Lobby retry", tostring(ok and reason or success))
                    waitSeconds(CONFIG.FlowRetryDelay)
                end
            end
        elseif map and area == map.Name then
            STATE.phase = "MATCH"
            STATE.roundTeam = getCurrentTeam()
            setStatus("Match", map.Name)
            local ok, reason = pcall(runMatchLoop, map)
            stopMovement()
            clearMovementConnections()
            pcall(function() Controls:Enable() end)
            if not STATE.enabled then break end
            if not ok then
                STATE.troopActive = false
                setStatus("Match retry", tostring(reason))
                waitSeconds(CONFIG.FlowRetryDelay)
            end
            if ok and not CONFIG.AutoNextRound then
                setStatus("Round finished", "Auto next round is OFF")
                return
            end
            -- A new map or return to lobby is handled by the next location sample.
        else
            stopMovement()
            STATE.troopActive = false
            setStatus("Checking location", "Waiting for character or teleport to finish")
        end
        waitSeconds(CONFIG.ActiveMapCheckInterval)
    end
end

--==================================================

