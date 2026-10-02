-- START / STOP

--==================================================

local function stopAutomation()
    STATE.enabled = false
    STATE.runId += 1
    local worker = STATE.worker
    STATE.worker = nil
    if worker and worker ~= coroutine.running() and coroutine.status(worker) ~= "dead" then
        pcall(task.cancel, worker)
    end
    stopContinueWatcher()
    clearMovementConnections()
    stopTroopPathFilter()
    pcall(stopMovement)
    pcall(function() Controls:Enable() end)
    STATE.pendingSlot = nil
    STATE.pendingUntil = 0
    STATE.currentCamp = nil
    STATE.troopActive = false
    STATE.roundTeam = nil
    setRunningVisual(false)
    if gui.Parent then setStatus("Stopped") end
end

local function startAutomation()
    if not STATE.ready then
        setStatus("Chưa sẵn sàng", STATE.initReason)
        return
    end
    if STATE.enabled or not gui.Parent then return end
    STATE.runId += 1
    local runId = STATE.runId
    STATE.enabled = true
    STATE.phase = "WAITING"
    STATE.lobbyPreferences = nil
    STATE.location = nil
    STATE.lobbyPlayRequested = false
    STATE.lobbyPlayRequestedAt = 0
    STATE.lobbyVoteName = nil
    STATE.lobbyVoteChoice = nil

    STATE.lastSlot = nil
    STATE.activeSlot = nil
    STATE.zeroSince = nil
    STATE.pendingSlot = nil
    STATE.pendingUntil = 0
    STATE.currentCamp = nil
    STATE.troopActive = false
    STATE.lastAttackAt = 0
    setRunningVisual(true)
    -- Save the thread before scheduling it, including synchronous completion.
    local worker = coroutine.create(function()
        local ok, err = xpcall(mainLoop, function(message)
            return debug.traceback(tostring(message), 2)
        end)
        if STATE.runId ~= runId then return end
        if not ok then
            warn("[AUTO ERROR]", err)
            setStatus("Script error", err)
        end
        STATE.enabled = false
        STATE.worker = nil
        stopContinueWatcher()
        clearMovementConnections()
        stopTroopPathFilter()
        pcall(stopMovement)
        pcall(function() Controls:Enable() end)
        STATE.pendingSlot = nil
        STATE.pendingUntil = 0
        STATE.currentCamp = nil
        STATE.troopActive = false
        setRunningVisual(false)
    end)
    STATE.worker = worker
    task.spawn(worker)
end

local function destroyAutomation()
    stopAutomation()
    if STATE.initWorker and coroutine.status(STATE.initWorker) ~= "dead" then
        pcall(task.cancel, STATE.initWorker)
    end
    for _, connection in ipairs(STATE.connections) do connection:Disconnect() end
    table.clear(STATE.connections)
    if STATE.infoWorker and coroutine.status(STATE.infoWorker) ~= "dead" then
        pcall(task.cancel, STATE.infoWorker)
    end
    if gui.Parent then gui:Destroy() end
end

gui.Destroying:Connect(function()
    STATE.enabled = false
    STATE.runId += 1
    for _, key in ipairs({"worker", "initWorker", "continueWorker", "infoWorker"}) do
        local worker = STATE[key]
        STATE[key] = nil
        if worker and worker ~= coroutine.running() and coroutine.status(worker) ~= "dead" then
            pcall(task.cancel, worker)
        end
    end
    pcall(releaseContinueClick)
    pcall(clearMovementConnections)
    pcall(stopTroopPathFilter)
    pcall(stopMovement)
    if Controls then pcall(function() Controls:Enable() end) end
    for _, connection in ipairs(STATE.connections) do pcall(function() connection:Disconnect() end) end
    table.clear(STATE.connections)
end)

local shutdownEvent = Instance.new("BindableEvent")
shutdownEvent.Name = "StandaloneShutdown"
shutdownEvent.Parent = gui
shutdownEvent.Event:Connect(destroyAutomation)

STATE.destroy = destroyAutomation
STATE.stop = stopAutomation


--==================================================

-- GUI BUTTONS

--==================================================

-- Settings controls are wired after the automation helpers have been declared.
UI.onChange=function(key)
    if key=="IgnoreTroopsInPathfinding" or key=="__all" then
        if STATE.enabled and CONFIG.IgnoreTroopsInPathfinding then startTroopPathFilter()
        else stopTroopPathFilter() end
    end
    UI.message("Đã cập nhật. Map: lượt lobby kế tiếp • Team: lần join kế tiếp • Di chuyển: lượt di chuyển kế tiếp")
end
UI.toggle(lobbyPage,"Tự vote map","AutoVote")
UI.toggle(lobbyPage,"Tự join khi có trận","AutoJoin")
UI.toggle(lobbyPage,"Tự chơi trận tiếp theo","AutoNextRound")
UI.choice(lobbyPage,"Không có map ưu tiên","MapFallback",{"Available","Wait"},{"Map khác đang có","Chờ, không vote"})
UI.note(lobbyPage,"Ưu tiên từ trên xuống. TẮT = không vote map đó. Thay đổi áp dụng từ lượt lobby tiếp theo.")
UI.voteInfo=UI.note(lobbyPage,"Map đang vote: đang chờ dữ liệu...")
UI.mapHolder=make("Frame",{Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,BackgroundTransparency=1},lobbyPage)
function UI.renderMaps()
    UI.mapHolder:ClearAllChildren()
    make("UIListLayout",{Padding=UDim.new(0,6),SortOrder=Enum.SortOrder.LayoutOrder},UI.mapHolder)
    for index,name in ipairs(CONFIG.MapPriority) do
        local controls,_,row=UI.row(UI.mapHolder,tostring(index)..". "..name)
        row.LayoutOrder=index
        local toggle=button(controls,CONFIG.MapEnabled[name]~=false and "BẬT" or "TẮT",UDim2.new(1,-72,1,0))
        local up=button(controls,"↑",UDim2.fromOffset(30,38),UDim2.new(1,-66,0,0))
        local down=button(controls,"↓",UDim2.fromOffset(30,38),UDim2.new(1,-32,0,0))
        toggle.Activated:Connect(function()
            CONFIG.MapEnabled[name]=CONFIG.MapEnabled[name]==false
            UI.renderMaps(); UI.onChange("MapEnabled")
        end)
        local function reorder(delta)
            local destination=index+delta
            if destination<1 or destination>#CONFIG.MapPriority then return end
            CONFIG.MapPriority[index],CONFIG.MapPriority[destination]=CONFIG.MapPriority[destination],CONFIG.MapPriority[index]
            UI.renderMaps(); UI.onChange("MapPriority")
        end
        up.Activated:Connect(function() reorder(-1) end)
        down.Activated:Connect(function() reorder(1) end)
    end
end
UI.note(lobbyPage,"Map mới trên bảng vote sẽ được thêm vào danh sách khi tải được dữ liệu.")
UI.number(lobbyPage,"Giữ trên ô vote (giây)","VoteHoldTime",0.3,5,0.1)
UI.number(lobbyPage,"Chờ bảng vote (giây)","VoteSearchTimeout",2,30,1)
UI.number(lobbyPage,"Số lần thử vote","VoteRetries",1,6,1)

UI.toggle(troopPage,"Tự di chuyển về camp","AutoCamp")
UI.choice(troopPage,"Chọn camp","CampMode",{"Nearest","Selected"},{"Gần nhất / đang đứng","Camp chỉ định"})
local campControls=UI.row(troopPage,"Camp chỉ định (bấm để đổi)")
UI.campButton=button(campControls,"Chờ dữ liệu",UDim2.new(1,0,1,0))
UI.campNames={}
UI.campButton.Activated:Connect(function()
    if #UI.campNames==0 then UI.message("Chưa có camp của team hiện tại. Vào trận rồi chọn lại."); return end
    local index=table.find(UI.campNames,CONFIG.SelectedCamp) or 0
    CONFIG.CampMode="Selected"
    UI.change("SelectedCamp",UI.campNames[index % #UI.campNames+1])
end)
UI.toggle(troopPage,"Tự spawn / xoay slot lính","AutoSpawn")
UI.toggle(troopPage,"Tự ra lệnh Attack","AutoAttack")
UI.note(troopPage,"Slot từ trên xuống; bỏ qua slot TẮT, hết lính hoặc chết. Tên lính được cập nhật khi ở camp.")
UI.slotNames={}
UI.slotHolder=make("Frame",{Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,BackgroundTransparency=1},troopPage)
function UI.renderSlots()
    UI.slotHolder:ClearAllChildren()
    make("UIListLayout",{Padding=UDim.new(0,6),SortOrder=Enum.SortOrder.LayoutOrder},UI.slotHolder)
    for index,slot in ipairs(CONFIG.SlotOrder) do
        local controls,_,row=UI.row(UI.slotHolder,"Slot "..slot.." · "..(UI.slotNames[slot] or "Chưa có dữ liệu"))
        row.LayoutOrder=index
        local toggle=button(controls,CONFIG.SlotsEnabled[slot] and "BẬT" or "TẮT",UDim2.new(1,-72,1,0))
        local up=button(controls,"↑",UDim2.fromOffset(30,38),UDim2.new(1,-66,0,0))
        local down=button(controls,"↓",UDim2.fromOffset(30,38),UDim2.new(1,-32,0,0))
        toggle.Activated:Connect(function()
            CONFIG.SlotsEnabled[slot]=not CONFIG.SlotsEnabled[slot]
            UI.renderSlots(); UI.onChange("SlotsEnabled")
        end)
        local function reorder(delta)
            local destination=index+delta
            if destination<1 or destination>#CONFIG.SlotOrder then return end
            CONFIG.SlotOrder[index],CONFIG.SlotOrder[destination]=CONFIG.SlotOrder[destination],CONFIG.SlotOrder[index]
            UI.renderSlots(); UI.onChange("SlotOrder")
        end
        up.Activated:Connect(function() reorder(-1) end)
        down.Activated:Connect(function() reorder(1) end)
    end
end
UI.number(troopPage,"Kiểm tra / về camp (giây)","CampCheckInterval",1,120,1)
UI.number(troopPage,"Gửi lại Attack (giây)","AttackInterval",1,30,1)
UI.number(troopPage,"Chờ xác nhận spawn (giây)","SpawnPendingTimeout",3,30,1)

UI.choice(movementPage,"Cách di chuyển","MovementMode",{"Walk","TP"},{"Đi bộ (mặc định)","TP"})
UI.note(movementPage,"Đi bộ: giữ cách chạy và tìm đường hiện tại. TP: chuyển tới đích, rồi kiểm tra vị trí thực. Áp dụng cho cả vote và camp ở lần di chuyển kế tiếp.")
UI.toggle(movementPage,"Bỏ qua NPC khi tính đường","IgnoreTroopsInPathfinding")
UI.note(movementPage,"Nâng cao · Các thông số tìm đường bên dưới dùng cho chế độ Đi bộ.")
UI.number(movementPage,"Thời gian xác định kẹt (giây)","StuckTimeout",1,10,0.5)
UI.number(movementPage,"Số lần repath mỗi lượt","MaxRepaths",1,15,1)
UI.number(movementPage,"Chờ thử lại camp (giây)","CampRetryDelay",1,15,1)
UI.number(movementPage,"Giới hạn mỗi waypoint (giây)","WaypointTimeout",5,60,1)
UI.number(movementPage,"Giới hạn đi tới ô vote (giây)","MoveTimeout",3,60,1)

UI.toggle(utilitiesPage,"Tự bấm Click anywhere to continue","AutoContinue")
UI.number(utilitiesPage,"Nghỉ giữa lần bấm Continue (giây)","ContinueClickInterval",0.5,5,0.5)
UI.number(utilitiesPage,"Kích thước UI","UIScale",0.65,1.4,0.05)
UI.number(utilitiesPage,"Độ trong suốt","UITransparency",0,0.7,0.05)
UI.choice(utilitiesPage,"Phím ẩn / hiện","UIHotkey",{"RightControl","LeftAlt","F4","F8"})
local recenter=button(utilitiesPage,"Đưa UI về giữa màn hình",UDim2.new(1,-8,0,34))
recenter.Activated:Connect(function() main.Position=UDim2.fromScale(0.5,0.5); UI.fit() end)
UI.note(utilitiesPage,"Preset · Đặt tên rồi Lưu / Tải. Có lưu file nếu môi trường hỗ trợ; nếu không, giữ trong phiên hiện tại.")
local presetControls=UI.row(utilitiesPage,"Tên preset")
UI.presetName=make("TextBox",{Size=UDim2.fromScale(1,1),Text="Mac dinh",ClearTextOnFocus=false,
    BackgroundColor3=Color3.fromRGB(35,42,55),TextColor3=Color3.new(1,1,1),Font=Enum.Font.SourceSans,
    TextSize=13,BorderSizePixel=0},presetControls)
corner(UI.presetName)
UI.presetInfo=UI.note(utilitiesPage,"")
local presetRow=make("Frame",{Size=UDim2.new(1,-8,0,36),BackgroundTransparency=1},utilitiesPage)
local savePreset=button(presetRow,"Lưu",UDim2.new(0.31,0,1,0))
local loadPreset=button(presetRow,"Tải",UDim2.new(0.31,0,1,0),UDim2.fromScale(0.345,0))
local resetPreset=button(presetRow,"Mặc định",UDim2.new(0.31,0,1,0),UDim2.fromScale(0.69,0))

UI.numericLimits={VoteHoldTime={0.3,5},VoteSearchTimeout={2,30},VoteRetries={1,6,true},
    CampCheckInterval={1,120},AttackInterval={1,30},SpawnPendingTimeout={3,30},
    StuckTimeout={1,10},MaxRepaths={1,15,true},CampRetryDelay={1,15},WaypointTimeout={5,60},
    MoveTimeout={3,60},ContinueClickInterval={0.5,5},UIScale={0.65,1.4},UITransparency={0,0.7}}
UI.enums={Team={"Attackers","Defenders"},MovementMode={"Walk","TP"},CampMode={"Nearest","Selected"},
    MapFallback={"Available","Wait"},UIHotkey={"RightControl","LeftAlt","F4","F8"}}
function UI.validateConfig(data)
    assert(type(data)=="table","Preset không hợp lệ")
    local result=copySettings(DEFAULT_CONFIG)
    for key,value in pairs(result) do
        if type(value)=="boolean" and type(data[key])=="boolean" then result[key]=data[key] end
    end
    for key,limits in pairs(UI.numericLimits) do
        local value=data[key]
        if type(value)=="number" and value==value and math.abs(value)<math.huge then
            value=math.clamp(value,limits[1],limits[2])
            result[key]=limits[3] and math.round(value) or value
        end
    end
    for key,values in pairs(UI.enums) do if table.find(values,data[key]) then result[key]=data[key] end end
    if type(data.SelectedCamp)=="string" then result.SelectedCamp=data.SelectedCamp:sub(1,100) end
    if type(data.MapPriority)=="table" then
        result.MapPriority={}
        for _,name in ipairs(data.MapPriority) do
            if type(name)=="string" and #result.MapPriority<30 then
                name=normalizeMapName(name):sub(1,60)
                if name~="" and not table.find(result.MapPriority,name) then table.insert(result.MapPriority,name) end
            end
        end
        if #result.MapPriority==0 then result.MapPriority=copySettings(DEFAULT_CONFIG.MapPriority) end
    end
    result.MapEnabled={}
    for _,name in ipairs(result.MapPriority) do
        result.MapEnabled[name]=not (type(data.MapEnabled)=="table" and data.MapEnabled[name]==false)
    end
    if type(data.SlotOrder)=="table" then
        result.SlotOrder={}
        for _,slot in ipairs(data.SlotOrder) do
            if type(slot)=="number" and slot%1==0 and slot>=1 and slot<=4 and not table.find(result.SlotOrder,slot) then
                table.insert(result.SlotOrder,slot)
            end
        end
        for slot=1,4 do if not table.find(result.SlotOrder,slot) then table.insert(result.SlotOrder,slot) end end
    end
    if type(data.SlotsEnabled)=="table" then
        for slot=1,4 do result.SlotsEnabled[slot]=data.SlotsEnabled[slot]~=false and data.SlotsEnabled[tostring(slot)]~=false end
    end
    return result
end
local savedPresets = {}
UI.presetFile="command_army_auto_presets.json"
function UI.readPresets()
    if type(readfile)=="function" then
        local ok,data=pcall(function() return HttpService:JSONDecode(readfile(UI.presetFile)) end)
        if ok and type(data)=="table" and data.version==1 and type(data.presets)=="table" then
            for name,preset in pairs(data.presets) do
                if type(name)=="string" and type(preset)=="table" and not savedPresets[name] then
                    savedPresets[name]=preset
                end
            end
        end
    end
end
function UI.updatePresetInfo()
    local names={}
    for name in pairs(savedPresets) do table.insert(names,name) end
    table.sort(names)
    UI.presetInfo.Text="Đã lưu: "..(#names>0 and table.concat(names,", ") or "chưa có preset")
end
function UI.applyPreset(data)
    CONFIG=UI.validateConfig(data)
    UI.onChange("__all")
    UI.renderMaps(); UI.renderSlots(); UI.refresh()
end
savePreset.Activated:Connect(function()
    local name=UI.presetName.Text:match("^%s*(.-)%s*$"):sub(1,48)
    if name=="" then UI.message("Nhập tên preset trước."); return end
    UI.readPresets()
    savedPresets[name]=copySettings(CONFIG)
    local saved=false
    if type(writefile)=="function" then
        saved=pcall(function() writefile(UI.presetFile,HttpService:JSONEncode({version=1,presets=savedPresets})) end)
    end
    UI.updatePresetInfo()
    UI.message("Đã lưu '"..name.."'"..(saved and " vào file." or " trong phiên hiện tại."))
end)
loadPreset.Activated:Connect(function()
    UI.readPresets(); UI.updatePresetInfo()
    local name=UI.presetName.Text:match("^%s*(.-)%s*$"):sub(1,48)
    local data=savedPresets[name]
    if not data then UI.message("Không tìm thấy preset: "..name); return end
    local ok,err=pcall(UI.applyPreset,data)
    UI.message(ok and ("Đã tải '"..name.."'. Map mới áp dụng ở lượt lobby tiếp theo.") or tostring(err))
end)
resetPreset.Activated:Connect(function() UI.applyPreset(DEFAULT_CONFIG); UI.message("Đã khôi phục cấu hình mặc định, di chuyển = Đi bộ.") end)

function UI.updateDynamic()
    UI.fit()
    UI.summary.Text="Di chuyển: "..CONFIG.MovementMode.."  |  Camp: "..(STATE.currentCamp and STATE.currentCamp.Name or "—")
        .."\nThứ tự slot: "..table.concat(CONFIG.SlotOrder," → ")

    -- Show the maps that are ACTUALLY on the current vote board, not just the
    -- configured priority list. This also makes vote detection easy to debug.
    local choices, voteReady=getVoteChoices()
    local visibleVotes={}
    for name in pairs(choices) do table.insert(visibleVotes,name) end
    table.sort(visibleVotes)
    if #visibleVotes>0 then
        UI.voteInfo.Text="Map đang vote: "..table.concat(visibleVotes,"  |  ")
            ..(voteReady and "" or "  (đang tải)")
    else
        UI.voteInfo.Text="Map đang vote: chưa đọc được / chưa mở bảng vote"
    end

    local newNames={}
    for _,name in ipairs(visibleVotes) do
        if not table.find(CONFIG.MapPriority,name) then table.insert(newNames,name) end
    end
    if #newNames>0 then
        for _,name in ipairs(newNames) do
            table.insert(CONFIG.MapPriority,name)
            CONFIG.MapEnabled[name]=true
        end
        UI.renderMaps()
    end

    local supplies,prefix=getSuppliesFolder(),getTeamSupplyPrefix()
    UI.campNames={}
    if supplies and prefix then
        for _,supply in ipairs(supplies:GetChildren()) do
            if supply.Name:sub(1,#prefix)==prefix and getCapturePoint(supply) then
                table.insert(UI.campNames,supply.Name)
            end
        end
        table.sort(UI.campNames)
    end
    UI.campButton.Text=(CONFIG.SelectedCamp~="" and CONFIG.SelectedCamp or "Chưa chọn").."  ›"

    -- Read equipped units from MatchUI.SupplyPoint.Loadout when available,
    -- otherwise fall back to HUD.Loadout in the lobby.
    local units=getEquippedUnits()
    local changed=false
    for slot=1,4 do
        local name=units[slot] and units[slot].name or "Trống / chưa tải"
        if UI.slotNames[slot]~=name then
            changed=true
            UI.slotNames[slot]=name
        end
    end
    if changed then UI.renderSlots() end
end
UI.renderMaps(); UI.renderSlots(); UI.updatePresetInfo(); UI.refresh()

teamButton.MouseButton1Click:Connect(

    function()

        if CONFIG.Team == "Attackers" then

            CONFIG.Team = "Defenders"

        else

            CONFIG.Team = "Attackers"

        end

        refreshTeamButton()
        UI.onChange("Team")

        if STATE.enabled then

            setStatus(

                "Team changed",

                CONFIG.Team

                    .. " will be used on the next join"

            )

        end

    end

)

startButton.MouseButton1Click:Connect(

    function()

        if STATE.enabled then

            stopAutomation()

        else

            startAutomation()

        end

    end

)

closeButton.MouseButton1Click:Connect(destroyAutomation)

--==================================================

