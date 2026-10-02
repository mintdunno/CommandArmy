-- TROOP STATE

--==================================================

local function stripRichText(text)

    return text:gsub(

        "<[^>]->",

        ""

    )

end

local function getLoadout()

    local menu =

        getSupplyMenu()

    return menu

        and menu:FindFirstChild(

            "Loadout"

        )

        or nil

end

-- The match supply menu uses Slot1/Slot2/... while the lobby HUD uses 1/2/3/4.
-- Keep automation on the match loadout, but let the GUI read either source so
-- troop names are visible before entering a camp.
local function getDisplayLoadout()
    local menu = getSupplyMenu()
    local matchLoadout = menu and menu:FindFirstChild("Loadout")
    if menu and menu.Visible and matchLoadout then return matchLoadout end
    local playerGui = player:FindFirstChild("PlayerGui")
    local hud = playerGui and playerGui:FindFirstChild("HUD")
    local hudLoadout = hud and hud:FindFirstChild("Loadout")
    return hudLoadout or matchLoadout
end

local function getLoadoutSlot(loadout, slotNumber)
    if not loadout then return nil end
    return loadout:FindFirstChild("Slot" .. slotNumber)
        or loadout:FindFirstChild(tostring(slotNumber))
end

local function parseTroopCount()
    local matchUI = getMatchUI()
    local troop = matchUI and matchUI:FindFirstChild("Troop")
    local icon = troop and troop:FindFirstChild("TroopIcon")
    local label = icon and icon:FindFirstChild("TroopCount")
    if not label then return nil, nil end
    local alive, maximum = stripRichText(label.Text):match("(%d+)%s*/%s*(%d+)")
    return tonumber(alive), tonumber(maximum)
end

local function getEquippedSlot()
    local loadout = getLoadout()
    for slotNumber = 1, 4 do
        local slot = loadout and loadout:FindFirstChild("Slot" .. slotNumber)
        local state = slot and slot:FindFirstChild("State")
        local equipped = state and state:FindFirstChild("Equipped")
        if equipped and equipped.Visible then return slotNumber end
    end
    return nil
end

-- IMPORTANT:

-- This function is only called after the script

-- has verified that the player is inside camp.

local function getCurrentTroop()
    local loadout = getLoadout()
    local alive, max = parseTroopCount()
    -- Equipped identifies the slot; only TroopCount establishes liveness.
    local slotNumber = getEquippedSlot() or STATE.activeSlot or STATE.pendingSlot or STATE.lastSlot
    local name = "Active troop"

    if slotNumber then
        local slot = getLoadoutSlot(loadout, slotNumber)
        local nameLabel = slot and slot:FindFirstChild("TroopName", true)
        if nameLabel then
            name = stripRichText(nameLabel.Text)
        end
    end

    -- TroopCount is the authoritative liveness signal. Even if we do not
    -- know the slot yet (for example when enabling the script mid-round),
    -- a positive count means an existing troop must be preserved.
    if alive ~= nil or slotNumber then
        return {
            slot = slotNumber,
            name = name,
            alive = alive,
            max = max,
            dead = alive ~= nil and alive == 0,
        }
    end

    return nil
end

local function getEquippedUnits(matchOnly)

    local loadout
    if matchOnly then loadout = getLoadout() else loadout = getDisplayLoadout() end

    if not loadout then

        return {}

    end

    local units = {}

    for slotNumber = 1, 4 do

        local slot =

            getLoadoutSlot(

                loadout,

                slotNumber

            )

        if slot then

            local nameLabel =

                slot:FindFirstChild(

                    "TroopName",

                    true

                )

            local amountLabel =

                slot:FindFirstChild(

                    "TroopAmount",

                    true

                )

            if nameLabel and amountLabel then

                local name =

                    stripRichText(

                        nameLabel.Text

                    )

                local amountText =

                    stripRichText(

                        amountLabel.Text

                    )

                local amount =

                    tonumber(

                        amountText:match(

                            "%d+"

                        )

                    )

                if

                    name ~= ""

                    and amount

                    and amount > 0

                then

                    local deadOverlay =

                        slot:FindFirstChild(

                            "Dead"

                        )

                    local dead = deadOverlay and deadOverlay.Visible or false
                    local respawnLabel = deadOverlay and deadOverlay:FindFirstChild("Respawn", true)
                    if respawnLabel and (respawnLabel:IsA("TextLabel") or respawnLabel:IsA("TextButton")) then
                        local remaining = tonumber(stripRichText(respawnLabel.Text):match("%d+"))
                        if remaining ~= nil then dead = remaining > 0 end
                    end

                    units[slotNumber] = {

                        slot =

                            slotNumber,

                        name = name,

                        amount = amount,

                        dead = dead,

                    }

                end

            end

        end

    end

    return units

end

-- Cycles:

-- 1 -> 2 -> 3 -> 4 -> 1

--

-- Empty and dead slots are skipped.

local function getNextUsableUnit(afterSlot)
    local units=getEquippedUnits(true)
    local order=CONFIG.SlotOrder
    local startIndex=table.find(order,afterSlot) or 0
    for step=1,#order do
        local slot=order[(startIndex+step-1)%#order+1]
        local unit=units[slot]
        if CONFIG.SlotsEnabled[slot] and unit and not unit.dead then return slot,unit end
    end
    return nil
end

local function getSpecificUsableUnit(slot)

    local units =

        getEquippedUnits(true)

    local unit =

        units[slot]

    if unit and not unit.dead then

        return slot, unit

    end

    return nil

end

--==================================================

-- SPAWN

--==================================================

-- Re-check at the remote boundary too: opening the menu can yield while
-- the player dies, the GUI rebuilds, or a manual spawn begins.
local function spawnUnit(supply, slot)
    if not CONFIG.AutoSpawn then return false, "AUTO_SPAWN_OFF" end
    if not canAutomateTroops() then return false, "PLAYER_STATE_PAUSED" end
    local changing, progressKnown = isTroopSpawnInProgress()
    if changing or STATE.pendingSlot then return false, "SPAWN_PENDING" end
    if not progressKnown then return false, "TROOP_STATE_LOADING" end
    local alive = parseTroopCount()
    if alive ~= 0 then return false, "TROOP_NOT_ZERO" end
    if not STATE.zeroSince or os.clock() - STATE.zeroSince < 2 then
        return false, "DEATH_CONFIRMING"
    end
    if getSupplyAction() ~= "Spawn" then return false, "SPAWN_NOT_READY" end
    if not isInsideSupplyCamp(supply) then return false, "LEFT_CAMP" end
    local menu = getSupplyMenu()
    if not menu or not menu.Visible then return false, "SUPPLY_MENU_NOT_OPEN" end
    if type(slot) ~= "number" or slot % 1 ~= 0 or slot < 1 or slot > 4 then
        return false, "INVALID_SLOT"
    end
    if not CONFIG.SlotsEnabled[slot] then return false, "SLOT_DISABLED" end
    if not getSpecificUsableUnit(slot) then return false, "SLOT_UNAVAILABLE" end

    -- Reserve before sending; a successful send is not spawn confirmation.
    STATE.pendingSlot = slot
    STATE.pendingUntil = os.clock() + math.max(30, CONFIG.SpawnPendingTimeout)
    local fired, fireError = pcall(function()
        SupplyPointRequest:FireServer("Begin", slot)
    end)
    if not fired then
        STATE.pendingSlot = nil
        STATE.pendingUntil = 0
        STATE.zeroSince = nil
        return false, "SPAWN_REMOTE_ERROR: " .. tostring(fireError)
    end
    return true
end

--==================================================
-- TROOP CYCLE
--==================================================

local function observeTroopState()
    if not canAutomateTroops() then
        STATE.troopActive = false
        STATE.zeroSince = nil
        return "PLAYER_STATE_PAUSED"
    end

    local alive = parseTroopCount()
    local changing, progressKnown = isTroopSpawnInProgress()
    STATE.troopActive = alive ~= nil and alive > 0

    if STATE.troopActive then
        local equipped = getEquippedSlot()
        STATE.activeSlot = equipped or STATE.pendingSlot or STATE.activeSlot
        if STATE.activeSlot then STATE.lastSlot = STATE.activeSlot end
        STATE.zeroSince = nil
        -- Keep the reservation while native progress is visible, even if
        -- the count has already started increasing.
        if not changing and progressKnown then
            STATE.pendingSlot = nil
            STATE.pendingUntil = 0
        end
        return "ALIVE"
    end

    if changing then
        STATE.zeroSince = nil
        return "SPAWN_PENDING"
    end

    -- Missing/unparseable count and Retreat never authorize death/rotation.
    if alive == nil or not progressKnown or getSupplyAction() == "Retreat" then
        STATE.zeroSince = nil
        return (alive == nil or not progressKnown) and "TROOP_STATE_LOADING" or "RETREAT_AVAILABLE"
    end

    local now = os.clock()
    if STATE.pendingSlot then
        STATE.zeroSince = nil
        -- UI must positively permit spawning before abandoning a request.
        if now < STATE.pendingUntil or getSupplyAction() ~= "Spawn" then
            return "SPAWN_PENDING"
        end
        -- Remember the failed attempt so the next request advances once.
        STATE.lastSlot = STATE.pendingSlot
        STATE.pendingSlot = nil
        STATE.pendingUntil = 0
        STATE.zeroSince = now
        return "SPAWN_TIMEOUT"
    end

    STATE.zeroSince = STATE.zeroSince or now
    if now - STATE.zeroSince < 2 then return "DEATH_CONFIRMING" end
    if STATE.activeSlot then
        STATE.lastSlot = STATE.activeSlot
    elseif not STATE.lastSlot then
        STATE.lastSlot = getEquippedSlot()
    end
    STATE.activeSlot = nil
    return "READY_TO_SPAWN"
end

local function processTroopInsideCamp(supply)
    if not isInsideSupplyCamp(supply) then
        STATE.zeroSince = nil
        return false, "NOT_INSIDE_CAMP"
    end

    local phase = observeTroopState()
    if phase ~= "READY_TO_SPAWN" then
        if phase == "SPAWN_PENDING" then
            setStatus("Spawn pending", STATE.pendingSlot
                and ("Waiting for Slot " .. STATE.pendingSlot) or "Native troop spawn in progress")
        elseif phase == "ALIVE" then
            local troop = getCurrentTroop()
            setStatus("In camp", troop.name .. (troop.slot and (" | Slot " .. troop.slot) or "")
                .. " | " .. troop.alive .. "/" .. troop.max)
        end
        return true, phase
    end

    if not CONFIG.AutoSpawn then return true, "AUTO_SPAWN_OFF" end
    local opened, openReason = openSupplyMenu(supply)
    if not opened then return false, openReason end
    if not isInsideSupplyCamp(supply) then
        STATE.zeroSince = nil
        return false, "LEFT_CAMP"
    end

    -- Menu opening may yield. Re-read all lifecycle evidence, not just count.
    phase = observeTroopState()
    if phase ~= "READY_TO_SPAWN" then return true, phase end
    if getSupplyAction() ~= "Spawn" then return true, "SPAWN_NOT_READY" end

    local nextSlot, nextUnit = getNextUsableUnit(STATE.lastSlot)
    if not nextSlot then
        setStatus("In camp", "No usable troop yet")
        return true, "WAITING_FOR_UNIT"
    end
    setStatus("Spawning", nextUnit.name .. " | Slot " .. nextSlot)
    local spawned, spawnReason = spawnUnit(supply, nextSlot)
    if not spawned then return false, spawnReason end
    STATE.zeroSince = nil
    print("[SPAWN]", nextUnit.name, "| Slot:", nextSlot)
    return true, "SPAWN_REQUESTED"
end

--==================================================
-- TROOP ATTACK
--==================================================

local function updateTroopAttack()
    if not CONFIG.AutoAttack then return end
    if not canAutomateTroops() then
        STATE.troopActive = false
        return
    end
    local alive = parseTroopCount()
    STATE.troopActive = alive ~= nil and alive > 0
    if not STATE.troopActive then return end
    if os.clock() - STATE.lastAttackAt < CONFIG.AttackInterval then return end
    local fired, fireError = pcall(function()
        TroopStateRequest:FireServer("Attack")
    end)
    STATE.lastAttackAt = os.clock()
    if not fired then
        setStatus("Attack retry", tostring(fireError))
        return
    end
    print("[TROOP] Attack")
end

--==================================================

