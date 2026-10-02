-- GUI LIVE INFO

--==================================================

STATE.infoWorker = task.spawn(function()
    local lastError
    while gui.Parent do
        local ok, err = xpcall(function()
            local map = getActiveMapName() or "None"
            local team = getCurrentTeam() or "None"
            local area = getCurrentArea()
            infoLabel.Text = "Map: " .. map .. "    |    Team: " .. team
                .. "\nArea: " .. area .. "    |    Config: " .. CONFIG.Team
            UI.updateDynamic()
        end, function(message)
            return debug.traceback(tostring(message), 2)
        end)
        if not ok then
            local short = tostring(err):gsub("\n.*", "")
            infoLabel.Text = "Lỗi đọc trạng thái: " .. short
            if short ~= lastError then
                lastError = short
                warn("[ARMY UI UPDATE] " .. tostring(err))
                UI.message("Lỗi cập nhật GUI: " .. short)
            end
        else
            lastError = nil
        end
        task.wait(0.5)
    end
end)


setStatus("Đang khởi tạo", "Giao diện đã sẵn sàng; đang tìm thành phần game...")
STATE.initWorker = coroutine.create(function()
    while gui.Parent and not STATE.ready do
        local loaded, problem = pcall(function()
            local shared = ReplicatedStorage:FindFirstChild("Shared")
            Remotes = shared and shared:FindFirstChild("Remotes")
            if not Remotes then return "Chờ ReplicatedStorage.Shared.Remotes" end
            LobbyTeleportRequest = Remotes:FindFirstChild("LobbyMarkerTeleportRequest")
            TeamRequest = Remotes:FindFirstChild("TeamRequest")
            SupplyPointRequest = Remotes:FindFirstChild("SupplyPointRequest")
            TroopStateRequest = Remotes:FindFirstChild("TroopStateRequest")
            local missing = {}
            if not LobbyTeleportRequest then table.insert(missing,"LobbyMarkerTeleportRequest") end
            if not TeamRequest then table.insert(missing,"TeamRequest") end
            if not SupplyPointRequest then table.insert(missing,"SupplyPointRequest") end
            if not TroopStateRequest then table.insert(missing,"TroopStateRequest") end
            if #missing > 0 then return "Chờ remote: " .. table.concat(missing,", ") end
            if not Controls then
                local scripts = player:FindFirstChild("PlayerScripts")
                local module = scripts and scripts:FindFirstChild("PlayerModule")
                if not module then return "Chờ PlayerScripts.PlayerModule" end
                STATE.initReason = "Đang tải PlayerModule / Controls..."
                setStatus("Đang khởi tạo", STATE.initReason)
                local playerModule = require(module)
                local controls = playerModule:GetControls()
                if not controls or type(controls.Disable)~="function" or type(controls.Enable)~="function" then
                    return "PlayerModule không cung cấp Controls phù hợp"
                end
                Controls = controls
            end
            return nil
        end)
        if not gui.Parent then return end
        if loaded and problem == nil then
            STATE.ready = true
            STATE.initReason = nil
            setRunningVisual(false)
            setStatus("Ready", "Chọn cấu hình rồi bấm START")
            return
        end
        STATE.initReason = tostring(problem)
        setStatus(loaded and "Đang chờ game" or "Lỗi khởi tạo", STATE.initReason)
        task.wait(1)
    end
end)
task.spawn(STATE.initWorker)

end
local initialized, startupError = xpcall(initializeInterface, function(message)
    return debug.traceback(tostring(message), 2)
end)
if initialized then
    if startupText.Parent then startupText:Destroy() end
    if startupClose.Parent then startupClose:Destroy() end
else
    warn("[ARMY UI ERROR] " .. tostring(startupError))
    if standaloneGui.Parent then
        startupText.Text = (interfaceShellReady and "Lỗi khởi tạo logic (GUI vẫn dùng được):\n" or "Không tạo được UI:\n")
            .. tostring(startupError):sub(1,700)
        startupText.TextSize = 14
        startupText.TextXAlignment = Enum.TextXAlignment.Left
        startupText.TextYAlignment = Enum.TextYAlignment.Top
        startupText.BackgroundColor3 = Color3.fromRGB(74,31,36)
        startupText.BackgroundTransparency = 0.08
        if interfaceShellReady then
            startupText.Position = UDim2.new(0,12,1,-112)
            startupText.Size = UDim2.new(1,-24,0,100)
        else
            startupText.Position = UDim2.new(0,20,0,60)
            startupText.Size = UDim2.new(1,-40,1,-80)
        end
        startupText.Visible = true
        startupClose.Visible = true
    end
end
