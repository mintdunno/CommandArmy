-- MATCH LOOP

--==================================================

local function runMatchLoop(map)
    -- A retry/respawn on the same map must not discard a pending request.
    if STATE.troopMap ~= map then
        STATE.troopMap = map
        STATE.lastSlot = nil
        STATE.activeSlot = nil
        STATE.pendingSlot = nil
        STATE.pendingUntil = 0
    end
    STATE.zeroSince = nil
    STATE.currentCamp = nil
    STATE.troopActive = false
    STATE.lastAttackAt = 0
    local selectionKey
    local selectedSupply
    local nextCampCheckAt = 0
    local wasInsideCamp = false

    local endReason = "STOPPED"
    while STATE.enabled do
        local gamePhase = getGamePhase()
        if gamePhase == "RESULT" then endReason = "ROUND_FINISHED"; break end
        local area, currentMap = getLocation()
        if gamePhase == "LOBBY" and area == "LOBBY" then endReason = "RETURNED_TO_LOBBY"; break end
        if currentMap and currentMap ~= map then endReason = "ROUND_CHANGED"; break end
        if isPlayerRespawning() then
            stopMovement()
            STATE.troopActive = false
            STATE.zeroSince = nil
            nextCampCheckAt = 0
            setStatus("Waiting for player spawn", "Camp/troop automation paused")
            waitSeconds(CONFIG.CheckInterval)
            continue
        end
        if currentMap ~= map or area ~= map.Name or gamePhase ~= "MATCH" then
            stopMovement()
            STATE.troopActive = false
            STATE.zeroSince = nil
            setStatus("Checking location", "Waiting for map/lobby confirmation")
            waitSeconds(CONFIG.ActiveMapCheckInterval)
            continue
        end
        local character = player.Character
        local humanoid = character and character:FindFirstChild("Humanoid")
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if not humanoid or not root or humanoid.Health <= 0 then
            stopMovement()
            STATE.troopActive = false
            STATE.zeroSince = nil
            nextCampCheckAt = 0
            setStatus("Waiting for character", "Camp movement will resume after respawn")
            waitSeconds(CONFIG.CheckInterval)
            continue
        end
        observeTroopState() -- Also confirm identity/liveness outside camp.
        local interacting = isCampInteractionActive()
        if interacting then stopMovement() end
        local currentKey = tostring(getCurrentTeam()) .. ":" .. tostring(CONFIG.AutoCamp) .. ":" .. CONFIG.CampMode .. ":" .. CONFIG.SelectedCamp
        if not interacting and currentKey ~= selectionKey then
            selectionKey = currentKey
            selectedSupply = nil
            STATE.currentCamp = nil
            nextCampCheckAt = 0
            wasInsideCamp = false
        end
        if not interacting and not CONFIG.AutoCamp and CONFIG.CampMode == "Nearest" then
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
        if interacting and not selectedSupply then
            selectedSupply = getCurrentTeamCamp()
            STATE.currentCamp = selectedSupply
        end
        if not interacting and not selectedSupply and (CONFIG.AutoCamp or CONFIG.CampMode == "Selected")
            and os.clock() >= nextCampCheckAt then
            local reason
            selectedSupply, reason = getBestTeamSupply()
            STATE.currentCamp = selectedSupply
            if not selectedSupply then
                setStatus("Waiting for camp", tostring(reason) .. " | retrying shortly")
                nextCampCheckAt = os.clock() + CONFIG.CampRetryDelay
            end
        end
        if not STATE.enabled then break end
        -- GUI can change during camp selection/movement waits.
        if not canAutomateTroops() then
            stopMovement()
            STATE.zeroSince = nil
            STATE.troopActive = false
            waitSeconds(CONFIG.CheckInterval)
            continue
        end
        if selectedSupply then
            local inside = isInsideSupplyCamp(selectedSupply)
            if wasInsideCamp and not inside then nextCampCheckAt = 0 end
            if canNavigateCamp(map) and not inside and os.clock() >= nextCampCheckAt then
                setStatus("Moving to camp", selectedSupply.Name)
                local entered, reason = withControlsDisabled(function()
                    return runIntoSupplyCamp(selectedSupply)
                end)
                if not STATE.enabled then break end
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
        if not wasInsideCamp then STATE.zeroSince = nil end
        updateTroopAttack()
        waitSeconds(CONFIG.CheckInterval)
    end
    STATE.currentCamp = nil
    STATE.troopActive = false
    return true, endReason
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
    local screen = getGameScreen("MatchResult")
    local playerGui = player:FindFirstChild("PlayerGui")
    if not screen or not screen.Enabled or not playerGui then return nil end
    if not label.Parent or not label:IsDescendantOf(screen) or label:IsDescendantOf(gui)
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
    while ancestor and ancestor ~= playerGui do
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
            return ancestor == screen and ancestor.Enabled and ancestor or nil
        end
        ancestor = ancestor.Parent
    end
    return nil
end

local function getContinueClickPoint(label, screen)
    local playerGui = player:FindFirstChild("PlayerGui")
    if not playerGui then return nil end
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
            for _, hit in ipairs(playerGui:GetGuiObjectsAtPosition(guiPoint.X, guiPoint.Y)) do
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
        local resultScreen = getGameScreen("MatchResult")
        local visible = resultScreen ~= nil and resultScreen.Enabled
        for _, object in ipairs(visible and resultScreen:GetDescendants() or {}) do
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
        -- The audit has no Continue label in MatchResult. Its Victory/Defeat
        -- text offers a non-button click target, avoiding reward buttons.
        if visible and not prompt then
            local result = resultScreen:FindFirstChild("Result")
            for _, name in ipairs({"Victory", "Defeat"}) do
                local label = result and result:FindFirstChild(name)
                if label and getContinueScreen(label) then
                    prompt = label
                    point = getContinueClickPoint(label, resultScreen)
                    if point then break end
                end
            end
        end
        if STATE.continueVisible ~= visible then STATE.location = nil end
        STATE.continueVisible = visible
        if not CONFIG.AutoContinue or not visible or not prompt or os.clock() < nextClickAt then return end
        -- Respect the user's typing/mouse input and Roblox menus.
        if GuiService.MenuIsOpen or UserInputService:GetFocusedTextBox()
            or isGameScreenEnabled("LevelUp") or isGameScreenEnabled("Summon")
            or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then return end
        if not STATE.enabled or STATE.runId ~= runId or not getContinueScreen(prompt) then return end
        local restorePanel
        if not point and main.Visible and #senders > 0 then
            -- The automation panel often covers the entire result card.
            -- Restore it on release, cancellation, and errors alike.
            main.Visible = false
            restorePanel = function() if main.Parent then main.Visible = true end end
            STATE.continueRelease = restorePanel
            point = getContinueClickPoint(prompt, resultScreen)
        end
        if not point then releaseContinueClick(); return end
        nextClickAt = os.clock() + CONFIG.ContinueClickInterval
        stopMovement()
        for _, send in ipairs(senders) do
            local pressed = pcall(send, point, true)
            if pressed then
                STATE.continueRelease = function()
                    local released, err = pcall(send, point, false)
                    if restorePanel then restorePanel() end
                    if not released then warn("[AUTO] Continue release: " .. tostring(err)) end
                end
                -- Allow InputBegan and button press to process before the release.
                task.wait(0.05)
                releaseContinueClick()
                return -- The next scan verifies whether the prompt actually closed.
            end
        end
        releaseContinueClick()
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

-- Only confirmed lobby entry starts a fresh vote/join/troop history.
local function beginLobbyCycle()
    STATE.lobbyCycleActive = true
    STATE.roundFinished = false
    STATE.phase = "LOBBY"
    STATE.lobbyPreferences = {
        priority=copySettings(CONFIG.MapPriority), enabled=copySettings(CONFIG.MapEnabled), fallback=CONFIG.MapFallback,
    }
    STATE.lobbyPlayRequested = false
    STATE.lobbyVoteName = nil
    STATE.lobbyVoteChoice = nil
    STATE.joinRequest = nil
    STATE.roundTeam = nil
    STATE.currentCamp = nil
    STATE.troopMap = nil
    STATE.lastSlot = nil
    STATE.pendingSlot = nil
    STATE.pendingUntil = 0
    STATE.activeSlot = nil
    STATE.zeroSince = nil
    STATE.troopActive = false
    STATE.lastAttackAt = 0
    setStatus("Lobby", "Auto vote / join")
end

local function mainLoop()
    startContinueWatcher()
    startTroopPathFilter()
    while STATE.enabled do
        local gamePhase = getGamePhase()
        local area, map = getLocation()
        if gamePhase == "RESULT" then
            if STATE.phase ~= "RESULT" then
                STATE.finishedMap = STATE.troopMap or map or STATE.finishedMap
            end
            STATE.phase = "RESULT"
            STATE.roundFinished = true
            STATE.joinRequest = nil
            STATE.lobbyCycleActive = false
            STATE.currentCamp = nil
            STATE.troopActive = false
            STATE.zeroSince = nil
            stopMovement()
            setStatus("Match result", "Waiting for continue / return to lobby")
        elseif STATE.roundFinished and not CONFIG.AutoNextRound
            and gamePhase ~= "TRANSITION" and gamePhase ~= "UNKNOWN" then
            setStatus("Round finished", "Auto next round is OFF")
            return
        elseif hasEnteredMatchLifecycle() and map then
            STATE.phase = "MATCH"
            STATE.lobbyCycleActive = false
            STATE.roundTeam = getCurrentTeam() or STATE.roundTeam
            if STATE.joinRequest then STATE.joinRequest.accepted = true end
            setStatus("Match", map.Name)
            local ok, success, reason = pcall(runMatchLoop, map)
            stopMovement()
            clearMovementConnections()
            pcall(function() Controls:Enable() end)
            if not STATE.enabled then break end
            if not ok then
                STATE.troopActive = false
                STATE.zeroSince = nil
                setStatus("Match retry", tostring(success))
                waitSeconds(CONFIG.FlowRetryDelay)
            elseif success and (reason == "ROUND_FINISHED" or reason == "RETURNED_TO_LOBBY"
                or reason == "ROUND_CHANGED") then
                STATE.roundFinished = true
                STATE.finishedMap = map
            end
        elseif gamePhase == "PICK_TEAM" or (STATE.joinRequest and not STATE.joinRequest.accepted) then
            stopMovement()
            STATE.zeroSince = nil
            STATE.troopActive = false
            STATE.phase = "JOINING"
            if not map and gamePhase == "LOBBY" and area == "LOBBY" and STATE.joinRequest
                and os.clock() - STATE.joinRequest.sentAt >= CONFIG.JoinTimeout then
                STATE.finishedMap = STATE.joinRequest.map
                STATE.joinRequest = nil
                STATE.lobbyCycleActive = false
                setStatus("Lobby", "Previous join's map ended")
            elseif map and CONFIG.AutoJoin then
                local ok, success, reason = pcall(joinMatch, map)
                if not ok or not success then
                    if reason == "JOIN_MAP_CHANGED" then STATE.lobbyCycleActive = false end
                    setStatus("Join waiting", tostring(ok and reason or success))
                    waitSeconds(CONFIG.FlowRetryDelay)
                end
            else
                setStatus("Waiting for team selection", CONFIG.AutoJoin and "Map is loading" or "Auto join is OFF")
            end
        elseif gamePhase == "LOBBY" and area == "LOBBY" then
            if not STATE.lobbyCycleActive then beginLobbyCycle() end
            STATE.phase = "LOBBY"
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
        else
            stopMovement()
            STATE.troopActive = false
            STATE.zeroSince = nil
            setStatus("Waiting for game state", gamePhase .. " | character / map transition")
        end
        waitSeconds(CONFIG.ActiveMapCheckInterval)
    end
end

--==================================================

