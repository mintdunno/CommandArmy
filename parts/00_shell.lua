-- COMMAND AN ARMY — STANDALONE
-- Paste the entire file into a Roblox client execution context.
-- Settings/state are local; no environment table or external loader is used.
local localPlayers = game:GetService("Players")
local localPlayer = localPlayers.LocalPlayer
local startupDeadline = os.clock() + 15
while not localPlayer and os.clock() < startupDeadline do
    task.wait(0.1)
    localPlayer = localPlayers.LocalPlayer
end
if not localPlayer then
    warn("[ARMY] No LocalPlayer: this script must run on the Roblox client.")
    return
end
local localPlayerGui = localPlayer:WaitForChild("PlayerGui", 15)
local standaloneGui = Instance.new("ScreenGui")
standaloneGui.Name = "CommandArmyAutoStandalone"
standaloneGui.Enabled = true
standaloneGui.ResetOnSpawn = false
standaloneGui.IgnoreGuiInset = true
standaloneGui.DisplayOrder = 1000000
standaloneGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local function removePrevious(parent)
    if not parent then return end
    for _, name in ipairs({"CommandArmyAutoStandalone", "CommandArmyAutoGUI", "CommandArmyAutoLoading"}) do
        local old = parent:FindFirstChild(name)
        if old and old ~= standaloneGui then
            local shutdown = old:FindFirstChild("StandaloneShutdown")
            if shutdown and shutdown:IsA("BindableEvent") then shutdown:Fire() end
            old:Destroy()
        end
    end
end
-- HARD MOUNT: use PlayerGui directly. Some executors let Parent=CoreGui succeed
-- without actually rendering injected ScreenGuis, which makes the whole UI look dead.
if not localPlayerGui then
    warn("[ARMY] PlayerGui is unavailable.")
    return
end

pcall(removePrevious, localPlayerGui)
standaloneGui.Parent = localPlayerGui
standaloneGui.DisplayOrder = 999
pcall(function() standaloneGui.OnTopOfCoreBlur = true end)

local standalonePanel = Instance.new("Frame")
standalonePanel.Name = "Panel"
standalonePanel.Size = UDim2.new(0,720,0,540)
standalonePanel.Position = UDim2.new(0.5,0,0.5,0)
standalonePanel.AnchorPoint = Vector2.new(0.5,0.5)
standalonePanel.BackgroundColor3 = Color3.fromRGB(18,22,30)
standalonePanel.BackgroundTransparency = 0
standalonePanel.BorderSizePixel = 0
standalonePanel.Visible = true
standalonePanel.Parent = standaloneGui
print("[ARMY] UI bootstrap mounted in PlayerGui")

local startupText = Instance.new("TextLabel")
startupText.Name = "StartupMessage"
startupText.Position = UDim2.new(0,20,0,60)
startupText.Size = UDim2.new(1,-40,1,-80)
startupText.BackgroundTransparency = 0
startupText.BackgroundColor3 = Color3.fromRGB(30,38,52)
startupText.Text = "COMMAND AN ARMY · BOOTING\nPlayerGui mounted OK\nĐang tạo giao diện..."
startupText.TextColor3 = Color3.fromRGB(231,240,255)
startupText.Font = Enum.Font.SourceSans
startupText.TextSize = 20
startupText.TextWrapped = true
startupText.ZIndex = 100
startupText.TextXAlignment = Enum.TextXAlignment.Center
startupText.TextYAlignment = Enum.TextYAlignment.Center
startupText.Parent = standalonePanel
local startupClose = Instance.new("TextButton")
startupClose.Text = "X"
startupClose.Size = UDim2.new(0,34,0,30)
startupClose.Position = UDim2.new(1,-42,0,8)
startupClose.ZIndex = 101
startupClose.Parent = standalonePanel
startupClose.MouseButton1Click:Connect(function() standaloneGui:Destroy() end)

-- Render this actual window once before starting the larger initialization.
task.wait()
if not standaloneGui.Parent then return end

-- This flag lets the error handler keep a working UI visible instead of
-- covering the whole window with the startup layer when a later subsystem fails.
local interfaceShellReady = false
local function initializeInterface()
--==================================================

-- COMMAND AN ARMY - AUTO LOBBY + TROOP CYCLE (VOTING / LIFECYCLE FIX)

--==================================================

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PathfindingService = game:GetService("PathfindingService")

local RunService = game:GetService("RunService")

local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer

--==================================================

-- REMOTES

--==================================================

-- Resolve these after the interface is visible; never block GUI creation.
local Remotes
local LobbyTeleportRequest
local TeamRequest
local SupplyPointRequest
local TroopStateRequest
local Controls

--==================================================

-- CLEAN OLD INSTANCE

--==================================================

-- Previous instances are cleaned up by their GUI lifecycle, without globals.

--==================================================

