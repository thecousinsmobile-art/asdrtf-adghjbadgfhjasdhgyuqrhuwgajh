-- ==========================================
-- Stand Script – Executor single-file build
-- MAIN: GUI/controller only
-- ALT: stand executor only; GUI hidden
-- GUI button commands relay silently to the alt; chat remains a separate fallback.
-- ==========================================
-- Stand Script – Persistent Target, GOTO/GRAB, Retaliate, Stances, Sendall, Spin
-- Original Owner: ClaysRetake
-- ==========================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local TextChatService = game:GetService("TextChatService")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

-- ==================== CONFIGURATION ====================
-- The account with this exact Roblox username becomes the MAIN / GUI client.
-- Any other account running the script becomes the ALT / stand executor.
-- If the configured owner is NOT in the server, whichever client ran the
-- script becomes the MAIN account automatically so the GUI still appears.
local ORIGINAL_OWNER = "ClayFFA"
-- =======================================================

local currentOwnerName = ORIGINAL_OWNER
local IS_MAIN_ACCOUNT = (Players.LocalPlayer.Name == ORIGINAL_OWNER)
local OWNER_ONLY_GUI = IS_MAIN_ACCOUNT

-- Auto-fallback: if the configured owner isn't here and this client isn't
-- them, run as main so the panel is usable solo.
if not IS_MAIN_ACCOUNT and not Players:FindFirstChild(ORIGINAL_OWNER) then
    IS_MAIN_ACCOUNT = true
    ORIGINAL_OWNER = Players.LocalPlayer.Name
    currentOwnerName = ORIGINAL_OWNER
end

local exclusionList = { [ORIGINAL_OWNER] = true }

local FOLLOW_DISTANCE = 5
local SIDE_OFFSET = 3
local FOLLOW_HEIGHT = 3
local FLOAT_SPEED = 1.5
local FLOAT_HEIGHT = 0.5
local DEEP_UNDERGROUND_DEPTH = 100

local ORBIT_RADIUS = 5
local ORBIT_SPEED = 5
local PUNCH_INTERVAL = 0.2
local MOVE_INTERVAL = 0.1

local IDLE_ANIMATION_ID = "rbxassetid://18450698238"
local STANCE2_ANIMATION_ID = "rbxassetid://17124061663"
local CHAT_EMOTE_ID = "rbxassetid://18614546390"

local currentStance = 1

local SKILL_KEYS = {
    Enum.KeyCode.One,
    Enum.KeyCode.Two,
    Enum.KeyCode.Three,
    Enum.KeyCode.Four
}

local MOVE_RETURN_DELAYS = {1.5, 2.0, 1.0, 2.5}

local instantMovesMode = false
local commandActive = false
local currentIdleTrack = nil
local activeChatEmoteTrack = nil
local guardingActive = false
local standHidden = false
local aggressiveMode = false
local chatSystemEnabled = true
local specificTargetPlayer = nil

-- Forward declaration so setStandVisibility (which appears earlier) can
-- safely reference the function without tripping a nil-call runtime error.
local manageIdleAnimation

-- ======================== RETALIATE STATE ==========================
local retaliateEnabled = false
local retaliateTarget = nil
local retaliateRequested = false
local previousState = nil
local RETALIATE_RANGE = 250

local ownerDamageConn = nil
local lastOwnerHealth = nil
-- ======================================================================

-- ======================== GOTO / GRAB SYSTEM ==========================
local GOTO_LOCATIONS = {
    ["mid"]    = Vector3.new(142, 441, 29),
    ["mt"]     = Vector3.new(315, 671, 416),
    ["mt2"]    = Vector3.new(0, 653, -342),
    ["mte"]    = Vector3.new(-302, 594, -321),
    ["void"]   = Vector3.new(154, 220, 75),
    ["bw"]     = Vector3.new(-130, 440, -373),
    ["atomic"] = Vector3.new(-52, 1580, 25250),
    ["bp"]     = Vector3.new(-42, 1855, 25227),
    ["bp2"]    = Vector3.new(-42, 1469, 25227),
    ["jail"]   = Vector3.new(439, 440, -376),
    ["bsq"]    = Vector3.new(-73, 84, 20358),
    ["dc"]     = Vector3.new(-66, 29, 20383)
}

local GOTO_HEIGHT = 3.319
local GOTO_GROUND_OFFSET = 2
local GOTO_WAIT_BEFORE_Q = 0.219
local GOTO_FREEZE_TIME = 3
local SENDALL_BREATHER = 0.5

local gotoActive = false
local gotoTarget = nil
local gotoFreeze = false
local gotoFreezeCFrame = nil

local sendAllActive = false
local sendAllCancelled = false

local flingActive = false
local flingTarget = nil
local flingToken = 0

local spinningActive = false
local SPIN_RADIUS = 2.8
local SPIN_SPEED = 22
-- ======================================================================

local customChatCmds = {
    "CMDS 1/3: x=stop p=retaliate v=kill s=spin guard=guard target<name>=lock z=emote hide appear ult=G",
    "CMDS 2/3: goto: <user> goto <area> / goto <user> [area] / <user> [area] | sendall <area>=all | block fight on=. block fight off=, | 1-4=fire",
    "CMDS 3/3: give / give<name>=transfer back=reclaim exclude<name> stance1 stance2 co=chatON cf=chatOFF cmds | AREAS: mid mt mt2 mte void bw atomic bp bp2 jail bsq dc"
}

local flingPower = 9e9
local FLING_DURATION = 0.5
local GUARD_RANGE = 50

local ownerChatConnection = nil
local originalOwnerChatConnection = nil
local selfChatConnection = nil

local setupChatListener
local silentRelayExecution = false

-- ======================== SILENT TARGET ESP ========================
local espEnabled = IS_MAIN_ACCOUNT and true or false
local espHighlight = nil
local espLastTarget = nil
-- ==================================================================

-- GUI
local playerGui = LocalPlayer:WaitForChild("PlayerGui")
local screenGui = playerGui:FindFirstChild("StandGUI") or Instance.new("ScreenGui")
screenGui.Name = "StandGUI"
screenGui.ResetOnSpawn = false
screenGui.Enabled = true
screenGui.Parent = playerGui

local guiLabel = nil
if IS_MAIN_ACCOUNT then
    local oldLabel = screenGui:FindFirstChild("StandLabel")
    if oldLabel then
        oldLabel:Destroy()
    end
else
    guiLabel = screenGui:FindFirstChild("StandLabel") or Instance.new("TextLabel")
    guiLabel.Name = "StandLabel"
    guiLabel.Size = UDim2.new(0, 400, 0, 40)
    guiLabel.Position = UDim2.new(0.5, -200, 0, 10)
    guiLabel.BackgroundColor3 = Color3.new(0, 0, 0)
    guiLabel.BackgroundTransparency = 0.5
    guiLabel.TextColor3 = Color3.new(1, 1, 1)
    guiLabel.TextScaled = true
    guiLabel.Font = Enum.Font.SourceSansBold
    guiLabel.Parent = screenGui
end

local function updateGUI()
    if IS_MAIN_ACCOUNT then
        return
    end
    if standHidden then
        guiLabel.Visible = false
        return
    end
    guiLabel.Visible = true
    local modeText = instantMovesMode and "ON (Moves+Punch)" or "OFF (Punch Only)"
    if spinningActive then
        modeText = "SPINNING"
    elseif gotoFreeze then
        modeText = "GOTO FREEZE"
    elseif gotoActive then
        modeText = "GOTO: " .. (gotoTarget and gotoTarget.Name or "?")
    elseif retaliateTarget then
        modeText = "RETALIATING: " .. retaliateTarget.Name
    elseif guardingActive then
        modeText = "GUARDING ACTIVE"
    elseif aggressiveMode then
        modeText = "AGGRESSIVE MODE (V)"
    elseif specificTargetPlayer then
        modeText = "TARGETING: " .. specificTargetPlayer.Name
    elseif retaliateEnabled then
        modeText = "FOLLOW (retaliate ON)"
    else
        modeText = "FOLLOW"
    end
    guiLabel.Text = "Owner: " .. currentOwnerName .. " | Stance " .. currentStance .. " | Mode: " .. modeText
end

local function getOwner()
    return Players:FindFirstChild(currentOwnerName)
end

local function sendChatMessage(messageText)
    if silentRelayExecution then return end
    if not chatSystemEnabled then return end
    local success = pcall(function()
        if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
            local channels = TextChatService:FindFirstChild("TextChannels")
            local generalChannel = channels and channels:FindFirstChild("RBXGeneral")
            if generalChannel then
                generalChannel:SendAsync(messageText)
            end
        else
            game:GetService("ReplicatedStorage"):WaitForChild("DefaultChatSystemChatEvents"):WaitForChild("SayMessageRequest"):FireServer(messageText, "All")
        end
    end)
    if not success then
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Slash, false, game)
        task.wait(0.05)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Slash, false, game)
        task.wait(0.05)
        for i = 1, #messageText do
            local char = messageText:sub(i, i)
            VirtualInputManager:SendText(char)
            task.wait(0.02)
        end
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Return, false, game)
        task.wait(0.05)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Return, false, game)
    end
end

local function sendChatMessageAlways(messageText)
    if silentRelayExecution then return end
    local success = pcall(function()
        if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
            local channels = TextChatService:FindFirstChild("TextChannels")
            local generalChannel = channels and channels:FindFirstChild("RBXGeneral")
            if generalChannel then
                generalChannel:SendAsync(messageText)
            end
        else
            game:GetService("ReplicatedStorage"):WaitForChild("DefaultChatSystemChatEvents"):WaitForChild("SayMessageRequest"):FireServer(messageText, "All")
        end
    end)
    if not success then
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Slash, false, game)
        task.wait(0.05)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Slash, false, game)
        task.wait(0.05)
        for i = 1, #messageText do
            local char = messageText:sub(i, i)
            VirtualInputManager:SendText(char)
            task.wait(0.02)
        end
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Return, false, game)
        task.wait(0.05)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Return, false, game)
    end
end

local function sendEmoteChatMessage(messageText)
    if silentRelayExecution then return end
    local success = pcall(function()
        if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
            local channels = TextChatService:FindFirstChild("TextChannels")
            local generalChannel = channels and channels:FindFirstChild("RBXGeneral")
            if generalChannel then
                generalChannel:SendAsync(messageText)
            end
        else
            game:GetService("ReplicatedStorage"):WaitForChild("DefaultChatSystemChatEvents"):WaitForChild("SayMessageRequest"):FireServer(messageText, "All")
        end
    end)
    if not success then
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Slash, false, game)
        task.wait(0.05)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Slash, false, game)
        task.wait(0.05)
        for i = 1, #messageText do
            local char = messageText:sub(i, i)
            VirtualInputManager:SendText(char)
            task.wait(0.02)
        end
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Return, false, game)
        task.wait(0.05)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Return, false, game)
    end
end


-- ========================= MODERN CLAYSTAND GUI =========================
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local guiOpen = false
local activeTab = "Home"
local selectedGotoPlayer = ""
local selectedGotoArea = "void"
local selectedSendAllArea = "void"
local selectedFlingPlayer = ""

local GUI_THEME = {
    Background = Color3.fromRGB(14, 15, 21),
    Surface = Color3.fromRGB(20, 21, 29),
    Surface2 = Color3.fromRGB(27, 28, 38),
    Button = Color3.fromRGB(34, 35, 48),
    ButtonHover = Color3.fromRGB(46, 45, 65),
    Accent = Color3.fromRGB(104, 92, 180),
    AccentSoft = Color3.fromRGB(72, 64, 125),
    Border = Color3.fromRGB(66, 67, 86),
    Text = Color3.fromRGB(245, 245, 250),
    Muted = Color3.fromRGB(157, 158, 176),
    Danger = Color3.fromRGB(170, 68, 78),
}
local selectedGotoUserId = nil
local selectedFlingUserId = nil
local selectedOwnershipUserId = nil
local selectedMove = nil
local selectedStance = currentStance
local selectedAction = nil
local blockFightEnabled = true
local copiedMainEmoteId = nil

local getActiveStandPlayers

local function make(className, props, parent)
    local obj = Instance.new(className)
    for key, value in pairs(props or {}) do
        obj[key] = value
    end
    obj.Parent = parent
    return obj
end

local guiRoot = make("Frame", {
    Name = "ClayStandWindow",
    Size = UDim2.new(0, 820, 0, 540),
    Position = UDim2.new(0.5, -410, 0.5, -270),
    BackgroundColor3 = GUI_THEME.Background,
    BorderSizePixel = 0,
    Visible = false,
}, screenGui)
make("UICorner", {CornerRadius = UDim.new(0, 14)}, guiRoot)
make("UIStroke", {Thickness = 1, Color = Color3.fromRGB(70, 70, 90), Transparency = 0.2}, guiRoot)

local topBar = make("Frame", {
    Size = UDim2.new(1, 0, 0, 60),
    BackgroundColor3 = GUI_THEME.Surface2,
    BorderSizePixel = 0,
}, guiRoot)
make("UICorner", {CornerRadius = UDim.new(0, 14)}, topBar)

local dragging = false
local dragStart = nil
local dragStartPosition = nil

topBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = input.Position
        dragStartPosition = guiRoot.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
        local delta = input.Position - dragStart
        guiRoot.Position = UDim2.new(
            dragStartPosition.X.Scale,
            dragStartPosition.X.Offset + delta.X,
            dragStartPosition.Y.Scale,
            dragStartPosition.Y.Offset + delta.Y
        )
    end
end)

make("TextLabel", {
    Size = UDim2.new(1, -140, 1, 0),
    Position = UDim2.new(0, 18, 0, 0),
    BackgroundTransparency = 1,
    Text = "CLAYSTAND",
    TextColor3 = Color3.new(1, 1, 1),
    TextXAlignment = Enum.TextXAlignment.Left,
    Font = Enum.Font.GothamBold,
    TextSize = 21,
}, topBar)

local roleLabel = make("TextLabel", {
    Size = UDim2.new(0, 240, 1, 0),
    Position = UDim2.new(1, -365, 0, 0),
    BackgroundTransparency = 1,
    Text = "",
    TextColor3 = Color3.fromRGB(175, 175, 190),
    TextXAlignment = Enum.TextXAlignment.Right,
    Font = Enum.Font.Gotham,
    TextSize = 12,
}, topBar)

local closeButton = make("TextButton", {
    Size = UDim2.new(0, 42, 0, 34),
    Position = UDim2.new(1, -52, 0, 10),
    BackgroundColor3 = GUI_THEME.Button,
    Text = "×",
    TextColor3 = Color3.new(1, 1, 1),
    Font = Enum.Font.GothamBold,
    TextSize = 22,
    AutoButtonColor = false,
}, topBar)
make("UICorner", {CornerRadius = UDim.new(0, 8)}, closeButton)
closeButton.MouseEnter:Connect(function()
    TweenService:Create(closeButton, TweenInfo.new(0.12), {
        BackgroundColor3 = GUI_THEME.Danger
    }):Play()
end)
closeButton.MouseLeave:Connect(function()
    TweenService:Create(closeButton, TweenInfo.new(0.12), {
        BackgroundColor3 = GUI_THEME.Button
    }):Play()
end)

local tabBar = make("ScrollingFrame", {
    Size = UDim2.new(0, 180, 1, -60),
    Position = UDim2.new(0, 0, 0, 60),
    BackgroundColor3 = GUI_THEME.Surface,
    BorderSizePixel = 0,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    CanvasPosition = Vector2.zero,
    ScrollingDirection = Enum.ScrollingDirection.Y,
    ScrollBarThickness = 5,
    ScrollBarImageColor3 = Color3.fromRGB(95, 90, 130),
}, guiRoot)

make("TextLabel", {
    Size = UDim2.new(1, -20, 0, 24),
    Position = UDim2.new(0, 10, 0, 8),
    BackgroundTransparency = 1,
    Text = "CONTROL",
    TextColor3 = GUI_THEME.Muted,
    TextXAlignment = Enum.TextXAlignment.Left,
    Font = Enum.Font.GothamBold,
    TextSize = 11,
    ZIndex = 2,
}, guiRoot)

local content = make("Frame", {
    Size = UDim2.new(1, -180, 1, -60),
    Position = UDim2.new(0, 180, 0, 60),
    BackgroundColor3 = Color3.fromRGB(18, 18, 24),
    BorderSizePixel = 0,
}, guiRoot)

make("UIPadding", {
    PaddingTop = UDim.new(0, 20),
    PaddingBottom = UDim.new(0, 20),
    PaddingLeft = UDim.new(0, 20),
    PaddingRight = UDim.new(0, 20),
}, content)

local tabs = {
    "Home", "GOTO", "Sendall", "Actions", "Block Fight", "Emote Copy", "ESP", "Stances", "Fling",
    "Ownership", "Target", "Moves", "Main Moveset", "Alt Moveset", "Chat CMDS"
}
local tabButtons = {}
local pageFrames = {}
local showTab

local function clearPage(page)
    if page:IsA("ScrollingFrame") then
        page.CanvasPosition = Vector2.zero
    end
    for _, child in ipairs(page:GetChildren()) do
        if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
            child:Destroy()
        end
    end
end

local function addPageTitle(page, textValue, subtext)
    make("TextLabel", {
        Size = UDim2.new(1, 0, 0, 32),
        BackgroundTransparency = 1,
        Text = textValue,
        TextColor3 = Color3.new(1, 1, 1),
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.GothamBold,
        TextSize = 22,
    }, page)
    make("TextLabel", {
        Size = UDim2.new(1, 0, 0, 38),
        Position = UDim2.new(0, 0, 0, 34),
        BackgroundTransparency = 1,
        Text = subtext or "",
        TextColor3 = Color3.fromRGB(155, 155, 170),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,
        Font = Enum.Font.Gotham,
        TextSize = 12,
    }, page)
end

local function addButton(page, textValue, y, callback, selected)
    local isSelected = selected == true
    local b = make("TextButton", {
        Size = UDim2.new(1, 0, 0, 42),
        Position = UDim2.new(0, 0, 0, y),
        BackgroundColor3 = isSelected and GUI_THEME.AccentSoft or GUI_THEME.Button,
        Text = textValue,
        TextColor3 = GUI_THEME.Text,
        Font = Enum.Font.GothamMedium,
        TextSize = 13,
        AutoButtonColor = false,
    }, page)
    make("UICorner", {CornerRadius = UDim.new(0, 9)}, b)
    make("UIStroke", {
        Thickness = isSelected and 2 or 1,
        Color = isSelected and GUI_THEME.Accent or GUI_THEME.Border,
        Transparency = isSelected and 0 or 0.45,
    }, b)

    b.MouseEnter:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.12), {
            BackgroundColor3 = isSelected and GUI_THEME.AccentSoft or GUI_THEME.ButtonHover
        }):Play()
    end)

    b.MouseLeave:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.12), {
            BackgroundColor3 = isSelected and GUI_THEME.AccentSoft or GUI_THEME.Button
        }):Play()
    end)

    b.MouseButton1Click:Connect(function()
        local baseColor = isSelected and GUI_THEME.AccentSoft or GUI_THEME.Button
        b.BackgroundColor3 = GUI_THEME.Accent
        TweenService:Create(
            b,
            TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { BackgroundColor3 = baseColor }
        ):Play()
        callback()
    end)
    return b
end

local function addInfo(page, textValue, y)
    return make("TextLabel", {
        Size = UDim2.new(1, 0, 0, 32),
        Position = UDim2.new(0, 0, 0, y),
        BackgroundTransparency = 1,
        Text = textValue,
        TextColor3 = Color3.fromRGB(175, 175, 190),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,
        Font = Enum.Font.Gotham,
        TextSize = 12,
    }, page)
end

-- ============================================================
-- EXECUTOR-ONLY SILENT MAIN -> ALT RELAY
-- ============================================================
local RELAY_SECRET = "ClayStand_LocalRelay_9f3c7a4d8b2e6c1a"
local relaySeen = {}
local relayInitialized = false

local function getFileApi()
    return type(writefile) == "function"
        and type(readfile) == "function"
        and type(isfile) == "function"
        and writefile, readfile, isfile
end

local WRITEFILE, READFILE, ISFILE = getFileApi()

local function relayFileName()
    local place = tostring(game.PlaceId or "place")
    local job = tostring(game.JobId or "private"):gsub("[^%w%-_]", "")
    local owner = tostring(ORIGINAL_OWNER):gsub("[^%w%-_]", "")
    local secret = tostring(RELAY_SECRET):gsub("[^%w%-_]", "")
    return "ClayStandRelay_" .. place .. "_" .. job .. "_" .. owner .. "_" .. secret .. ".json"
end

local RELAY_FILE = relayFileName()

local function presenceFileName(userId)
    local place = tostring(game.PlaceId or "place")
    local job = tostring(game.JobId or "private"):gsub("[^%w%-_]", "")
    local owner = tostring(ORIGINAL_OWNER):gsub("[^%w%-_]", "")
    return "ClayStandPresence_" .. place .. "_" .. job .. "_" .. owner .. "_" .. tostring(userId) .. ".json"
end

local STAND_PRESENCE_TIMEOUT = 6

local function readPresenceForPlayer(plr)
    if not plr or not ISFILE or not READFILE then
        return nil
    end
    local file = presenceFileName(plr.UserId)
    if not ISFILE(file) then
        return nil
    end
    local ok, raw = pcall(READFILE, file)
    if not ok or type(raw) ~= "string" or raw == "" then
        return nil
    end
    local decodeOk, data = pcall(function()
        return HttpService:JSONDecode(raw)
    end)
    if not decodeOk or type(data) ~= "table" then
        return nil
    end
    local lastSeen = tonumber(data.lastSeen) or 0
    if os.time() - lastSeen > STAND_PRESENCE_TIMEOUT then
        return nil
    end
    return data
end

getActiveStandPlayers = function()
    local result = {}
    if not ISFILE or not READFILE then
        return result
    end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Name ~= ORIGINAL_OWNER then
            local presence = readPresenceForPlayer(plr)
            if presence then
                table.insert(result, {
                    player = plr,
                    registeredAt = tonumber(presence.registeredAt) or 0,
                    userId = plr.UserId,
                })
            end
        end
    end
    table.sort(result, function(a, b)
        if a.registeredAt == b.registeredAt then
            return a.userId < b.userId
        end
        return a.registeredAt < b.registeredAt
    end)
    local playersOnly = {}
    for _, item in ipairs(result) do
        table.insert(playersOnly, item.player)
    end
    return playersOnly
end

local function publishStandPresence()
    if IS_MAIN_ACCOUNT or not WRITEFILE or not READFILE or not ISFILE then
        return
    end
    local file = presenceFileName(LocalPlayer.UserId)
    local previous
    if ISFILE(file) then
        local ok, raw = pcall(READFILE, file)
        if ok and type(raw) == "string" and raw ~= "" then
            local decodeOk, data = pcall(function()
                return HttpService:JSONDecode(raw)
            end)
            if decodeOk and type(data) == "table" then
                previous = data
            end
        end
    end
    local registeredAt = tonumber(previous and previous.registeredAt) or 0
    local previousSeen = tonumber(previous and previous.lastSeen) or 0
    if registeredAt <= 0 or os.time() - previousSeen > STAND_PRESENCE_TIMEOUT then
        registeredAt = tick()
    end
    local payload = {
        userId = LocalPlayer.UserId,
        name = LocalPlayer.Name,
        displayName = LocalPlayer.DisplayName,
        registeredAt = registeredAt,
        lastSeen = os.time(),
    }
    pcall(function()
        WRITEFILE(file, HttpService:JSONEncode(payload))
    end)
end

local function destroyTargetHighlight()
    if espHighlight then
        pcall(function() espHighlight:Destroy() end)
        espHighlight = nil
    end
end

local function clearTargetESP()
    espLastTarget = nil
    destroyTargetHighlight()
end

local function setTargetESP(player)
    if not player or player == LocalPlayer then
        destroyTargetHighlight()
        return
    end
    espLastTarget = player
    if not espEnabled then
        destroyTargetHighlight()
        return
    end
    local character = player.Character
    if not character then
        destroyTargetHighlight()
        return
    end
    local existing = character:FindFirstChild("ClayStandESP")
    if existing and existing:IsA("Highlight") then
        destroyTargetHighlight()
        espHighlight = existing
        espHighlight.Enabled = true
        return
    end
    destroyTargetHighlight()
    local highlight = Instance.new("Highlight")
    highlight.Name = "ClayStandESP"
    highlight.Adornee = character
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillColor = Color3.fromRGB(255, 0, 0)
    highlight.FillTransparency = 0.28
    highlight.OutlineColor = Color3.fromRGB(255, 0, 0)
    highlight.OutlineTransparency = 0
    highlight.Enabled = true
    highlight.Parent = character
    espHighlight = highlight
end

local function refreshTargetESP()
    if espEnabled and espLastTarget then
        setTargetESP(espLastTarget)
    elseif not espEnabled then
        destroyTargetHighlight()
    end
end

local function readRelayQueue()
    if not WRITEFILE or not READFILE or not ISFILE then
        return nil
    end
    if not ISFILE(RELAY_FILE) then
        return {}
    end
    local ok, raw = pcall(READFILE, RELAY_FILE)
    if not ok or type(raw) ~= "string" or raw == "" then
        return {}
    end
    local decodeOk, data = pcall(function()
        return HttpService:JSONDecode(raw)
    end)
    if decodeOk and type(data) == "table" then
        return data
    end
    return {}
end

local function writeRelayQueue(queue)
    if not WRITEFILE then
        return false
    end
    local ok = pcall(function()
        WRITEFILE(RELAY_FILE, HttpService:JSONEncode(queue))
    end)
    return ok
end

local function makeRelayId()
    return table.concat({
        tostring(LocalPlayer.UserId),
        tostring(os.time()),
        tostring(math.floor((tick() % 1) * 1000000)),
        tostring(math.random(100000, 999999))
    }, "_")
end

local function publishRelay(cmd)
    if not IS_MAIN_ACCOUNT then
        return false
    end
    if not WRITEFILE or not READFILE or not ISFILE then
        warn("[ClayStand] Nexomia file API missing (writefile/readfile/isfile). Main -> Alt GUI relay cannot run.")
        return false
    end
    local queue = readRelayQueue() or {}
    table.insert(queue, {
        id = makeRelayId(),
        cmd = tostring(cmd),
        source = tostring(LocalPlayer.UserId),
        sentAt = os.time()
    })
    while #queue > 60 do
        table.remove(queue, 1)
    end
    return writeRelayQueue(queue)
end

local function sendUICmd(cmd)
    if not IS_MAIN_ACCOUNT then
        return
    end
    publishRelay(cmd)
end

local function rebuildHome(page)
    clearPage(page)
    addPageTitle(page, "Welcome to ClayStand", "Control panel • K toggles the window • selections use UserIds")
    local owner = Players:FindFirstChild(currentOwnerName)
    local stands = IS_MAIN_ACCOUNT and getActiveStandPlayers() or {}
    local stand = stands[1]
    addInfo(page, "Role: " .. (IS_MAIN_ACCOUNT and "MAIN / OWNER ACCOUNT" or "STAND ACCOUNT (NO GUI)"), 84)
    addInfo(page, "Owner: " .. currentOwnerName .. (owner and " ✓" or " (not in server)"), 116)
    addInfo(page, "Silent Main → Alt relay: " .. ((WRITEFILE and READFILE and ISFILE) and "READY" or "MISSING FILE API"), 148)
    local standText
    if stand then
        standText = "Stand 1: " .. stand.DisplayName .. "  •  @" .. stand.Name
        if #stands > 1 then
            standText = standText .. "  (" .. tostring(#stands) .. " active stands)"
        end
    else
        standText = "No active stand script detected"
    end
    addInfo(page, "Stand: " .. standText, 180)
    addInfo(page, "ESP: " .. (espEnabled and "ON — Neon Red" or "OFF"), 212)
    addButton(page, "OPEN GOTO CONTROLS", 258, function() showTab("GOTO") end)
    addButton(page, "OPEN SENDALL TAB", 308, function() showTab("Sendall") end)
    addButton(page, "OPEN ACTIONS", 358, function() showTab("Actions") end)
    addButton(page, "STOP / RESET", 408, function() sendUICmd("x") end)
end

local function getPlayerFromUserId(userId)
    userId = tonumber(userId)
    if not userId then return nil end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr.UserId == userId then
            return plr
        end
    end
    return nil
end

local function getPlayerThumbnail(player)
    if not player then return "" end
    local ok, image = pcall(function()
        local content = Players:GetUserThumbnailAsync(
            player.UserId,
            Enum.ThumbnailType.HeadShot,
            Enum.ThumbnailSize.Size100x100
        )
        return content
    end)
    return ok and image or ""
end

local function addPlayerPicker(page, y, height, selectedUserId, onSelect)
    local picker = make("ScrollingFrame", {
        Size = UDim2.new(1, 0, 0, height),
        Position = UDim2.new(0, 0, 0, y),
        BackgroundColor3 = Color3.fromRGB(27, 27, 37),
        BorderSizePixel = 0,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarThickness = 6,
        ScrollBarImageColor3 = Color3.fromRGB(95, 90, 130),
    }, page)
    make("UICorner", {CornerRadius = UDim.new(0, 10)}, picker)
    make("UIPadding", {
        PaddingTop = UDim.new(0, 6),
        PaddingBottom = UDim.new(0, 6),
        PaddingLeft = UDim.new(0, 6),
        PaddingRight = UDim.new(0, 6),
    }, picker)

    make("UIListLayout", {
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, picker)

    local players = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        table.insert(players, plr)
    end
    table.sort(players, function(a, b)
        local ad = (a.DisplayName or a.Name):lower()
        local bd = (b.DisplayName or b.Name):lower()
        if ad == bd then
            return a.Name:lower() < b.Name:lower()
        end
        return ad < bd
    end)

    for _, plr in ipairs(players) do
        local isSelected = selectedUserId and plr.UserId == selectedUserId
        local row = make("TextButton", {
            Size = UDim2.new(1, -4, 0, 58),
            BackgroundColor3 = isSelected and Color3.fromRGB(70, 65, 110) or Color3.fromRGB(38, 38, 50),
            Text = "",
            AutoButtonColor = true,
        }, picker)
        make("UICorner", {CornerRadius = UDim.new(0, 8)}, row)
        make("UIStroke", {
            Thickness = isSelected and 2 or 1,
            Color = isSelected and Color3.fromRGB(125, 105, 255) or Color3.fromRGB(60, 60, 75),
            Transparency = isSelected and 0 or 0.75,
        }, row)

        local avatar = make("ImageLabel", {
            Size = UDim2.new(0, 44, 0, 44),
            Position = UDim2.new(0, 7, 0.5, -22),
            BackgroundColor3 = Color3.fromRGB(22, 22, 30),
            BorderSizePixel = 0,
            Image = "",
        }, row)
        make("UICorner", {CornerRadius = UDim.new(1, 0)}, avatar)
        make("UIStroke", {
            Thickness = isSelected and 3 or 1,
            Color = isSelected and Color3.fromRGB(160, 140, 255) or Color3.fromRGB(60, 60, 75),
            Transparency = isSelected and 0 or 0.65,
        }, avatar)

        task.spawn(function()
            avatar.Image = getPlayerThumbnail(plr)
        end)

        make("TextLabel", {
            Size = UDim2.new(1, -70, 0, 24),
            Position = UDim2.new(0, 60, 0, 7),
            BackgroundTransparency = 1,
            Text = plr.DisplayName,
            TextColor3 = Color3.new(1, 1, 1),
            TextXAlignment = Enum.TextXAlignment.Left,
            Font = Enum.Font.GothamMedium,
            TextSize = 13,
        }, row)

        make("TextLabel", {
            Size = UDim2.new(1, -165, 0, 20),
            Position = UDim2.new(0, 60, 0, 31),
            BackgroundTransparency = 1,
            Text = "@" .. plr.Name,
            TextColor3 = Color3.fromRGB(155, 155, 170),
            TextXAlignment = Enum.TextXAlignment.Left,
            Font = Enum.Font.Gotham,
            TextSize = 11,
        }, row)

        if isSelected then
            local badge = make("TextLabel", {
                Size = UDim2.new(0, 90, 0, 24),
                Position = UDim2.new(1, -100, 0.5, -12),
                BackgroundColor3 = Color3.fromRGB(90, 75, 155),
                BackgroundTransparency = 0.05,
                Text = "✓ SELECTED",
                TextColor3 = Color3.new(1, 1, 1),
                Font = Enum.Font.GothamBold,
                TextSize = 10,
            }, row)
            make("UICorner", {CornerRadius = UDim.new(0, 7)}, badge)
        end

        row.MouseButton1Click:Connect(function()
            onSelect(plr)
        end)
    end

    return picker
end

local function getSortedGotoAreas()
    local areas = {}
    for name in pairs(GOTO_LOCATIONS) do
        table.insert(areas, name)
    end
    table.sort(areas)
    return areas
end

local function addAreaGrid(page, y, selectedArea, onSelect)
    local areas = getSortedGotoAreas()
    local cols = 4
    local buttonWidth = 112
    local gap = 8
    local buttonHeight = 36
    local rowHeight = 42

    for i, name in ipairs(areas) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)

        local b = make("TextButton", {
            Size = UDim2.new(0, buttonWidth, 0, buttonHeight),
            Position = UDim2.new(0, col * (buttonWidth + gap), 0, y + row * rowHeight),
            BackgroundColor3 = (selectedArea == name) and GUI_THEME.AccentSoft or GUI_THEME.Button,
            Text = string.upper(name),
            TextColor3 = GUI_THEME.Text,
            Font = Enum.Font.GothamMedium,
            TextSize = 12,
            AutoButtonColor = false,
        }, page)

        make("UICorner", {CornerRadius = UDim.new(0, 8)}, b)
        make("UIStroke", {
            Thickness = (selectedArea == name) and 2 or 1,
            Color = (selectedArea == name) and GUI_THEME.Accent or GUI_THEME.Border,
            Transparency = (selectedArea == name) and 0 or 0.45,
        }, b)

        b.MouseEnter:Connect(function()
            if selectedArea ~= name then
                TweenService:Create(b, TweenInfo.new(0.12), {
                    BackgroundColor3 = GUI_THEME.ButtonHover
                }):Play()
            end
        end)

        b.MouseLeave:Connect(function()
            if selectedArea ~= name then
                TweenService:Create(b, TweenInfo.new(0.12), {
                    BackgroundColor3 = GUI_THEME.Button
                }):Play()
            end
        end)

        b.MouseButton1Click:Connect(function()
            onSelect(name)
        end)
    end

    return math.ceil(#areas / cols) * rowHeight
end

local function rebuildGoto(page)
    clearPage(page)
    addPageTitle(page, "GOTO", "Select a player from the scrolling list, then choose a destination. No typing is required.")

    local selected = getPlayerFromUserId(selectedGotoUserId)
    addInfo(page, "Selected: " .. (selected and (selected.DisplayName .. "  •  @" .. selected.Name) or "none"), 78)

    addPlayerPicker(page, 110, 130, selectedGotoUserId, function(plr)
        selectedGotoUserId = plr.UserId
        selectedGotoPlayer = plr.Name
        selectedOwnershipUserId = plr.UserId
        if IS_MAIN_ACCOUNT then
            espLastTarget = plr
            refreshTargetESP()
        end
        rebuildGoto(page)
    end)

    addInfo(page, "Destination", 246)
    addAreaGrid(page, 278, selectedGotoArea, function(name)
        selectedGotoArea = name
        rebuildGoto(page)
    end)

    addButton(page, "GOTO SELECTED PLAYER", 408, function()
        local plr = getPlayerFromUserId(selectedGotoUserId)
        if plr then
            sendUICmd("goto " .. plr.Name .. " " .. selectedGotoArea)
        end
    end)
end

local function rebuildSendAll(page)
    clearPage(page)
    addPageTitle(page, "SENDALL", "Choose one destination and send every eligible player there. The existing sendall logic is used.")

    local eligible = 0
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer
            and plr.Name ~= currentOwnerName
            and plr.Name ~= ORIGINAL_OWNER
            and not exclusionList[plr.Name]
            and plr.Character
            and plr.Character:FindFirstChild("HumanoidRootPart") then
            eligible = eligible + 1
        end
    end

    addInfo(page, "Eligible players: " .. tostring(eligible), 78)
    addInfo(page, "Destination", 114)

    local gridHeight = addAreaGrid(page, 146, selectedSendAllArea, function(name)
        selectedSendAllArea = name
        rebuildSendAll(page)
    end)

    local buttonY = 146 + gridHeight + 10
    local sendButton = addButton(page, "SEND ALL → " .. string.upper(selectedSendAllArea), buttonY, function()
        sendUICmd("sendall " .. selectedSendAllArea)
    end)

    addButton(page, "CANCEL / RESET", buttonY + 48, function()
        sendUICmd("x")
    end)

    addInfo(page, "Sendall skips the owner, the local stand client, and excluded players. Use Cancel / Reset to stop the current run.", buttonY + 96)
    return sendButton
end

local function rebuildFling(page)
    clearPage(page)
    addPageTitle(page, "FLING", "Select a player from the scrolling list. No player-name typing is required.")

    local selected = getPlayerFromUserId(selectedFlingUserId)
    addInfo(page, "Selected: " .. (selected and (selected.DisplayName .. "  •  @" .. selected.Name) or "none"), 78)

    addPlayerPicker(page, 110, 210, selectedFlingUserId, function(plr)
        selectedFlingUserId = plr.UserId
        selectedFlingPlayer = plr.Name
        selectedOwnershipUserId = plr.UserId
        if IS_MAIN_ACCOUNT then
            espLastTarget = plr
            refreshTargetESP()
        end
        rebuildFling(page)
    end)

    addButton(page, "FLING selected player", 330, function()
        local plr = getPlayerFromUserId(selectedFlingUserId)
        if plr then
            sendUICmd("fling " .. plr.Name)
        end
    end)
    addButton(page, "GUARD mode", 376, function() sendUICmd("guard") end)
    addInfo(page, "The selected player is identified by UserId, so display-name changes do not break the selection.", 420)
end

local function rebuildActions(page)
    clearPage(page)
    addPageTitle(page, "ACTIONS", "Main GUI buttons run these actions silently on the ALT. The last selected action stays highlighted.")

    local function chooseAction(name, cmd)
        selectedAction = name
        sendUICmd(cmd)
        rebuildActions(page)
    end

    addButton(page, "STOP / RESET", 92, function() chooseAction("stop", "x") end, selectedAction == "stop")
    addButton(page, "RETALIATE", 138, function() chooseAction("retaliate", "p") end, selectedAction == "retaliate")
    addButton(page, "AGGRESSIVE", 184, function() chooseAction("aggressive", "v") end, selectedAction == "aggressive")
    addButton(page, "SPIN", 230, function() chooseAction("spin", "s") end, selectedAction == "spin")
    addButton(page, "GUARD", 276, function() chooseAction("guard", "guard") end, selectedAction == "guard")
    addButton(page, "EMOTE", 322, function() chooseAction("emote", "z") end, selectedAction == "emote")
    addButton(page, "HIDE STAND", 368, function() chooseAction("hide", "hide") end, selectedAction == "hide")
    addButton(page, "SHOW STAND", 414, function() chooseAction("appear", "appear") end, selectedAction == "appear")
    addButton(page, "ULTIMATE", 460, function() chooseAction("ult", "ult") end, selectedAction == "ult")
end

local function rebuildBlockFight(page)
    clearPage(page)
    addPageTitle(page, "BLOCK FIGHT", "Toggle the Block Fight system without sending anything through chat.")
    addButton(page, "BLOCK FIGHT ON", 92, function()
        blockFightEnabled = true
        sendUICmd(".")
        rebuildBlockFight(page)
    end, blockFightEnabled)
    addButton(page, "BLOCK FIGHT OFF", 138, function()
        blockFightEnabled = false
        sendUICmd(",")
        rebuildBlockFight(page)
    end, not blockFightEnabled)
    addInfo(page, "Default: ON. This controls whether holding/blocking on the main account starts the stand fight behavior.", 194)
end

local function rebuildEmoteCopy(page)
    clearPage(page)
    addPageTitle(page, "EMOTE COPY", "Copy the emote currently playing on the main account to the stand.")

    addButton(page, "COPY MAIN ACCOUNT EMOTE", 92, function()
        sendUICmd("copyemote")
        rebuildEmoteCopy(page)
    end)

    addInfo(page, "The stand looks at the main account's currently playing animation and mirrors the most likely emote/action track.", 148)
    addInfo(page, "If the main account is not currently playing an emote, the stand will report that no active emote was found.", 190)
end

local function rebuildESP(page)
    clearPage(page)
    addPageTitle(page, "ESP", "Main-account ESP highlights the currently selected player in neon red.")
    addButton(page, "ESP ON — NEON RED", 92, function()
        espEnabled = true
        refreshTargetESP()
        sendUICmd("esp on")
        rebuildESP(page)
    end, espEnabled)
    addButton(page, "ESP OFF", 138, function()
        espEnabled = false
        destroyTargetHighlight()
        sendUICmd("esp off")
        rebuildESP(page)
    end, not espEnabled)
    addInfo(page, "Select a player on GOTO, Fling, Ownership, or Target and the main account highlights them.", 194)
end

local function rebuildOwnership(page)
    clearPage(page)
    addPageTitle(page, "OWNERSHIP", "Select a player, then give them the stand. Back always returns it to the main account.")

    local selected = getPlayerFromUserId(selectedOwnershipUserId)
    addInfo(page, "Selected: " .. (selected and (selected.DisplayName .. "  •  @" .. selected.Name) or "none"), 78)

    addPlayerPicker(page, 110, 190, selectedOwnershipUserId, function(plr)
        selectedOwnershipUserId = plr.UserId
        if IS_MAIN_ACCOUNT then
            espLastTarget = plr
            refreshTargetESP()
        end
        rebuildOwnership(page)
    end)

    local grantButton = addButton(page, "GRANT OWNERSHIP TO SELECTED PLAYER", 310, function()
        local plr = getPlayerFromUserId(selectedOwnershipUserId)
        if plr then
            sendUICmd("give " .. plr.Name)
            grantButton.Text = "GRANTED OWNERSHIP TO " .. plr.DisplayName
            task.delay(1.75, function()
                if grantButton and grantButton.Parent then
                    grantButton.Text = "GRANT OWNERSHIP TO SELECTED PLAYER"
                end
            end)
        end
    end)

    addButton(page, "BACK — GIVE STAND TO @" .. ORIGINAL_OWNER, 356, function()
        sendUICmd("back")
    end)
end

local function rebuildTarget(page)
    clearPage(page)
    addPageTitle(page, "TARGET", "Select a player, then lock them as the stand target or exclude them.")

    local selected = getPlayerFromUserId(selectedGotoUserId)
    addInfo(page, "Selected: " .. (selected and (selected.DisplayName .. "  •  @" .. selected.Name) or "none"), 78)

    addPlayerPicker(page, 110, 190, selectedGotoUserId, function(plr)
        selectedGotoUserId = plr.UserId
        selectedGotoPlayer = plr.Name
        espLastTarget = plr
        refreshTargetESP()
        rebuildTarget(page)
    end)

    addButton(page, "LOCK TARGET", 310, function()
        local plr = getPlayerFromUserId(selectedGotoUserId)
        if plr then
            sendUICmd("target " .. plr.Name)
        end
    end)

    addButton(page, "EXCLUDE SELECTED PLAYER", 356, function()
        local plr = getPlayerFromUserId(selectedGotoUserId)
        if plr then
            sendUICmd("exclude " .. plr.Name)
        end
    end)

    addButton(page, "CLEAR TARGET", 402, function()
        sendUICmd("target off")
        clearTargetESP()
    end)
end

local function rebuildMoves(page)
    clearPage(page)
    addPageTitle(page, "MOVES", "Fire moves 1–4 directly on the ALT. The last chosen move stays highlighted.")
    addButton(page, "MOVE 1", 92, function() selectedMove = 1; sendUICmd("1"); rebuildMoves(page) end, selectedMove == 1)
    addButton(page, "MOVE 2", 138, function() selectedMove = 2; sendUICmd("2"); rebuildMoves(page) end, selectedMove == 2)
    addButton(page, "MOVE 3", 184, function() selectedMove = 3; sendUICmd("3"); rebuildMoves(page) end, selectedMove == 3)
    addButton(page, "MOVE 4", 230, function() selectedMove = 4; sendUICmd("4"); rebuildMoves(page) end, selectedMove == 4)
end

local function rebuildChatCmds(page)
    clearPage(page)
    addPageTitle(page, "CHAT CMDS", "Reference only — manual chat commands still work exactly as before.")

    local refs = {
        "x  = stop/reset    p = retaliate    v = aggressive    s = spin",
        "guard = guard      z = emote        hide / appear     ult = ultimate",
        "goto <player> <area>    sendall <area>",
        "give <player>    back    target <player>    exclude <player>",
        "blockfight on / blockfight off    = Block Fight detection toggle",
        "stance 1    stance 2    co = chat ON    cf = chat OFF",
        "1 / 2 / 3 / 4 = moves",
        "esp on    esp off"
    }

    local y = 92
    for _, line in ipairs(refs) do
        addInfo(page, line, y)
        y = y + 42
    end
end

local function rebuildStances(page)
    clearPage(page)
    addPageTitle(page, "STANCES", "Switch the stand animation. The chosen stance stays highlighted.")
    addButton(page, "STANCE 1 — Normal", 92, function()
        currentStance = 1
        selectedStance = 1
        sendUICmd("stance 1")
        rebuildStances(page)
    end, selectedStance == 1)
    addButton(page, "STANCE 2 — Alternate", 138, function()
        currentStance = 2
        selectedStance = 2
        sendUICmd("stance 2")
        rebuildStances(page)
    end, selectedStance == 2)
    addInfo(page, "Current stance: " .. tostring(currentStance), 190)
end

local mainMovesetEnabled = false
local altMovesetEnabled = false

local function rebuildMainMoveset(page)
    clearPage(page)
    addPageTitle(page, "MAIN MOVESET", "Main-account moveset slot. Add your main moveset code here later.")
    addInfo(page, "Status: " .. (mainMovesetEnabled and "ENABLED" or "DISABLED"), 94)
    addButton(page, "ENABLE MAIN MOVESET", 140, function()
        mainMovesetEnabled = true
        rebuildMainMoveset(page)
    end, mainMovesetEnabled)
    addButton(page, "DISABLE MAIN MOVESET", 186, function()
        mainMovesetEnabled = false
        rebuildMainMoveset(page)
    end, not mainMovesetEnabled)
end

local function rebuildAltMoveset(page)
    clearPage(page)
    addPageTitle(page, "ALT MOVESET", "Alt/stand moveset slot. Add your alt moveset code here later.")
    addInfo(page, "Status: " .. (altMovesetEnabled and "ENABLED" or "DISABLED"), 94)
    addButton(page, "ENABLE ALT MOVESET", 140, function()
        altMovesetEnabled = true
        rebuildAltMoveset(page)
    end, altMovesetEnabled)
    addButton(page, "DISABLE ALT MOVESET", 186, function()
        altMovesetEnabled = false
        rebuildAltMoveset(page)
    end, not altMovesetEnabled)
end

local builders = {
    Home = rebuildHome,
    GOTO = rebuildGoto,
    Sendall = rebuildSendAll,
    Actions = rebuildActions,
    ["Block Fight"] = rebuildBlockFight,
    ["Emote Copy"] = rebuildEmoteCopy,
    ESP = rebuildESP,
    Stances = rebuildStances,
    Fling = rebuildFling,
    Ownership = rebuildOwnership,
    Target = rebuildTarget,
    Moves = rebuildMoves,
    ["Main Moveset"] = rebuildMainMoveset,
    ["Alt Moveset"] = rebuildAltMoveset,
    ["Chat CMDS"] = rebuildChatCmds,
}

showTab = function(name)
    activeTab = name
    for tabName, page in pairs(pageFrames) do
        page.Visible = (tabName == name)
    end
    for tabName, button in pairs(tabButtons) do
        button.BackgroundColor3 = (tabName == name) and GUI_THEME.AccentSoft or Color3.fromRGB(25, 26, 35)
    end
    local page = pageFrames[name]
    if page and builders[name] then builders[name](page) end
end

for i, tabName in ipairs(tabs) do
    local b = make("TextButton", {
        Name = tabName:gsub("%s", ""),
        Size = UDim2.new(1, -18, 0, 40),
        Position = UDim2.new(0, 9, 0, 40 + (i - 1) * 46),
        BackgroundColor3 = Color3.fromRGB(25, 26, 35),
        Text = tabName,
        TextColor3 = Color3.new(1, 1, 1),
        Font = Enum.Font.GothamMedium,
        TextSize = 13,
    }, tabBar)
    make("UICorner", {CornerRadius = UDim.new(0, 8)}, b)
    tabButtons[tabName] = b
    local page = make("ScrollingFrame", {
        Name = tabName .. "Page",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Visible = false,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ScrollBarThickness = 6,
        ScrollBarImageColor3 = Color3.fromRGB(95, 90, 130),
    }, content)
    pageFrames[tabName] = page
    b.MouseButton1Click:Connect(function()
        b.BackgroundColor3 = GUI_THEME.Accent
        TweenService:Create(
            b,
            TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { BackgroundColor3 = (activeTab == tabName) and GUI_THEME.AccentSoft or Color3.fromRGB(25, 26, 35) }
        ):Play()
        showTab(tabName)
    end)
end

local function setGuiOpen(open)
    guiOpen = open
    if open then
        guiRoot.Visible = true
        guiRoot.Size = UDim2.new(0, 780, 0, 500)
        TweenService:Create(guiRoot, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Size = UDim2.new(0, 820, 0, 540)
        }):Play()
    else
        TweenService:Create(guiRoot, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            Size = UDim2.new(0, 780, 0, 500)
        }):Play()
        task.delay(0.12, function()
            if not guiOpen then guiRoot.Visible = false end
        end)
    end
end

closeButton.MouseButton1Click:Connect(function() setGuiOpen(false) end)
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if IS_MAIN_ACCOUNT and input.KeyCode == Enum.KeyCode.K then
        setGuiOpen(not guiOpen)
    end
end)

local function updateClayStandGui()
    if not IS_MAIN_ACCOUNT then return end
    local stands = getActiveStandPlayers()
    local stand = stands[1]
    local standText = stand and ("Stand 1 • @" .. stand.Name) or "No stand detected"
    if #stands > 1 then
        standText = standText .. "  (" .. tostring(#stands) .. ")"
    end
    roleLabel.Text = (IS_MAIN_ACCOUNT and "MAIN / OWNER" or "STAND") ..
        "  •  Owner: " .. currentOwnerName ..
        "  •  " .. standText
end

showTab("Home")
updateClayStandGui()

-- ===================== OWNER-ONLY WELCOME CARD =====================
if IS_MAIN_ACCOUNT then
    local welcome = make("Frame", {
        Name = "ClayStandWelcome",
        Size = UDim2.new(0, 460, 0, 180),
        Position = UDim2.new(0.5, -230, 0.5, -90),
        BackgroundColor3 = Color3.fromRGB(25, 25, 34),
        BorderSizePixel = 0,
        ZIndex = 20,
    }, screenGui)
    make("UICorner", {CornerRadius = UDim.new(0, 14)}, welcome)
    make("TextLabel", {
        Size = UDim2.new(1, -30, 0, 48),
        Position = UDim2.new(0, 15, 0, 18),
        BackgroundTransparency = 1,
        Text = "WELCOME TO CLAYSTAND",
        TextColor3 = Color3.new(1, 1, 1),
        Font = Enum.Font.GothamBold,
        TextSize = 23,
        ZIndex = 21,
    }, welcome)
    make("TextLabel", {
        Size = UDim2.new(1, -40, 0, 48),
        Position = UDim2.new(0, 20, 0, 70),
        BackgroundTransparency = 1,
        Text = "Owner detected: " .. LocalPlayer.Name .. "\nPress K to open/close the control panel.",
        TextColor3 = Color3.fromRGB(175, 175, 190),
        Font = Enum.Font.Gotham,
        TextSize = 13,
        TextWrapped = true,
        ZIndex = 21,
    }, welcome)
    local continue = make("TextButton", {
        Size = UDim2.new(0, 150, 0, 34),
        Position = UDim2.new(0.5, -75, 1, -48),
        BackgroundColor3 = Color3.fromRGB(65, 60, 100),
        Text = "OPEN PANEL",
        TextColor3 = Color3.new(1, 1, 1),
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        ZIndex = 21,
    }, welcome)
    make("UICorner", {CornerRadius = UDim.new(0, 8)}, continue)
    continue.MouseButton1Click:Connect(function()
        welcome:Destroy()
        setGuiOpen(true)
    end)
end
-- =================================================================

task.spawn(function()
    while IS_MAIN_ACCOUNT and screenGui.Parent do
        updateClayStandGui()
        if activeTab == "Home" and pageFrames.Home and pageFrames.Home.Visible then
            rebuildHome(pageFrames.Home)
        end
        task.wait(1)
    end
end)

-- ======================= END MODERN CLAYSTAND GUI =======================

local function setupGodmode(humanoid)
    if not humanoid then return end
    humanoid.MaxHealth = 9e9
    humanoid.Health = 9e9
    humanoid.BreakJointsOnDeath = false
    humanoid.HealthChanged:Connect(function()
        if humanoid.Health < humanoid.MaxHealth then
            if retaliateEnabled then
                retaliateRequested = true
            end
            humanoid.Health = humanoid.MaxHealth
        end
    end)
end

local function attachOwnerDamageWatcher(ownerPlayer)
    if ownerDamageConn then
        ownerDamageConn:Disconnect()
        ownerDamageConn = nil
    end
    lastOwnerHealth = nil
    if not ownerPlayer then return end

    local function hookChar(char)
        if ownerDamageConn then
            ownerDamageConn:Disconnect()
            ownerDamageConn = nil
        end
        lastOwnerHealth = nil
        if not char then return end

        local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5)
        if not hum then return end

        lastOwnerHealth = hum.Health
        ownerDamageConn = hum.HealthChanged:Connect(function(newHealth)
            if lastOwnerHealth and newHealth < lastOwnerHealth and newHealth > 0 then
                if retaliateEnabled then
                    retaliateRequested = true
                end
            end
            lastOwnerHealth = newHealth
        end)
    end

    if ownerPlayer.Character then
        hookChar(ownerPlayer.Character)
    end
    ownerPlayer.CharacterAdded:Connect(hookChar)
end

local function setPhysicsRep(part, targetPart)
    if not part then return end
    pcall(function()
        sethiddenproperty(part, "PhysicsRepRootPart", targetPart)
    end)
end

local function flatLookFrom(root)
    local lv = root.CFrame.LookVector
    local flat = Vector3.new(lv.X, 0, lv.Z)
    if flat.Magnitude < 0.01 then
        return Vector3.new(0, 0, -1)
    end
    return flat.Unit
end

local function layFlatLookingDown(position, flatLook)
    local baseCF = CFrame.lookAt(position, position + flatLook, Vector3.new(0, 1, 0))
    return baseCF * CFrame.Angles(-math.pi / 2, 0, 0)
end

local function setStandVisibility(hidden)
    standHidden = hidden
    local character = LocalPlayer.Character
    if not character then return end

    if hidden then
        if currentIdleTrack and currentIdleTrack.IsPlaying then
            currentIdleTrack:Stop()
        end
    else
        if not guardingActive then
            manageIdleAnimation(character, true)
        end
    end

    updateGUI()
end

local function NetworkFling(TargetPlayer)
    if not TargetPlayer then return false end
    if TargetPlayer == LocalPlayer or TargetPlayer.Name == currentOwnerName or TargetPlayer.Name == ORIGINAL_OWNER then
        return false
    end

    local targetCharacter = TargetPlayer.Character
    local targetRoot = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")
    if not targetRoot then
        return false
    end

    setTargetESP(TargetPlayer)

    flingToken = flingToken + 1
    local myToken = flingToken
    flingTarget = TargetPlayer
    flingActive = true

    task.spawn(function()
        task.wait(FLING_DURATION)
        if flingToken == myToken and flingTarget == TargetPlayer then
            flingActive = false
            flingTarget = nil
            updateGUI()
        end
    end)

    updateGUI()
    return true
end

local function isTargetBlocking(targetCharacter)
    if not targetCharacter then return false end
    for _, child in ipairs(targetCharacter:GetDescendants()) do
        if child:IsA("BoolValue") and (string.find(child.Name:lower(), "block") or string.find(child.Name:lower(), "guard")) then
            if child.Value then return true end
        end
    end
    local animator = targetCharacter:FindFirstChildOfClass("Animator")
    if animator then
        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
            local animName = track.Animation and track.Animation.Name or ""
            if string.find(animName:lower(), "block") or string.find(animName:lower(), "guard") then
                return true
            end
        end
    end
    local humanoid = targetCharacter:FindFirstChildOfClass("Humanoid")
    if humanoid then
        if humanoid.WalkSpeed == 0 and humanoid.MoveDirection.Magnitude == 0 then
            local tool = targetCharacter:FindFirstChildOfClass("Tool")
            if tool and (string.find(tool.Name:lower(), "block") or string.find(tool.Name:lower(), "guard")) then
                return true
            end
        end
    end
    if targetCharacter:GetAttribute("Blocking") == true then return true end
    if targetCharacter:GetAttribute("Block") == true then return true end

    local owner = getOwner()
    if owner and owner.Character then
        for _, child in ipairs(owner.Character:GetDescendants()) do
            if child:IsA("BoolValue") and (string.find(child.Name:lower(), "block") or string.find(child.Name:lower(), "guard")) then
                if child.Value then return true end
            end
        end
    end
    return false
end

local function findAttacker(originPos)
    local nearest = nil
    local nearestDist = RETALIATE_RANGE
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Name ~= currentOwnerName and not exclusionList[plr.Name] then
            local c = plr.Character
            local r = c and c:FindFirstChild("HumanoidRootPart")
            local h = c and c:FindFirstChildOfClass("Humanoid")
            if r and h and h.Health > 0 then
                local d = (r.Position - originPos).Magnitude
                if d < nearestDist then
                    nearestDist = d
                    nearest = plr
                end
            end
        end
    end
    return nearest
end

local function findNearestEnemy(originPosition)
    if retaliateTarget and retaliateTarget.Parent then
        if retaliateTarget.Character and retaliateTarget.Character:FindFirstChild("HumanoidRootPart") then
            return retaliateTarget.Character
        end
    end

    if specificTargetPlayer and specificTargetPlayer.Parent then
        if specificTargetPlayer.Character and specificTargetPlayer.Character:FindFirstChild("HumanoidRootPart") then
            return specificTargetPlayer.Character
        else
            return nil
        end
    end

    local nearest = nil
    local nearestDist = math.huge
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Name ~= LocalPlayer.Name and not exclusionList[player.Name] and player.Name ~= currentOwnerName then
            local character = player.Character
            if character and character:FindFirstChild("HumanoidRootPart") then
                local root = character.HumanoidRootPart
                local dist = (root.Position - originPosition).Magnitude
                if dist < nearestDist then
                    nearestDist = dist
                    nearest = character
                end
            end
        end
    end
    return nearest
end

local function findNearestPlayer()
    local nearest = nil
    local nearestDist = math.huge
    local myChar = LocalPlayer.Character
    if not myChar or not myChar:FindFirstChild("HumanoidRootPart") then return nil end
    local myRoot = myChar.HumanoidRootPart
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Name ~= ORIGINAL_OWNER and player ~= LocalPlayer then
            local char = player.Character
            if char and char:FindFirstChild("HumanoidRootPart") then
                local root = char.HumanoidRootPart
                local dist = (root.Position - myRoot.Position).Magnitude
                if dist < nearestDist then
                    nearestDist = dist
                    nearest = player
                end
            end
        end
    end
    return nearest
end

local function findPlayerByName(name)
    name = name:lower()
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Name:lower() == name or player.DisplayName:lower() == name or player.Name:lower():sub(1, #name) == name then
            return player
        end
    end
    return nil
end

local function pressKey(keyCode)
    VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
    task.wait(0.05)
    VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
end

local function punch()
    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 1)
    task.wait(0.05)
    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 1)
end

local function handleGoto(targetPlayer, locPos, locName)
    if not targetPlayer then return false end
    setTargetESP(targetPlayer)

    local isSelf = (targetPlayer == LocalPlayer)

    if not isSelf then
        if not targetPlayer.Character or not targetPlayer.Character:FindFirstChild("HumanoidRootPart") then
            return false
        end
    end

    local originalTarget = specificTargetPlayer
    gotoActive = true
    gotoTarget = targetPlayer
    updateGUI()

    if currentIdleTrack and currentIdleTrack.IsPlaying then
        currentIdleTrack:Stop()
    end

    local char = LocalPlayer.Character
    local sh = char and char:FindFirstChild("HumanoidRootPart")
    if not sh then
        gotoActive = false
        gotoTarget = nil
        updateGUI()
        return false
    end

    local ragdolled = false

    if isSelf then
        ragdolled = true
    else
        local tCharStart = targetPlayer.Character
        local preRagdoll = tCharStart and tCharStart:FindFirstChild("Ragdoll")
        preRagdoll = preRagdoll and preRagdoll:IsA("Accessory")

        local startTime = tick()

        while tick() - startTime < 10 do
            if not targetPlayer or not targetPlayer.Parent or not targetPlayer.Character
                or not targetPlayer.Character:FindFirstChild("HumanoidRootPart") then
                break
            end
            if not gotoActive then break end

            local tChar = targetPlayer.Character
            local tHum = tChar:FindFirstChildOfClass("Humanoid")

            local hasRagdoll = tChar:FindFirstChild("Ragdoll")
            local isDead = tHum and tHum.Health <= 0

            if ((hasRagdoll and hasRagdoll:IsA("Accessory") and not preRagdoll) or isDead) then
                ragdolled = true
                break
            end

            punch()
            punch()
            task.wait(0.2)
        end
    end

    if not gotoActive then
        gotoTarget = nil
        specificTargetPlayer = originalTarget
        updateGUI()
        return false
    end

    gotoActive = false
    gotoTarget = nil
    updateGUI()

    if not ragdolled then
        specificTargetPlayer = originalTarget
        return false
    end

    setPhysicsRep(sh, nil)

    char = LocalPlayer.Character
    sh = char and char:FindFirstChild("HumanoidRootPart")
    if not sh then return false end

    local groundPos = Vector3.new(locPos.X, locPos.Y + GOTO_GROUND_OFFSET, locPos.Z)

    local owner = getOwner()
    local flatLook = Vector3.new(0, 0, -1)
    if owner and owner.Character and owner.Character:FindFirstChild("HumanoidRootPart") then
        flatLook = flatLookFrom(owner.Character.HumanoidRootPart)
    end

    local freezePos = layFlatLookingDown(groundPos, flatLook)

    sh.CFrame = freezePos
    sh.AssemblyLinearVelocity = Vector3.zero
    sh.AssemblyAngularVelocity = Vector3.zero

    gotoFreeze = true
    gotoFreezeCFrame = freezePos
    updateGUI()

    if locName == "jail" then
        task.spawn(function()
            task.wait(0.3)
            sendChatMessageAlways("jail time for you")
        end)
    end

    task.wait(GOTO_WAIT_BEFORE_Q)

    if not gotoFreeze then
        gotoTarget = nil
        specificTargetPlayer = originalTarget
        updateGUI()
        return false
    end

    pressKey(Enum.KeyCode.Q)
    task.wait(GOTO_FREEZE_TIME)

    gotoFreeze = false
    gotoFreezeCFrame = nil
    updateGUI()

    return true
end

local function handleSendAll(locPos, locName)
    if gotoActive or gotoFreeze then
        return
    end

    sendAllActive = true
    sendAllCancelled = false

    local targets = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer
            and plr.Name ~= currentOwnerName
            and plr.Name ~= ORIGINAL_OWNER
            and not exclusionList[plr.Name] then
            if plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") then
                table.insert(targets, plr)
            end
        end
    end

    if #targets == 0 then
        sendAllActive = false
        sendChatMessage("Sendall: no eligible players.")
        return
    end

    sendChatMessage("Sendall -> " .. locName .. " (" .. #targets .. " players)")

    for i, target in ipairs(targets) do
        if sendAllCancelled then break end
        if target and target.Parent and target.Character
            and target.Character:FindFirstChild("HumanoidRootPart") then
            handleGoto(target, locPos, locName)
        end
        if sendAllCancelled then break end
        task.wait(SENDALL_BREATHER)
    end

    sendAllActive = false
    sendAllCancelled = false
end

local function stopChatEmote()
    if activeChatEmoteTrack and activeChatEmoteTrack.IsPlaying then
        activeChatEmoteTrack:Stop()
    end
end

local function copyMainAccountEmote(character)
    local owner = getOwner()
    if not owner or not owner.Character then
        return false
    end

    local ownerHumanoid = owner.Character:FindFirstChildOfClass("Humanoid")
    local ownerAnimator = owner.Character:FindFirstChildOfClass("Animator")
        or (ownerHumanoid and ownerHumanoid:FindFirstChildOfClass("Animator"))
    if not ownerAnimator then
        return false
    end

    local bestTrack = nil
    local bestPriority = -1
    local bestLength = 0

    for _, track in ipairs(ownerAnimator:GetPlayingAnimationTracks()) do
        local animation = track.Animation
        local animationId = animation and animation.AnimationId or ""
        if animationId ~= "" and track.IsPlaying then
            local name = (animation and animation.Name or ""):lower()
            local priority = track.Priority.Value
            local length = track.Length or 0

            -- Prefer action/emote-style tracks and avoid the stand's normal
            -- idle/walk-style animations when possible.
            local looksLikeIdle = name:find("idle", 1, true)
                or name:find("walk", 1, true)
                or name:find("run", 1, true)
                or name:find("jump", 1, true)
                or name:find("fall", 1, true)

            if not looksLikeIdle and (priority > bestPriority or (priority == bestPriority and length > bestLength)) then
                bestTrack = track
                bestPriority = priority
                bestLength = length
            end
        end
    end

    if not bestTrack or not bestTrack.Animation then
        return false
    end

    copiedMainEmoteId = bestTrack.Animation.AnimationId
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local animator = character and (
        character:FindFirstChildOfClass("Animator")
        or (humanoid and humanoid:FindFirstChildOfClass("Animator"))
    )
    if not animator then
        return false
    end

    if currentIdleTrack and currentIdleTrack.IsPlaying then
        currentIdleTrack:Stop()
    end
    stopChatEmote()

    local anim = Instance.new("Animation")
    anim.AnimationId = copiedMainEmoteId
    local success, copiedTrack = pcall(function()
        return animator:LoadAnimation(anim)
    end)

    if success and copiedTrack then
        activeChatEmoteTrack = copiedTrack
        activeChatEmoteTrack.Priority = Enum.AnimationPriority.Action4
        activeChatEmoteTrack:Play()
        return true
    end

    return false
end

local function playChatEmote(character)
    if standHidden then return end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local animator = character:FindFirstChildOfClass("Animator") or (humanoid and humanoid:FindFirstChildOfClass("Animator"))
    if not animator then return end

    if currentIdleTrack and currentIdleTrack.IsPlaying then
        currentIdleTrack:Stop()
    end

    if activeChatEmoteTrack and activeChatEmoteTrack.IsPlaying then
        activeChatEmoteTrack:Stop()
    end

    local anim = Instance.new("Animation")
    anim.AnimationId = CHAT_EMOTE_ID
    local success, track = pcall(function()
        return animator:LoadAnimation(anim)
    end)
    if success and track then
        activeChatEmoteTrack = track
        activeChatEmoteTrack.Priority = Enum.AnimationPriority.Action4
        activeChatEmoteTrack:Play()
    end

    task.spawn(function()
        task.wait(0.2)
        sendEmoteChatMessage("lol ez")
    end)
end

manageIdleAnimation = function(character, shouldPlay)
    if standHidden then return end
    if activeChatEmoteTrack and activeChatEmoteTrack.IsPlaying then
        return
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local animator = character:FindFirstChildOfClass("Animator") or (humanoid and humanoid:FindFirstChildOfClass("Animator"))

    if not animator then return end

    if shouldPlay then
        if not currentIdleTrack then
            local anim = Instance.new("Animation")
            anim.AnimationId = (currentStance == 2) and STANCE2_ANIMATION_ID or IDLE_ANIMATION_ID
            local success, track = pcall(function()
                return animator:LoadAnimation(anim)
            end)
            if success and track then
                currentIdleTrack = track
                currentIdleTrack.Priority = Enum.AnimationPriority.Action
                currentIdleTrack:Play()
            end
        elseif not currentIdleTrack.IsPlaying then
            currentIdleTrack:Play()
        end
    else
        if currentIdleTrack and currentIdleTrack.IsPlaying then
            currentIdleTrack:Stop()
        end
    end
end

local function executeMoveCommand(moveIndex)
    if commandActive then return end
    commandActive = true

    local owner = getOwner()
    if not owner or not owner.Character or not owner.Character:FindFirstChild("HumanoidRootPart") then
        commandActive = false
        return
    end
    local ownerRoot = owner.Character.HumanoidRootPart
    local altChar = LocalPlayer.Character
    if not altChar or not altChar:FindFirstChild("HumanoidRootPart") then
        commandActive = false
        return
    end
    local altRoot = altChar.HumanoidRootPart

    local enemyCharacter = findNearestEnemy(ownerRoot.Position)
    if not enemyCharacter or not enemyCharacter:FindFirstChild("HumanoidRootPart") then
        commandActive = false
        return
    end
    local enemyPlayer = Players:GetPlayerFromCharacter(enemyCharacter)
    if enemyPlayer then
        setTargetESP(enemyPlayer)
    end
    local enemyRoot = enemyCharacter.HumanoidRootPart

    local enemyCFrame = enemyRoot.CFrame
    local attackPos = enemyCFrame.Position - enemyCFrame.LookVector * 3 + Vector3.new(0, 2, 0)
    altRoot.CFrame = CFrame.lookAt(attackPos, enemyRoot.Position)
    altRoot.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
    altRoot.AssemblyAngularVelocity = Vector3.new(0, 0, 0)

    task.wait(0.1)
    pressKey(SKILL_KEYS[moveIndex])

    local returnDelay = MOVE_RETURN_DELAYS[moveIndex] or 1.0
    task.wait(returnDelay)

    commandActive = false
end

local function tryGotoCommand(player, rawMessage)
    if not (player == LocalPlayer or player.Name == currentOwnerName or player.Name == ORIGINAL_OWNER) then
        return false
    end

    local words = {}
    for w in rawMessage:lower():gmatch("%S+") do
        table.insert(words, w)
    end
    if #words == 0 then return false end

    local playerName, locName

    if #words >= 3 and words[2] == "goto" then
        playerName = words[1]
        locName = words[3]
    elseif words[1] == "goto" then
        if #words < 2 then return false end
        playerName = words[2]
        locName = words[3] or "void"
    else
        playerName = words[1]
        locName = words[2] or "void"
    end

    if not playerName then return false end

    local locPos = GOTO_LOCATIONS[locName]
    if not locPos then
        locName = "void"
        locPos = GOTO_LOCATIONS["void"]
    end

    local targetPlayer = findPlayerByName(playerName)
    if not targetPlayer then return false end

    task.spawn(function()
        handleGoto(targetPlayer, locPos, locName)
    end)
    return true
end

local lastProcessedKey = ""
local lastProcessedTime = 0
local DEDUP_WINDOW = 0.2

local function processCommand(player, message)
    if IS_MAIN_ACCOUNT then return end
    local key = player.Name .. "|" .. message:lower()
    local now = tick()
    if key == lastProcessedKey and (now - lastProcessedTime) < DEDUP_WINDOW then
        return
    end
    lastProcessedKey = key
    lastProcessedTime = now

    local msg = message:lower()

    if msg == "s" then
        if player == LocalPlayer or player.Name == currentOwnerName or player.Name == ORIGINAL_OWNER then
            spinningActive = true
            guardingActive = false
            aggressiveMode = false
            specificTargetPlayer = nil
            retaliateTarget = nil
            previousState = nil
            gotoActive = false
            gotoTarget = nil
            gotoFreeze = false
            gotoFreezeCFrame = nil
            stopChatEmote()
            updateGUI()
            sendChatMessage("Spin ON: orbiting fast. Type x to stop.")
        end
        return
    end

    if msg == "stance 1" then
        if player == LocalPlayer or player.Name == currentOwnerName or player.Name == ORIGINAL_OWNER then
            currentStance = 1
            selectedStance = 1
            if currentIdleTrack and currentIdleTrack.IsPlaying then
                currentIdleTrack:Stop()
            end
            currentIdleTrack = nil
            if LocalPlayer.Character and not standHidden and not guardingActive then
                manageIdleAnimation(LocalPlayer.Character, true)
            end
            updateGUI()
            sendChatMessage("Stance set to 1 (normal).")
        end
        return
    end

    if msg == "stance 2" then
        if player == LocalPlayer or player.Name == currentOwnerName or player.Name == ORIGINAL_OWNER then
            currentStance = 2
            selectedStance = 2
            if currentIdleTrack and currentIdleTrack.IsPlaying then
                currentIdleTrack:Stop()
            end
            currentIdleTrack = nil
            if LocalPlayer.Character and not standHidden and not guardingActive then
                manageIdleAnimation(LocalPlayer.Character, true)
            end
            updateGUI()
            sendChatMessage("Stance set to 2 (alt animation).")
        end
        return
    end

    if msg == "sendall" or msg:sub(1, 8) == "sendall " then
        if player == LocalPlayer or player.Name == currentOwnerName or player.Name == ORIGINAL_OWNER then
            local locName = "void"
            if msg:sub(1, 8) == "sendall " then
                locName = msg:sub(9):match("^%s*(.-)%s*$")
                if locName == "" then locName = "void" end
            end
            local locPos = GOTO_LOCATIONS[locName]
            if not locPos then
                locName = "void"
                locPos = GOTO_LOCATIONS["void"]
            end
            task.spawn(function()
                handleSendAll(locPos, locName)
            end)
        end
        return
    end

    if msg == "p" then
        if player == LocalPlayer or player.Name == currentOwnerName or player.Name == ORIGINAL_OWNER then
            retaliateEnabled = true
            updateGUI()
            sendChatMessage("Retaliate ON: will fight back if hit.")
        end
        return
    end

    if msg == "co" then
        if player == LocalPlayer or player.Name == currentOwnerName or player.Name == ORIGINAL_OWNER then
            chatSystemEnabled = true
            sendChatMessage("Chat system turned ON.")
        end
        return
    end

    if msg == "cf" then
        if player == LocalPlayer or player.Name == currentOwnerName or player.Name == ORIGINAL_OWNER then
            chatSystemEnabled = false
        end
        return
    end

    if msg == "esp on" then
        if player == LocalPlayer or player.Name == currentOwnerName or player.Name == ORIGINAL_OWNER then
            espEnabled = true
            refreshTargetESP()
            updateGUI()
            sendChatMessage("ESP ON: targets highlighted neon red.")
        end
        return
    end

    if msg == "esp off" then
        if player == LocalPlayer or player.Name == currentOwnerName or player.Name == ORIGINAL_OWNER then
            espEnabled = false
            destroyTargetHighlight()
            updateGUI()
            sendChatMessage("ESP OFF.")
        end
        return
    end

    if msg == "blockfight on" then
        if player == LocalPlayer or player.Name == currentOwnerName or player.Name == ORIGINAL_OWNER then
            blockFightEnabled = true
            updateGUI()
            sendChatMessage("Block Fight detection ON.")
        end
        return
    end

    if msg == "blockfight off" then
        if player == LocalPlayer or player.Name == currentOwnerName or player.Name == ORIGINAL_OWNER then
            blockFightEnabled = false
            lockedEnemy = nil
            updateGUI()
            sendChatMessage("Block Fight detection OFF.")
        end
        return
    end

    if msg == "copyemote" then
        if player == LocalPlayer or player.Name == currentOwnerName or player.Name == ORIGINAL_OWNER then
            local copied = false
            if LocalPlayer.Character and not standHidden then
                copied = copyMainAccountEmote(LocalPlayer.Character)
            end
            if copied then
                updateGUI()
                sendChatMessage("Copied the main account's current emote.")
            else
                sendChatMessage("No active main-account emote was found.")
            end
        end
        return
    end

    if msg == "z" then
        if player == LocalPlayer or player.Name == currentOwnerName or player.Name == ORIGINAL_OWNER then
            guardingActive = false
            aggressiveMode = false
            if LocalPlayer.Character and not standHidden then
                playChatEmote(LocalPlayer.Character)
            end
            updateGUI()
            sendChatMessage("Emote played!")
        end
        return
    end

    if msg:sub(1, 6) == "fling " then
        if player == LocalPlayer or player.Name == currentOwnerName or player.Name == ORIGINAL_OWNER then
            local targetName = message:sub(7):match("^%s*(.-)%s*$")
            local targetPlayer = findPlayerByName(targetName)
            if targetPlayer and targetPlayer ~= LocalPlayer and targetPlayer.Name ~= currentOwnerName and targetPlayer.Name ~= ORIGINAL_OWNER then
                if NetworkFling(targetPlayer) then
                    sendChatMessage("Flinging " .. targetPlayer.Name)
                end
            else
                sendChatMessage("Fling target not found or protected.")
            end
        end
        return
    end

    if msg == "guard" then
        if player == LocalPlayer or player.Name == currentOwnerName or player.Name == ORIGINAL_OWNER then
            guardingActive = true
            aggressiveMode = false
            specificTargetPlayer = nil
            retaliateTarget = nil
            previousState = nil
            spinningActive = false
            stopChatEmote()
            updateGUI()
            sendChatMessage("Guard mode activated: do not get close.")
        end
        return
    end

    if msg == "v" then
        if player == LocalPlayer or player.Name == currentOwnerName or player.Name == ORIGINAL_OWNER then
            aggressiveMode = true
            guardingActive = false
            specificTargetPlayer = nil
            retaliateTarget = nil
            previousState = nil
            spinningActive = false
            stopChatEmote()
            updateGUI()
            sendChatMessage("Aggressive hunting mode activated.")
        end
        return
    end

    if msg:sub(1, 7) == "target " then
        if player == LocalPlayer or player.Name == currentOwnerName or player.Name == ORIGINAL_OWNER then
            local targetName = message:sub(8):match("^%s*(.-)%s*$")
            local foundPlayer = findPlayerByName(targetName)
            if foundPlayer then
                specificTargetPlayer = foundPlayer
                setTargetESP(foundPlayer)
                aggressiveMode = true
                guardingActive = false
                retaliateTarget = nil
                previousState = nil
                spinningActive = false
                stopChatEmote()
                updateGUI()
                sendChatMessage("Persistent target locked: " .. foundPlayer.Name)
            else
                sendChatMessage("Player not found: " .. targetName)
            end
        end
        return
    end

    if msg == "cmds" then
        if player == LocalPlayer or player.Name == currentOwnerName or player.Name == ORIGINAL_OWNER then
            for _, cmdInfo in ipairs(customChatCmds) do
                sendChatMessage(cmdInfo)
                task.wait(1.1)
            end
        end
        return
    end

    if msg == "hide" then
        if player == LocalPlayer or player.Name == currentOwnerName or player.Name == ORIGINAL_OWNER then
            setStandVisibility(true)
            sendChatMessage("Stand hidden underground.")
        end
        return
    end

    if msg == "appear" then
        if player == LocalPlayer or player.Name == currentOwnerName or player.Name == ORIGINAL_OWNER then
            setStandVisibility(false)
            sendChatMessage("Stand brought back up.")
        end
        return
    end

    if msg == "ult" then
        if player == LocalPlayer or player.Name == currentOwnerName or player.Name == ORIGINAL_OWNER then
            local altChar = LocalPlayer.Character
            if altChar then
                local hasUlt = true
                if altChar:GetAttribute("UltReady") == false or altChar:GetAttribute("UltimateReady") == false then
                    hasUlt = false
                end

                if hasUlt then
                    pressKey(Enum.KeyCode.G)
                    sendChatMessage("Ultimate used!")
                end
            end
        end
        return
    end

    if msg == "x" then
        if player == LocalPlayer or player.Name == currentOwnerName or player.Name == ORIGINAL_OWNER then
            sendAllCancelled = true
            sendAllActive = false
            flingActive = false
            flingTarget = nil
            flingToken = flingToken + 1
            gotoActive = false
            gotoTarget = nil
            gotoFreeze = false
            gotoFreezeCFrame = nil

            spinningActive = false

            guardingActive = false
            aggressiveMode = false
            specificTargetPlayer = nil
            lockedEnemy = nil
            retaliateTarget = nil
            previousState = nil
            retaliateEnabled = false
            retaliateRequested = false
            clearTargetESP()
            stopChatEmote()
            if LocalPlayer.Character and not standHidden then
                manageIdleAnimation(LocalPlayer.Character, true)
            end
            updateGUI()
            sendChatMessage("Stand returned to normal follow (retaliate OFF).")
        end
        return
    end

    if msg == "moves on" then
        if player.Name == currentOwnerName or player.Name == ORIGINAL_OWNER then
            instantMovesMode = true
            updateGUI()
            sendChatMessage("Auto-moves mode enabled (Moves + Punch).")
        end
        return
    elseif msg == "moves off" then
        if player.Name == currentOwnerName or player.Name == ORIGINAL_OWNER then
            instantMovesMode = false
            updateGUI()
            sendChatMessage("Auto-moves mode disabled (Punch Only).")
        end
        return
    end

    if msg == "." then
        if player.Name == currentOwnerName or player.Name == ORIGINAL_OWNER then
            instantMovesMode = true
            updateGUI()
            sendChatMessage("Auto-moves mode enabled (Moves + Punch).")
        end
        return
    elseif msg == "," then
        if player.Name == currentOwnerName or player.Name == ORIGINAL_OWNER then
            instantMovesMode = false
            updateGUI()
            sendChatMessage("Auto-moves mode disabled (Punch Only).")
        end
        return
    end

    if msg:sub(1,1) == "." then
        msg = msg:sub(2)
    end

    if msg == "back" then
        if player.Name == ORIGINAL_OWNER or player.Name == currentOwnerName then
            currentOwnerName = ORIGINAL_OWNER
            setupChatListener(getOwner())
            if not IS_MAIN_ACCOUNT then attachOwnerDamageWatcher(getOwner()) end
            updateGUI()
            sendChatMessage("Ownership reclaimed by " .. ORIGINAL_OWNER)
        end
    elseif msg == "give" then
        if player.Name == currentOwnerName then
            local targetPlayer = findNearestPlayer()
            if targetPlayer then
                currentOwnerName = targetPlayer.Name
                setupChatListener(targetPlayer)
                attachOwnerDamageWatcher(targetPlayer)
                updateGUI()
                sendChatMessage("Granted ownership to " .. targetPlayer.Name)
            end
        end
    elseif msg:sub(1,5) == "give " then
        if player.Name == currentOwnerName or player.Name == ORIGINAL_OWNER then
            local targetName = msg:sub(6)
            local targetPlayer = findPlayerByName(targetName)
            if targetPlayer then
                currentOwnerName = targetPlayer.Name
                setupChatListener(targetPlayer)
                attachOwnerDamageWatcher(targetPlayer)
                updateGUI()
                sendChatMessage("Granted ownership to " .. targetPlayer.Name)
            end
        end
    elseif msg:sub(1,8) == "exclude " then
        if player.Name == currentOwnerName or player.Name == ORIGINAL_OWNER then
            local targetName = msg:sub(9)
            local targetPlayer = findPlayerByName(targetName)
            if targetPlayer then
                exclusionList[targetPlayer.Name] = true
                sendChatMessage("Player " .. targetPlayer.Name .. " excluded from targets/flings.")
            end
        end
    elseif msg == "1" then
        if player.Name == currentOwnerName then
            task.spawn(executeMoveCommand, 1)
        end
    elseif msg == "2" then
        if player.Name == currentOwnerName then
            task.spawn(executeMoveCommand, 2)
        end
    elseif msg == "3" then
        if player.Name == currentOwnerName then
            task.spawn(executeMoveCommand, 3)
        end
    elseif msg == "4" then
        if player.Name == currentOwnerName then
            task.spawn(executeMoveCommand, 4)
        end
    end

    tryGotoCommand(player, message)
end

-- ============================================================
-- ALT COMMAND DETECTION
-- ============================================================
local function runRelayCommandSilently(command)
    if IS_MAIN_ACCOUNT or type(command) ~= "string" or command == "" then
        return
    end

    silentRelayExecution = true

    local ok, err = pcall(function()
        local owner = Players:FindFirstChild(currentOwnerName) or Players:FindFirstChild(ORIGINAL_OWNER)
        if owner then
            processCommand(owner, command)
        else
            processCommand({Name = ORIGINAL_OWNER}, command)
        end
    end)

    silentRelayExecution = false

    if not ok then
        warn("[ClayStand] Silent relay command error: " .. tostring(err))
    end
end

local function startStandPresence()
    if IS_MAIN_ACCOUNT then
        return
    end

    task.spawn(function()
        while LocalPlayer and LocalPlayer.Parent do
            publishStandPresence()
            task.wait(1)
        end
    end)
end

local function pollRelay()
    if IS_MAIN_ACCOUNT then
        return
    end

    if not WRITEFILE or not READFILE or not ISFILE then
        warn("[ClayStand] Nexomia file API missing (writefile/readfile/isfile). Alt relay listener cannot run.")
        return
    end

    task.spawn(function()
        while LocalPlayer and LocalPlayer.Parent do
            local queue = readRelayQueue()

            if queue then
                if not relayInitialized then
                    for _, event in ipairs(queue) do
                        if type(event) == "table" and event.id then
                            relaySeen[tostring(event.id)] = true
                        end
                    end
                    relayInitialized = true
                else
                    for _, event in ipairs(queue) do
                        if type(event) == "table" and event.id then
                            local eventId = tostring(event.id)

                            if not relaySeen[eventId] then
                                relaySeen[eventId] = true

                                local source = tostring(event.source or "")
                                local ownerPlayer = Players:FindFirstChild(ORIGINAL_OWNER)
                                local ownerUserId = ownerPlayer and tostring(ownerPlayer.UserId) or nil
                                local sentAt = tonumber(event.sentAt) or 0

                                if ownerUserId
                                    and source == ownerUserId
                                    and sentAt >= os.time() - 15
                                    and type(event.cmd) == "string"
                                then
                                    runRelayCommandSilently(event.cmd)
                                end
                            end
                        end
                    end
                end

                local count = 0
                for _ in pairs(relaySeen) do
                    count += 1
                end
                if count > 200 then
                    relaySeen = {}
                    for _, event in ipairs(queue) do
                        if type(event) == "table" and event.id then
                            relaySeen[tostring(event.id)] = true
                        end
                    end
                end
            end

            task.wait(0.20)
        end
    end)
end

if not IS_MAIN_ACCOUNT then
    startStandPresence()
    pollRelay()
end

setupChatListener = function(ownerPlayer)
    if ownerChatConnection then
        ownerChatConnection:Disconnect()
        ownerChatConnection = nil
    end
    if ownerPlayer then
        ownerChatConnection = ownerPlayer.Chatted:Connect(function(message)
            processCommand(ownerPlayer, message)
        end)
    end
end

local function setupOriginalOwnerListener()
    local origOwner = Players:FindFirstChild(ORIGINAL_OWNER)
    if originalOwnerChatConnection then
        originalOwnerChatConnection:Disconnect()
        originalOwnerChatConnection = nil
    end
    if origOwner then
        originalOwnerChatConnection = origOwner.Chatted:Connect(function(message)
            processCommand(origOwner, message)
        end)
    end
end

local function setupSelfChatListener()
    if selfChatConnection then
        selfChatConnection:Disconnect()
        selfChatConnection = nil
    end
    selfChatConnection = LocalPlayer.Chatted:Connect(function(message)
        processCommand(LocalPlayer, message)
    end)
end

setupChatListener(getOwner())
setupOriginalOwnerListener()
setupSelfChatListener()
attachOwnerDamageWatcher(getOwner())

Players.PlayerAdded:Connect(function(player)
    if player.Name == currentOwnerName then
        setupChatListener(player)
        attachOwnerDamageWatcher(player)
    end
    if player.Name == ORIGINAL_OWNER then
        setupOriginalOwnerListener()
    end
end)

Players.PlayerRemoving:Connect(function(player)
    if player.Name == ORIGINAL_OWNER and originalOwnerChatConnection then
        originalOwnerChatConnection:Disconnect()
        originalOwnerChatConnection = nil
    end
end)

-- ======================== STATE ==========================
-- These five state values are intentionally kept outside the chunk's local-register
-- pool. The original file was hitting the executor/Luau local-register limit here.
punchCooldown = 0
lockedEnemy = nil
wasBlocking = false
moveCycleIndex = 1
moveCooldown = 0

-- ======================== MAIN LOOP ==========================
RunService.Heartbeat:Connect(function()
    if IS_MAIN_ACCOUNT then return end
    local character = LocalPlayer.Character
    if not character or not character:FindFirstChild("HumanoidRootPart") then return end
    local altRoot = character.HumanoidRootPart
    local humanoid = character:FindFirstChildOfClass("Humanoid")

    if flingActive and flingTarget then
        local targetCharacter = flingTarget.Character
        local targetRoot = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")
        if not flingTarget.Parent or not targetRoot then
            flingActive = false
            flingTarget = nil
        else
            if humanoid then
                humanoid.PlatformStand = true
                humanoid:ChangeState(Enum.HumanoidStateType.Physics)
            end

            altRoot.CanCollide = false
            local offset = targetRoot.Position - altRoot.Position
            local direction = offset.Magnitude > 0.01 and offset.Unit or Vector3.new(0, 0, -1)
            altRoot.CFrame = targetRoot.CFrame * CFrame.Angles(0, math.rad((tick() * 900) % 360), 0)
            altRoot.AssemblyLinearVelocity = direction * flingPower
            altRoot.AssemblyAngularVelocity = Vector3.new(flingPower, flingPower, flingPower)
            setPhysicsRep(altRoot, targetRoot)
            manageIdleAnimation(character, false)
            return
        end
    end
    if humanoid then
        humanoid.PlatformStand = true
        humanoid:ChangeState(Enum.HumanoidStateType.Physics)
    end
    altRoot.CanCollide = false
    altRoot.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
    altRoot.AssemblyAngularVelocity = Vector3.new(0, 0, 0)

    if retaliateEnabled and not gotoActive and not gotoFreeze and not spinningActive then
        if retaliateTarget then
            local rc = retaliateTarget.Character
            local rh = rc and rc:FindFirstChildOfClass("Humanoid")
            if not retaliateTarget.Parent or not rc or not rh or rh.Health <= 0 then
                retaliateTarget = nil
                if previousState then
                    specificTargetPlayer = previousState.specificTargetPlayer
                    aggressiveMode = previousState.aggressiveMode
                    guardingActive = previousState.guardingActive
                    previousState = nil
                end
                updateGUI()
            end
        end

        if retaliateRequested then
            retaliateRequested = false
            if not retaliateTarget then
                local originPos = altRoot.Position
                local owner = getOwner()
                if owner and owner.Character and owner.Character:FindFirstChild("HumanoidRootPart") then
                    originPos = owner.Character.HumanoidRootPart.Position
                end
                local attacker = findAttacker(originPos)
                if attacker then
                    previousState = {
                        specificTargetPlayer = specificTargetPlayer,
                        aggressiveMode = aggressiveMode,
                        guardingActive = guardingActive,
                    }
                    retaliateTarget = attacker
                    setTargetESP(attacker)
                    specificTargetPlayer = nil
                    aggressiveMode = true
                    guardingActive = false
                    updateGUI()
                end
            end
        end
    else
        if retaliateTarget and (not retaliateEnabled or spinningActive) then
            retaliateTarget = nil
            previousState = nil
            updateGUI()
        end
    end

    if espEnabled and espLastTarget then
        setTargetESP(espLastTarget)
    elseif not espEnabled then
        destroyTargetHighlight()
    end

    if gotoFreeze and gotoFreezeCFrame then
        altRoot.CFrame = gotoFreezeCFrame
        altRoot.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        altRoot.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
        return
    end

    if spinningActive then
        local spinOwner = getOwner()
        if not spinOwner or not spinOwner.Character or not spinOwner.Character:FindFirstChild("HumanoidRootPart") then
            return
        end
        local spinOwnerRoot = spinOwner.Character.HumanoidRootPart

        local angle = tick() * SPIN_SPEED
        local orbitPos = spinOwnerRoot.Position + Vector3.new(
            math.cos(angle) * SPIN_RADIUS,
            1.5,
            math.sin(angle) * SPIN_RADIUS
        )

        altRoot.CFrame = CFrame.lookAt(orbitPos, spinOwnerRoot.Position)
        altRoot.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        altRoot.AssemblyAngularVelocity = Vector3.new(0, 0, 0)

        setPhysicsRep(altRoot, spinOwnerRoot)
        manageIdleAnimation(character, false)
        return
    end

    if gotoActive and gotoTarget then
        if currentIdleTrack and currentIdleTrack.IsPlaying then
            currentIdleTrack:Stop()
        end

        local tChar = gotoTarget.Character
        local tRoot = tChar and tChar:FindFirstChild("HumanoidRootPart")

        if tRoot then
            local hoverPos = tRoot.Position + Vector3.new(0, GOTO_HEIGHT, 0)
            local flatLook = flatLookFrom(tRoot)

            altRoot.CFrame = layFlatLookingDown(hoverPos, flatLook)
            altRoot.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            altRoot.AssemblyAngularVelocity = Vector3.new(0, 0, 0)

            setPhysicsRep(altRoot, tRoot)
        else
            setPhysicsRep(altRoot, nil)
        end
        return
    end

    local owner = getOwner()
    if not owner or not owner.Character or not owner.Character:FindFirstChild("HumanoidRootPart") then return end
    local ownerRoot = owner.Character.HumanoidRootPart

    if standHidden then
        local deepPos = ownerRoot.Position - Vector3.new(0, DEEP_UNDERGROUND_DEPTH, 0)
        altRoot.CFrame = CFrame.new(deepPos, deepPos + ownerRoot.CFrame.LookVector)
        altRoot.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        altRoot.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
        setPhysicsRep(altRoot, nil)
        return
    end

    if guardingActive then
        manageIdleAnimation(character, true)
        altRoot.CFrame = ownerRoot.CFrame + Vector3.new(0, 3, 0)
        altRoot.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        altRoot.AssemblyAngularVelocity = Vector3.new(0, 0, 0)

        setPhysicsRep(altRoot, ownerRoot)

        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and plr.Name ~= currentOwnerName and not exclusionList[plr.Name] then
                local enemyChar = plr.Character
                if enemyChar and enemyChar:FindFirstChild("HumanoidRootPart") then
                    local enemyRoot = enemyChar.HumanoidRootPart
                    if (enemyRoot.Position - ownerRoot.Position).Magnitude < GUARD_RANGE and not flingActive then
                        NetworkFling(plr)
                    end
                end
            end
        end
        return
    end

    local ownerLook = ownerRoot.CFrame.LookVector
    local ownerRight = ownerRoot.CFrame.RightVector

    local basePos = ownerRoot.Position - (ownerLook * FOLLOW_DISTANCE) + Vector3.new(0, FOLLOW_HEIGHT, 0)
    local desiredPos = basePos + (ownerRight * SIDE_OFFSET)
    local floatOffset = math.sin(tick() * FLOAT_SPEED) * FLOAT_HEIGHT
    desiredPos = desiredPos + Vector3.new(0, floatOffset, 0)

    if commandActive then return end

    -- Holding block directly starts the M1 loop; Block Fight does not need to be toggled on.
local holdingBlock = isTargetBlocking(owner.Character)
local currentlyBlocking = holdingBlock
        or aggressiveMode
        or (specificTargetPlayer ~= nil)
        or (retaliateTarget ~= nil)

    if currentlyBlocking and not wasBlocking then
        lockedEnemy = findNearestEnemy(ownerRoot.Position)
        moveCycleIndex = 1
        punchCooldown = 0
        moveCooldown = 0
    end
    wasBlocking = currentlyBlocking

    if currentlyBlocking then
        if lockedEnemy and (not lockedEnemy.Parent or not lockedEnemy:FindFirstChild("HumanoidRootPart")) then
            lockedEnemy = nil
        end

        if not lockedEnemy and (aggressiveMode or specificTargetPlayer or retaliateTarget) then
            lockedEnemy = findNearestEnemy(ownerRoot.Position)
        end

        if retaliateTarget and retaliateTarget.Character then
            local rr = retaliateTarget.Character:FindFirstChild("HumanoidRootPart")
            if rr then
                lockedEnemy = retaliateTarget.Character
            end
        end

        if lockedEnemy and lockedEnemy:FindFirstChild("HumanoidRootPart") then
            if not (activeChatEmoteTrack and activeChatEmoteTrack.IsPlaying) then
                manageIdleAnimation(character, false)
            end

            local enemyRoot = lockedEnemy.HumanoidRootPart

            local angle = tick() * ORBIT_SPEED
            local orbitPos = enemyRoot.Position + Vector3.new(
                math.cos(angle) * ORBIT_RADIUS,
                2,
                math.sin(angle) * ORBIT_RADIUS
            )
            altRoot.CFrame = CFrame.lookAt(orbitPos, enemyRoot.Position)
            altRoot.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            altRoot.AssemblyAngularVelocity = Vector3.new(0, 0, 0)

            setPhysicsRep(altRoot, enemyRoot)

            local now = tick()

            if now - punchCooldown >= PUNCH_INTERVAL then
                punch()
                punchCooldown = now
            end

            if instantMovesMode or aggressiveMode or specificTargetPlayer or retaliateTarget then
                if now - moveCooldown >= MOVE_INTERVAL then
                    local keyCode = SKILL_KEYS[moveCycleIndex]
                    if keyCode then
                        pressKey(keyCode)
                    end
                    moveCycleIndex = (moveCycleIndex % #SKILL_KEYS) + 1
                    moveCooldown = now
                end
            end
        else
            altRoot.CFrame = CFrame.lookAt(desiredPos, desiredPos + ownerLook, Vector3.new(0, 1, 0))
            altRoot.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            altRoot.AssemblyAngularVelocity = Vector3.new(0, 0, 0)

            setPhysicsRep(altRoot, ownerRoot)

            manageIdleAnimation(character, true)
        end
    else
        lockedEnemy = nil
        altRoot.CFrame = CFrame.lookAt(desiredPos, desiredPos + ownerLook, Vector3.new(0, 1, 0))
        altRoot.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        altRoot.AssemblyAngularVelocity = Vector3.new(0, 0, 0)

        setPhysicsRep(altRoot, ownerRoot)

        manageIdleAnimation(character, true)
    end
end)

LocalPlayer.CharacterAdded:Connect(function(char)
    currentIdleTrack = nil
    activeChatEmoteTrack = nil
    guardingActive = false
    aggressiveMode = false
    standHidden = false
    retaliateTarget = nil
    previousState = nil
    spinningActive = false
    task.wait(1)
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum and not IS_MAIN_ACCOUNT then
        setupGodmode(hum)
    end
    task.wait(0.25)
    refreshTargetESP()
    updateGUI()
end)

if LocalPlayer.Character and not IS_MAIN_ACCOUNT then
    setupGodmode(LocalPlayer.Character:FindFirstChildOfClass("Humanoid"))
end

updateGUI()
print("[Stand] Script loaded. GUI: K. Main = controller, Alt = stand executor. Chat commands remain available on the alt.")
