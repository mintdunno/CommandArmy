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

-- IMPORTANT:

-- This function is only called after the script

-- has verified that the player is inside camp.

local function getCurrentTroop()
    local matchUI = getMatchUI()
    local loadout = getLoadout()
    if not matchUI or not loadout then
        return nil
    end

    local troop = matchUI:FindFirstChild("Troop")
    local troopIcon = troop and troop:FindFirstChild("TroopIcon")
    local countLabel = troopIcon and troopIcon:FindFirstChild("TroopCount")
    local deadOverlay = troopIcon and troopIcon:FindFirstChild("Dead")

    local alive
    local max
    if countLabel then
        local clean = stripRichText(countLabel.Text)
        local aliveText, maxText = clean:match("(%d+)%s*/%s*(%d+)")
        alive = tonumber(aliveText)
        max = tonumber(maxText)
    end

    -- IMPORTANT:
    -- Do NOT use Slot.State.Equipped.Visible to determine the currently
    -- deployed troop. "Equipped" describes the loadout and is not a
    -- reliable active-slot signal. We remember the slot that this script
    -- actually spawned instead.
    local slotNumber = STATE.activeSlot or STATE.pendingSlot or STATE.lastSlot
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
    if countLabel or slotNumber then
        return {
            slot = slotNumber,
            name = name,
            alive = alive,
            max = max,
            dead = (deadOverlay and deadOverlay.Visible) or (alive ~= nil and alive <= 0),
        }
    end

    return nil
end

local function getEquippedUnits()

    local loadout =

        getDisplayLoadout()

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
    local units=getEquippedUnits()
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

        getEquippedUnits()

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

local function spawnUnit(supply,slot)
    if not CONFIG.AutoSpawn then return false,"AUTO_SPAWN_OFF" end
    if not isInsideSupplyCamp(supply) then return false,"LEFT_CAMP" end
    local menu=getSupplyMenu()
    if not menu or not menu.Visible then return false,"SUPPLY_MENU_NOT_OPEN" end
    if type(slot)~="number" or slot%1~=0 or slot<1 or slot>4 then return false,"INVALID_SLOT" end
    if not CONFIG.SlotsEnabled[slot] then return false,"SLOT_DISABLED" end
    local fired, fireError = pcall(function()
        SupplyPointRequest:FireServer("Begin",slot)
    end)
    if not fired then return false, "SPAWN_REMOTE_ERROR: " .. tostring(fireError) end
    STATE.pendingSlot=slot
    STATE.pendingUntil=os.clock()+CONFIG.SpawnPendingTimeout
    return true
end

--==================================================

-- TROOP CYCLE

--==================================================

local function processTroopInsideCamp(supply)
    if not isInsideSupplyCamp(supply) then
        STATE.troopActive = false
        STATE.zeroSince = nil
        return false, "NOT_INSIDE_CAMP"
    end

    local troop = getCurrentTroop()
    local now = os.clock()

    -- A pending Begin(slot) is confirmed by the global TroopCount becoming
    -- positive. We intentionally do not compare against UI "Equipped" state.
    if STATE.pendingSlot then
        if troop and troop.alive and troop.alive > 0 then
            STATE.activeSlot = STATE.pendingSlot
            STATE.lastSlot = STATE.pendingSlot
            STATE.pendingSlot = nil
            STATE.pendingUntil = 0
            STATE.zeroSince = nil
            STATE.troopActive = true

            troop = getCurrentTroop()
        elseif now < STATE.pendingUntil then
            STATE.troopActive = false
            setStatus(
                "Spawn pending",
                "Waiting for Slot " .. STATE.pendingSlot
            )
            return true, "SPAWN_PENDING"
        else
            -- Request never produced a living troop. Clear only the pending
            -- request; do not rotate repeatedly in the same tick.
            STATE.pendingSlot = nil
            STATE.pendingUntil = 0
            STATE.zeroSince = now
            STATE.troopActive = false
            return true, "SPAWN_TIMEOUT"
        end
    end

    if troop then
        local countText = troop.alive ~= nil and troop.max ~= nil
            and (tostring(troop.alive) .. "/" .. tostring(troop.max))
            or "?"

        local slotText = troop.slot and (" | Slot " .. troop.slot) or ""
        setStatus(
            "In camp",
            troop.name .. slotText .. " | " .. countText
        )

        -- Positive TroopCount always wins: keep the current unit.
        if troop.alive and troop.alive > 0 then
            if STATE.activeSlot then
                STATE.lastSlot = STATE.activeSlot
            end
            STATE.zeroSince = nil
            STATE.troopActive = true
            return true, "ALIVE"
        end

        -- If the UI has not produced a numeric count yet, do not guess that
        -- the troop is dead and do not switch.
        if troop.alive == nil and not troop.dead then
            STATE.troopActive = false
            STATE.zeroSince = nil
            return true, "TROOP_STATE_LOADING"
        end

        -- TroopCount can flash 0 during UI/server transitions. Require the
        -- zero/dead state to remain stable before rotating to another slot.
        STATE.zeroSince = STATE.zeroSince or now
        if now - STATE.zeroSince < 2.0 then
            STATE.troopActive = false
            return true, "DEATH_CONFIRMING"
        end

        if STATE.activeSlot then
            STATE.lastSlot = STATE.activeSlot
        elseif troop.slot then
            STATE.lastSlot = troop.slot
        end
        STATE.activeSlot = nil
    else
        -- No readable troop state: never spam Begin requests. Wait briefly
        -- for MatchUI/SupplyPoint to settle before deciding there is no troop.
        STATE.zeroSince = STATE.zeroSince or now
        if now - STATE.zeroSince < 2.0 then
            STATE.troopActive = false
            return true, "TROOP_STATE_LOADING"
        end
    end

    if not CONFIG.AutoSpawn then
        STATE.troopActive = false
        return true, "AUTO_SPAWN_OFF"
    end

    STATE.troopActive = false

    if not isInsideSupplyCamp(supply) then
        return false, "LEFT_CAMP"
    end

    local opened, openReason = openSupplyMenu(supply)
    if not opened then
        return false, openReason
    end

    if not isInsideSupplyCamp(supply) then
        return false, "LEFT_CAMP"
    end

    -- Opening the menu can refresh TroopCount. Re-check before spawning.
    troop = getCurrentTroop()
    if troop and troop.alive and troop.alive > 0 then
        STATE.zeroSince = nil
        STATE.troopActive = true
        return true, "ALIVE"
    end

    local afterSlot = STATE.lastSlot
    local nextSlot, nextUnit = getNextUsableUnit(afterSlot)

    if not nextSlot then
        setStatus("In camp", "No usable troop yet")
        return true, "WAITING_FOR_UNIT"
    end

    setStatus(
        "Spawning",
        nextUnit.name .. " | Slot " .. nextSlot
    )

    local spawned, spawnReason = spawnUnit(supply, nextSlot)
    if not spawned then
        return false, spawnReason
    end

    STATE.zeroSince = nil

    print(
        "[SPAWN]",
        nextUnit.name,
        "| Slot:",
        nextSlot
    )

    return true, "SPAWN_REQUESTED"
end

--==================================================
-- TROOP ATTACK
--==================================================

local function updateTroopAttack()
    if not CONFIG.AutoAttack then return end
    if not isMatchContext(getActiveMapModel()) then
        STATE.troopActive = false
        return
    end
    local matchUI = getMatchUI()
    local troop = matchUI and matchUI:FindFirstChild("Troop")
    local troopIcon = troop and troop:FindFirstChild("TroopIcon")
    local countLabel = troopIcon and troopIcon:FindFirstChild("TroopCount")
    if countLabel then
        local clean = stripRichText(countLabel.Text)
        local aliveText = clean:match("(%d+)%s*/%s*%d+")
        local alive = tonumber(aliveText)
        if alive ~= nil then STATE.troopActive = alive > 0 end
    end
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

