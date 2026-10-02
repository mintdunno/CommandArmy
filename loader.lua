-- COMMAND ARMY — GITHUB RAW LOADER
-- Repo: mintdunno/CommandArmy
-- Branch: main

local BASE =
    "https://raw.githubusercontent.com/mintdunno/CommandArmy/main/"

local PARTS = {
    "parts/00_shell.lua",
    "parts/01_config_state.lua",
    "parts/02_location.lua",
    "parts/03_gui_and_movement.lua",
    "parts/04_pathfinding.lua",
    "parts/05_lobby_and_join.lua",
    "parts/06_camp.lua",
    "parts/07_supply_ui.lua",
    "parts/08_troops.lua",
    "parts/09_match_and_main.lua",
    "parts/10_controls_and_settings.lua",
    "parts/11_live_info_and_init.lua",
}

--==================================================
-- LOADER UI
--==================================================

local Players = game:GetService("Players")

local player =
    Players.LocalPlayer
    or Players.PlayerAdded:Wait()

local playerGui =
    player:WaitForChild("PlayerGui")

local old =
    playerGui:FindFirstChild(
        "CommandArmyModuleLoader"
    )

if old then
    old:Destroy()
end

local gui = Instance.new("ScreenGui")

gui.Name = "CommandArmyModuleLoader"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 1000003
gui.Parent = playerGui

local frame = Instance.new("Frame")

frame.AnchorPoint =
    Vector2.new(0.5, 0.5)

frame.Position =
    UDim2.fromScale(0.5, 0.5)

frame.Size =
    UDim2.fromOffset(590, 230)

frame.BackgroundColor3 =
    Color3.fromRGB(25, 30, 40)

frame.BorderSizePixel = 0
frame.Parent = gui

local label = Instance.new("TextLabel")

label.Position =
    UDim2.fromOffset(14, 14)

label.Size =
    UDim2.new(1, -28, 1, -28)

label.BackgroundTransparency = 1

label.TextColor3 =
    Color3.new(1, 1, 1)

label.TextSize = 16
label.TextWrapped = true

label.TextXAlignment =
    Enum.TextXAlignment.Left

label.TextYAlignment =
    Enum.TextYAlignment.Top

label.Font = Enum.Font.Code

label.Text =
    "COMMAND ARMY GITHUB LOADER\nStarting..."

label.Parent = frame

task.wait()

--==================================================
-- ERROR
--==================================================

local function fail(message)

    message = tostring(message)

    label.Text =
        "COMMAND ARMY GITHUB LOADER — ERROR\n\n"
        .. message

    frame.BackgroundColor3 =
        Color3.fromRGB(74, 31, 36)

    warn(
        "[ARMY LOADER] "
        .. message
    )

end

--==================================================
-- CHECK LOADSTRING
--==================================================

if type(loadstring) ~= "function" then

    fail(
        "loadstring() is unavailable."
    )

    return

end

--==================================================
-- HTTP GET
--==================================================

local function httpGet(url)

    -- First try game:HttpGet()
    local ok, result =
        pcall(function()

            return game:HttpGet(url)

        end)

    if
        ok
        and type(result) == "string"
        and #result > 0
    then
        return result
    end

    -- Fallback for environments exposing request()
    if type(request) == "function" then

        local requestOk, response =
            pcall(function()

                return request({
                    Url = url,
                    Method = "GET",
                })

            end)

        if requestOk and response then

            local body =
                response.Body
                or response.body

            local status =
                response.StatusCode
                or response.Status
                or response.status

            if
                type(body) == "string"
                and #body > 0
                and (
                    status == nil
                    or (
                        tonumber(status)
                        and tonumber(status) >= 200
                        and tonumber(status) < 300
                    )
                )
            then
                return body
            end

        end

    end

    error(
        "HTTP GET failed:\n"
        .. url
        .. "\n\n"
        .. tostring(result)
    )

end

--==================================================
-- DOWNLOAD PARTS
--==================================================

local sources =
    table.create(#PARTS)

for index, relativePath
    in ipairs(PARTS)
do

    local url =
        BASE .. relativePath

    label.Text =
        string.format(
            "COMMAND ARMY GITHUB LOADER\n\n"
            .. "Downloading %d/%d\n"
            .. "%s",
            index,
            #PARTS,
            relativePath
        )

    task.wait()

    local ok, content =
        pcall(
            httpGet,
            url
        )

    if not ok then

        fail(
            "Could not download:\n"
            .. relativePath
            .. "\n\n"
            .. tostring(content)
        )

        return

    end

    if
        content == ""
        or content:find(
            "404: Not Found",
            1,
            true
        )
    then

        fail(
            "GitHub file missing:\n"
            .. relativePath
        )

        return

    end

    sources[index] =
        content

end

--==================================================
-- COMBINE
--==================================================

label.Text =
    "COMMAND ARMY GITHUB LOADER\n\n"
    .. "All parts downloaded.\n"
    .. "Combining source..."

task.wait()

-- IMPORTANT:
-- These files are slices of one original source.
-- Their exact order must not change.

local source =
    table.concat(sources, "\n")

--==================================================
-- COMPILE
--==================================================

label.Text =
    "COMMAND ARMY GITHUB LOADER\n\n"
    .. "Compiling..."

task.wait()

local chunk, compileError =
    loadstring(
        source,
        "@CommandArmy/combined.lua"
    )

if not chunk then

    fail(
        "COMPILE ERROR\n\n"
        .. tostring(compileError)
    )

    return

end

--==================================================
-- RUN
--==================================================

label.Text =
    "COMMAND ARMY GITHUB LOADER\n\n"
    .. "Compile OK.\n"
    .. "Starting Command Army..."

task.wait()

local ok, runtimeError =
    xpcall(
        chunk,
        function(message)

            if
                debug
                and type(debug.traceback)
                    == "function"
            then

                return debug.traceback(
                    tostring(message),
                    2
                )

            end

            return tostring(message)

        end
    )

if not ok then

    fail(
        "RUNTIME ERROR\n\n"
        .. tostring(runtimeError):sub(
            1,
            1600
        )
    )

    return

end

--==================================================
-- DONE
--==================================================

if gui.Parent then
    gui:Destroy()
end
