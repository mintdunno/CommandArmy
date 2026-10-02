-- SUPPLY GUI

--==================================================

local function getMatchUI()

    return player.PlayerGui

        :FindFirstChild("MatchUI")

end

local function getSupplyMenu()

    local matchUI =

        getMatchUI()

    return matchUI

        and matchUI:FindFirstChild(

            "SupplyPoint"

        )

        or nil

end

local function waitForSupplyMenu()

    local startedAt = os.clock()

    while

        STATE.enabled

        and os.clock() - startedAt

            < CONFIG.MenuTimeout

    do

        local menu =

            getSupplyMenu()

        if menu and menu.Visible then

            return true

        end

        task.wait(0.05)

    end

    return false

end

local function openSupplyMenu(supply)

    if not isInsideSupplyCamp(supply) then

        return false,

            "NOT_INSIDE_CAMP"

    end

    local menu =

        getSupplyMenu()

    if menu and menu.Visible then

        return true

    end

    local prompt =

        getSupplyPrompt(supply)

    if not prompt then

        return false,

            "NO_PROMPT"

    end

    if not prompt.Enabled then

        return false,

            "PROMPT_DISABLED"

    end

    if

        type(fireproximityprompt)

        ~= "function"

    then

        return false,

            "fireproximityprompt unavailable"

    end

    fireproximityprompt(prompt)

    if not waitForSupplyMenu() then

        return false,

            "SUPPLY_MENU_NOT_OPEN"

    end

    return true

end

--==================================================

