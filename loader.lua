-- COMMAND ARMY — MODULAR LOCAL LOADER
-- Put this whole CommandArmy folder in your executor workspace, then execute this file.
-- If your folder has another name/path, change ROOT below.

local ROOT = "CommandArmy"

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

local Players = game:GetService("Players")
local player = Players.LocalPlayer or Players.PlayerAdded:Wait()
local playerGui = player:WaitForChild("PlayerGui")

local old = playerGui:FindFirstChild("CommandArmyModuleLoader")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "CommandArmyModuleLoader"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 1000003
gui.Parent = playerGui

local frame = Instance.new("Frame")
frame.AnchorPoint = Vector2.new(0.5, 0.5)
frame.Position = UDim2.fromScale(0.5, 0.5)
frame.Size = UDim2.fromOffset(590, 230)
frame.BackgroundColor3 = Color3.fromRGB(25, 30, 40)
frame.BorderSizePixel = 0
frame.Parent = gui

local label = Instance.new("TextLabel")
label.Position = UDim2.fromOffset(14, 14)
label.Size = UDim2.new(1, -28, 1, -28)
label.BackgroundTransparency = 1
label.TextColor3 = Color3.new(1, 1, 1)
label.TextSize = 16
label.TextWrapped = true
label.TextXAlignment = Enum.TextXAlignment.Left
label.TextYAlignment = Enum.TextYAlignment.Top
label.Font = Enum.Font.Code
label.Text = "COMMAND ARMY MODULE LOADER\nStarting..."
label.Parent = frame

task.wait()

local function fail(message)
    label.Text = "COMMAND ARMY MODULE LOADER — ERROR\n\n" .. tostring(message)
    frame.BackgroundColor3 = Color3.fromRGB(74, 31, 36)
    warn("[ARMY LOADER] " .. tostring(message))
end

if type(readfile) ~= "function" then
    fail("Your executor does not expose readfile().\nThis modular folder loader needs local-file access.")
    return
end

if type(loadstring) ~= "function" then
    fail("Your executor does not expose loadstring().")
    return
end

local sources = table.create(#PARTS)
for index, relativePath in ipairs(PARTS) do
    local fullPath = ROOT .. "/" .. relativePath
    label.Text = string.format(
        "COMMAND ARMY MODULE LOADER\nReading %d/%d\n%s",
        index,
        #PARTS,
        fullPath
    )
    task.wait()

    if type(isfile) == "function" and not isfile(fullPath) then
        fail("Missing file:\n" .. fullPath .. "\n\nKeep the whole CommandArmy folder together.")
        return
    end

    local ok, content = pcall(readfile, fullPath)
    if not ok then
        fail("Could not read:\n" .. fullPath .. "\n\n" .. tostring(content))
        return
    end

    sources[index] = content
end

label.Text = "COMMAND ARMY MODULE LOADER\nAll parts read. Compiling combined source..."
task.wait()

-- The part files are literal slices of one source file, so joining them without
-- separators reconstructs the exact original source text.
local source = table.concat(sources)
local chunk, compileError = loadstring(source, "@CommandArmy/combined.lua")
if not chunk then
    fail("COMPILE ERROR\n\n" .. tostring(compileError))
    return
end

label.Text = "COMMAND ARMY MODULE LOADER\nCompile OK. Starting Command Army..."
task.wait()

local ok, runtimeError = xpcall(chunk, function(message)
    return debug.traceback(tostring(message), 2)
end)

if not ok then
    fail("RUNTIME ERROR\n\n" .. tostring(runtimeError):sub(1, 1400))
    return
end

if gui.Parent then gui:Destroy() end
