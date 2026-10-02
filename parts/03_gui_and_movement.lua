-- GUI

--==================================================

local UI = {pages = {}, tabs = {}, refreshers = {}, logs = {}, collapsed = false}
local function make(class, props, parent)
    local object = Instance.new(class)
    for key, value in pairs(props) do object[key] = value end
    object.Parent = parent
    return object
end
local function corner(object, radius)
    make("UICorner", {CornerRadius = UDim.new(0, radius or 7)}, object)
end
local function button(parent, text, size, position)
    local object = make("TextButton", {Text = text, Size = size or UDim2.fromOffset(100,32),
        Position = position or UDim2.new(), BackgroundColor3 = Color3.fromRGB(45,51,65),
        BorderSizePixel = 0, TextColor3 = Color3.fromRGB(232,237,246), TextSize = 13,
        Font = Enum.Font.SourceSans, AutoButtonColor = true}, parent)
    corner(object)
    return object
end
local gui = standaloneGui
local main = standalonePanel
corner(main,12)
make("UIStroke", {Color=Color3.fromRGB(62,75,96), Thickness=1}, main)
UI.scale = make("UIScale", {Scale=1}, main)
local header = make("Frame", {Size=UDim2.new(1,0,0,48), BackgroundTransparency=1, Active=true}, main)
make("TextLabel", {Text="COMMAND AN ARMY · STANDALONE", Size=UDim2.new(1,-230,1,0),
    Position=UDim2.fromOffset(16,0), BackgroundTransparency=1, Font=Enum.Font.SourceSansBold,
    TextSize=17, TextColor3=Color3.fromRGB(239,244,255), TextXAlignment=Enum.TextXAlignment.Left}, header)
local startButton = button(header,"START",UDim2.fromOffset(90,32),UDim2.new(1,-174,0,8))
local minimizeButton = button(header,"−",UDim2.fromOffset(30,32),UDim2.new(1,-76,0,8))
local closeButton = button(header,"×",UDim2.fromOffset(30,32),UDim2.new(1,-40,0,8))
local body = make("Frame", {Position=UDim2.fromOffset(12,56), Size=UDim2.new(1,-24,1,-140),
    BackgroundTransparency=1}, main)
UI.sidebar = make("Frame", {Size=UDim2.new(0,128,1,0), BackgroundTransparency=1}, body)
make("UIListLayout", {Padding=UDim.new(0,8),SortOrder=Enum.SortOrder.LayoutOrder},UI.sidebar)
UI.content = make("Frame", {Position=UDim2.fromOffset(140,0),Size=UDim2.new(1,-140,1,0),
    BackgroundColor3=Color3.fromRGB(25,30,40),BorderSizePixel=0},body)
corner(UI.content,8)
UI.footer = make("Frame", {Position=UDim2.new(0,12,1,-76),Size=UDim2.new(1,-24,0,64),
    BackgroundTransparency=1},main)
local statusLabel = make("TextLabel", {Size=UDim2.new(1,0,0,36), Text="Ready",
    BackgroundTransparency=1,TextColor3=Color3.fromRGB(119,210,244), Font=Enum.Font.SourceSans,
    TextSize=13, TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left},UI.footer)
UI.notice = make("TextLabel", {Position=UDim2.fromOffset(0,40),Size=UDim2.new(1,0,0,24),
    Text="RightControl: ẩn/hiện  •  Kéo thanh tiêu đề để di chuyển",BackgroundTransparency=1,
    TextColor3=Color3.fromRGB(162,174,195),Font=Enum.Font.SourceSans,TextSize=12,
    TextXAlignment=Enum.TextXAlignment.Left},UI.footer)
UI.reopen = button(gui,"ARMY  •  Mở UI",UDim2.fromOffset(120,34),UDim2.new(0,12,1,-48))
UI.reopen.Visible=false

function UI.message(text) UI.notice.Text=text end
function UI.fit()
    local camera=workspace.CurrentCamera
    local view=camera and camera.ViewportSize or Vector2.new(1280,720)
    UI.scale.Scale=math.min(CONFIG.UIScale,math.max(0.3,(view.X-24)/720),math.max(0.3,(view.Y-24)/540))
    main.BackgroundTransparency=CONFIG.UITransparency
    UI.content.BackgroundTransparency=CONFIG.UITransparency
end
function UI.refresh()
    for _, refresh in ipairs(UI.refreshers) do refresh() end
    UI.fit()
end
function UI.change(key,value)
    CONFIG[key]=value
    if UI.onChange then UI.onChange(key) end
    UI.refresh()
end
function UI.page(name)
    local page=make("ScrollingFrame", {Name=name,Size=UDim2.fromScale(1,1),
        BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=4,CanvasSize=UDim2.new(),
        AutomaticCanvasSize=Enum.AutomaticSize.None,ScrollingDirection=Enum.ScrollingDirection.Y,
        Visible=false},UI.content)
    make("UIPadding",{PaddingTop=UDim.new(0,12),PaddingBottom=UDim.new(0,12),
        PaddingLeft=UDim.new(0,12),PaddingRight=UDim.new(0,12)},page)
    local layout=make("UIListLayout",{Padding=UDim.new(0,8),SortOrder=Enum.SortOrder.LayoutOrder},page)
    local function updateCanvas()
        page.CanvasSize=UDim2.fromOffset(0,layout.AbsoluteContentSize.Y+24)
    end
    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvas)
    task.defer(updateCanvas)
    local tab=button(UI.sidebar,name,UDim2.new(1,0,0,38))
    tab.LayoutOrder=#UI.tabs+1
    UI.pages[name]=page
    table.insert(UI.tabs,{name=name,button=tab})
    tab.Activated:Connect(function() UI.select(name) end)
    return page
end
function UI.select(name)
    for key,page in pairs(UI.pages) do page.Visible=key==name end
    for _,tab in ipairs(UI.tabs) do
        tab.button.BackgroundColor3=tab.name==name and Color3.fromRGB(40,104,145) or Color3.fromRGB(33,40,53)
    end
end
function UI.note(parent,text)
    return make("TextLabel",{Text=text,Size=UDim2.new(1,-8,0,28),AutomaticSize=Enum.AutomaticSize.Y,
        BackgroundTransparency=1,TextColor3=Color3.fromRGB(168,182,204),Font=Enum.Font.SourceSans,
        TextSize=12,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left},parent)
end
function UI.row(parent,text)
    local row=make("Frame",{Size=UDim2.new(1,-8,0,38),BackgroundTransparency=1},parent)
    local label=make("TextLabel",{Text=text,Size=UDim2.new(0.55,-10,1,0),BackgroundTransparency=1,
        TextColor3=Color3.fromRGB(226,233,244),Font=Enum.Font.SourceSans,TextSize=13,TextWrapped=true,
        TextXAlignment=Enum.TextXAlignment.Left},row)
    local controls=make("Frame",{Position=UDim2.fromScale(0.55,0),Size=UDim2.fromScale(0.45,1),
        BackgroundTransparency=1},row)
    return controls,label,row
end
function UI.toggle(parent,text,key)
    local controls=UI.row(parent,text)
    local toggle=button(controls,"",UDim2.new(1,0,1,0))
    table.insert(UI.refreshers,function()
        toggle.Text=CONFIG[key] and "BẬT" or "TẮT"
        toggle.BackgroundColor3=CONFIG[key] and Color3.fromRGB(37,114,94) or Color3.fromRGB(54,59,71)
    end)
    toggle.Activated:Connect(function() UI.change(key,not CONFIG[key]) end)
end
function UI.choice(parent,text,key,values,labels)
    local controls=UI.row(parent,text)
    local picker=button(controls,"",UDim2.new(1,0,1,0))
    table.insert(UI.refreshers,function()
        local index=table.find(values,CONFIG[key]) or 1
        picker.Text=(labels and labels[index] or tostring(values[index])).."  ›"
    end)
    picker.Activated:Connect(function()
        local index=table.find(values,CONFIG[key]) or 1
        UI.change(key,values[index % #values+1])
    end)
    return picker
end
function UI.number(parent,text,key,minimum,maximum,step)
    local controls=UI.row(parent,text)
    local minus=button(controls,"−",UDim2.fromOffset(30,38))
    local input=make("TextBox",{Position=UDim2.fromOffset(34,0),Size=UDim2.new(1,-68,1,0),
        Text=tostring(CONFIG[key]),ClearTextOnFocus=false,BackgroundColor3=Color3.fromRGB(35,42,55),
        TextColor3=Color3.new(1,1,1),Font=Enum.Font.SourceSans,TextSize=13,BorderSizePixel=0},controls)
    corner(input)
    local plus=button(controls,"+",UDim2.fromOffset(30,38),UDim2.new(1,-30,0,0))
    local function apply(value)
        if not value or value~=value or math.abs(value)==math.huge then value=CONFIG[key] end
        value=math.clamp(math.round(value/step)*step,minimum,maximum)
        UI.change(key,tonumber(string.format("%.2f",value)))
    end
    minus.Activated:Connect(function() apply(CONFIG[key]-step) end)
    plus.Activated:Connect(function() apply(CONFIG[key]+step) end)
    input.FocusLost:Connect(function() apply(tonumber(input.Text)) end)
    table.insert(UI.refreshers,function() if not input:IsFocused() then input.Text=tostring(CONFIG[key]) end end)
end

local overview=UI.page("Tổng quan")
local lobbyPage=UI.page("Lobby / Map")
local troopPage=UI.page("Camp / Lính")
local movementPage=UI.page("Di chuyển")
local utilitiesPage=UI.page("Tiện ích")
local teamControls=UI.row(overview,"Team cho lần join kế tiếp")
local teamButton=button(teamControls,"",UDim2.new(1,0,1,0))
local infoLabel=UI.note(overview,"Đang đọc trạng thái...")
UI.summary=UI.note(overview,"")
UI.note(overview,"Nhật ký gần đây")
UI.logLabel=UI.note(overview,"")

local function refreshTeamButton() teamButton.Text=CONFIG.Team.."  ›" end
local function setStatus(titleText,detail)
    if not gui.Parent then return end
    local text=titleText..(detail and ("\n"..tostring(detail)) or "")
    if statusLabel.Text==text then return end
    statusLabel.Text=text
    table.insert(UI.logs,1,os.date("%H:%M:%S").."  "..titleText..(detail and (" — "..tostring(detail)) or ""))
    if #UI.logs>8 then table.remove(UI.logs) end
    UI.logLabel.Text=table.concat(UI.logs,"\n")
    print("[AUTO]",titleText,detail or "")
end
local function setRunningVisual(running)
    if not STATE.ready then
        startButton.Text="WAIT"
        startButton.BackgroundColor3=Color3.fromRGB(67,77,92)
        return
    end
    startButton.Text=running and "STOP" or "START"
    startButton.BackgroundColor3=running and Color3.fromRGB(155,64,73) or Color3.fromRGB(37,126,93)
end
table.insert(UI.refreshers,refreshTeamButton)
minimizeButton.Activated:Connect(function()
    UI.collapsed=not UI.collapsed
    main.Size=UDim2.fromOffset(720,UI.collapsed and 48 or 540)
    body.Visible=not UI.collapsed
    UI.footer.Visible=not UI.collapsed
    minimizeButton.Text=UI.collapsed and "+" or "−"
end)
UI.reopen.Activated:Connect(function() main.Visible=true; UI.reopen.Visible=false end)
do
    local dragInput,dragStart,startPosition
    header.InputBegan:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
            dragInput=input; dragStart=input.Position; startPosition=main.Position
        end
    end)
    table.insert(STATE.connections,UserInputService.InputChanged:Connect(function(input)
        if not dragInput then return end
        if input.UserInputType==Enum.UserInputType.MouseMovement or input==dragInput then
            local delta=input.Position-dragStart
            main.Position=UDim2.new(startPosition.X.Scale,startPosition.X.Offset+delta.X,
                startPosition.Y.Scale,startPosition.Y.Offset+delta.Y)
        end
    end))
    table.insert(STATE.connections,UserInputService.InputEnded:Connect(function(input)
        if input==dragInput or input.UserInputType==Enum.UserInputType.MouseButton1 then dragInput=nil end
    end))
    table.insert(STATE.connections,UserInputService.InputBegan:Connect(function(input,processed)
        if not processed and not UserInputService:GetFocusedTextBox() and input.KeyCode==Enum.KeyCode[CONFIG.UIHotkey] then
            main.Visible=not main.Visible
            UI.reopen.Visible=not main.Visible
        end
    end))
end
UI.select("Tổng quan")
setRunningVisual(false)
UI.refresh()

-- From this point the shell is usable. Do not let the startup label cover it
-- while the game-specific helpers/remotes are being prepared.
interfaceShellReady = true
startupText.Visible = false
startupClose.Visible = false

local function waitSeconds(seconds)

    local startedAt = os.clock()

    while

        STATE.enabled

        and os.clock() - startedAt < seconds

    do

        task.wait(0.05)

    end

    return STATE.enabled

end

local function stopMovement()
    local character = player.Character
    local humanoid = character and character:FindFirstChild("Humanoid")
    if humanoid then humanoid:Move(Vector3.zero, false) end
end

local function clearMovementConnections()
    for connection in pairs(STATE.movementConnections) do
        connection:Disconnect()
    end
    table.clear(STATE.movementConnections)
end

local function withControlsDisabled(callback)
    Controls:Disable()
    local ok, result, reason = pcall(callback)
    pcall(stopMovement)
    pcall(function() Controls:Enable() end)
    if not ok then return false, "MOVEMENT_ERROR: " .. tostring(result) end
    return result, reason
end

local function getObjectPart(object)

    if not object then

        return nil

    end

    if object:IsA("BasePart") then

        return object

    end

    if object:IsA("Model") then

        if object.PrimaryPart then

            return object.PrimaryPart

        end

    end

    return object:FindFirstChildWhichIsA(

        "BasePart",

        true

    )

end

local function getObjectPosition(object)
    if not object then
        return nil
    end

    if object:IsA("BasePart") then
        return object.Position
    end

    if object:IsA("Model") then
        return object:GetPivot().Position
    end

    local part = object:FindFirstChildWhichIsA(
        "BasePart",
        true
    )

    return part and part.Position or nil
end

-- Lobby voting verifies the actual trigger footprint, including thin floor pads.
local function getVotePart(object)
    if not object then return nil end
    if object:IsA("BasePart") then return object end
    for _, name in ipairs(CONFIG.VotePartNames) do
        local part = object:FindFirstChild(name, true)
        if part and part:IsA("BasePart") then return part end
    end
    if object:IsA("Model") and object.PrimaryPart then return object.PrimaryPart end
    -- An arbitrary decorative part or model pivot may be nowhere near the pad.
    local onlyPart
    for _, child in ipairs(object:GetDescendants()) do
        if child:IsA("BasePart") then
            if onlyPart then return nil end
            onlyPart = child
        end
    end
    return onlyPart
end

local function isOnVotePart(root, humanoid, part)
    local position = part.CFrame:PointToObjectSpace(root.Position)
    local half = part.Size / 2
    local marginX = math.min(0.25, half.X * 0.2)
    local marginZ = math.min(0.25, half.Z * 0.2)
    local rootHeight = math.max(3, humanoid.HipHeight + root.Size.Y / 2)
    return math.abs(position.X) <= half.X - marginX
        and math.abs(position.Z) <= half.Z - marginZ
        and position.Y >= -half.Y - 0.5
        and position.Y <= half.Y + rootHeight + 2
end

local function teleportToPosition(position)
    if not STATE.enabled or STATE.continueVisible then return false, "STOPPED_OR_CONTINUE" end
    local character = player.Character
    local humanoid = character and character:FindFirstChild("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root or not humanoid or humanoid.Health <= 0 then return false, "CHARACTER_NOT_READY" end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.RespectCanCollide = true
    local excluded = {character}
    local ground
    -- Resolve a walkable floor below the destination, ignoring troops and ceilings.
    for _ = 1, 12 do
        params.FilterDescendantsInstances = excluded
        local hit = workspace:Raycast(position + Vector3.new(0,6,0), Vector3.new(0,-60,0), params)
        if not hit then break end
        local rig
        local ancestor = hit.Instance.Parent
        while ancestor and ancestor ~= workspace do
            if ancestor:IsA("Model") and (ancestor:FindFirstChildWhichIsA("Humanoid")
                or ancestor:FindFirstChildWhichIsA("AnimationController")) then rig=ancestor; break end
            ancestor=ancestor.Parent
        end
        if rig then table.insert(excluded,rig)
        elseif hit.Position.Y > position.Y+3 then table.insert(excluded,hit.Instance)
        else ground=hit; break end
    end
    if not ground then return false, "TP_NO_GROUND" end
    local clearance=math.max(3,humanoid.HipHeight+root.Size.Y/2)+0.15
    local landing=Vector3.new(position.X,ground.Position.Y+clearance,position.Z)
    humanoid:Move(Vector3.zero,false)
    root.AssemblyLinearVelocity=Vector3.zero
    root.AssemblyAngularVelocity=Vector3.zero
    root.CFrame=CFrame.new(landing)*root.CFrame.Rotation
    return true
end

local function moveToObject(object, stillValid)
    local movementMode = CONFIG.MovementMode
    local part = getVotePart(object)
    if not part then return false, "VOTE_PART_NOT_FOUND" end
    local character = player.Character
    local humanoid = character and character:FindFirstChild("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root then return false, "CHARACTER_NOT_READY" end
    local startedAt = os.clock()
    local insideSince, lastMoveAt = nil, -math.huge
    while STATE.enabled and os.clock() - startedAt < CONFIG.MoveTimeout do
        if not CONFIG.AutoVote then stopMovement(); return false, "AUTO_VOTE_OFF" end
        if STATE.continueVisible then
            stopMovement()
            return false, "CONTINUE_SCREEN"
        end
        if getActiveMapModel() then
            stopMovement()
            return true, "ROUND_STARTED"
        end
        if player.Character ~= character or not root.Parent or humanoid.Health <= 0 then
            stopMovement()
            return false, "CHARACTER_CHANGED"
        end
        if not object.Parent or not part.Parent or (stillValid and not stillValid()) then
            stopMovement()
            return false, "VOTE_CHANGED"
        end
        if isOnVotePart(root, humanoid, part) then
            stopMovement()
            insideSince = insideSince or os.clock()
            if os.clock() - insideSince >= CONFIG.VoteHoldTime then
                return true, "PAD_HELD"
            end
        else
            insideSince = nil
            if os.clock() - lastMoveAt >= 1 then
                -- Refresh MoveTo's built-in timeout; verify the pad ourselves.
                if movementMode == "TP" then
                    local teleported, reason = teleportToPosition(part.Position)
                    if not teleported then return false, reason end
                else
                    humanoid:MoveTo(part.Position)
                end
                lastMoveAt = os.clock()
            end
        end
        task.wait(0.05)
    end
    stopMovement()
    return false, STATE.enabled and "VOTE_MOVE_TIMEOUT" or "STOPPED"
end

local function isPositionInsidePart(

    position,

    part

)

    local localPosition =

        part.CFrame:PointToObjectSpace(

            position

        )

    local halfSize = part.Size / 2

    return

        math.abs(localPosition.X)

            <= halfSize.X

        and math.abs(localPosition.Y)

            <= halfSize.Y

        and math.abs(localPosition.Z)

            <= halfSize.Z

end

--==================================================

