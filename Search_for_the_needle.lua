-- Candy Corn Farm — consolidated
-- Farm: hover + look-down + TP to skeleton + input-simulated pitchfork swing
--   PC  : left-click at screen center each swingRate
--   Mobile: taps at touch anchor (drag circle to swing button)
-- Auto Buy / Pitchfork Upg / Auto Candle1 pipelines unchanged
-- Anti-AFK: always on

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local CoreGui           = game:GetService("CoreGui")
local VirtualUser       = game:GetService("VirtualUser")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player            = Players.LocalPlayer
local camera            = workspace.CurrentCamera

if CoreGui:FindFirstChild("CandyCornFarmMenu") then
    CoreGui.CandyCornFarmMenu:Destroy()
end

local IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
local IS_PC     = not IS_MOBILE

------------------------------------------------------------
-- REMOTES
------------------------------------------------------------
local buyShopItem, buyUpgrade, pickUpCandle, placeCandle
do
    local ok, container = pcall(function()
        return ReplicatedStorage:WaitForChild("NeedleHaystack", 10)
    end)
    if ok and container then
        buyShopItem  = container:WaitForChild("BuyShopItem", 10)
        buyUpgrade   = container:WaitForChild("BuyUpgrade", 10)
    end
end
do
    local ok, remotes = pcall(function()
        return ReplicatedStorage:WaitForChild("CandleRitual", 10)
            :WaitForChild("Remotes", 5)
    end)
    if ok and remotes then
        pickUpCandle = remotes:WaitForChild("PickUpCandle", 5)
        placeCandle  = remotes:WaitForChild("PlaceCandle", 5)
    end
end

------------------------------------------------------------
-- STATE
------------------------------------------------------------
local state = {
    farming       = false,
    autoBuy       = false,
    upgrading     = false,
    candles       = false,
    hoverHeight   = 8,
    groundClear   = 6,
    pitchDeg      = 80,
    interval      = 0.15,
    lookDown      = true,
    antiAFK       = true,
    upgradeRate   = 0.1,
    swingRate     = 0.25,
    candleRate    = 0.1,
    candleOffset  = Vector3.new(0, 3, 0),
    candleLiftTol = 1.0,
    placeDelay    = 0.4,
    touchAnchor   = nil,
}

------------------------------------------------------------
-- TARGET RESOLUTION
------------------------------------------------------------
local function resolveSkeletonTarget()
    local effects = workspace:FindFirstChild("PumpkinBossEffects")
    if not effects then return nil end
    local child = effects:GetChildren()[3]
    if child then
        local gs = child:FindFirstChild("GraveSkeleton_Glow")
        if gs then return gs end
    end
    for _, c in ipairs(effects:GetChildren()) do
        local gs = c:FindFirstChild("GraveSkeleton_Glow")
        if gs then return gs end
    end
    return nil
end

local function resolveCandle()
    local hay = workspace:FindFirstChild("HayCandles")
    if not hay then return nil end
    local c1 = hay:FindFirstChild("Candle1")
    if not c1 then return nil end
    local inner = c1:FindFirstChild("Candle")
    if not inner then return nil end
    return inner, c1
end

local function resolvePlaceSpot()
    local wtp = workspace:FindFirstChild("WhereToPlaceCandles")
    if not wtp then return nil end
    return wtp:FindFirstChild("1")
end

------------------------------------------------------------
-- GUI
------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "CandyCornFarmMenu"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 9999
gui.Parent = CoreGui

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 270, 0, 220)
frame.Position = UDim2.new(0, 20, 0, 100)
frame.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = gui

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(255, 170, 40)
stroke.Thickness = 1
stroke.Parent = frame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -16, 0, 22)
title.Position = UDim2.new(0, 8, 0, 4)
title.BackgroundTransparency = 1
title.Text = "CANDY CORN FARM"
title.TextColor3 = Color3.fromRGB(255, 170, 40)
title.Font = Enum.Font.Code
title.TextSize = 13
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = frame

local function makeToggle(y, text)
    local t = Instance.new("TextButton")
    t.Size = UDim2.new(0, 42, 0, 20)
    t.Position = UDim2.new(1, -54, 0, y)
    t.BackgroundColor3 = Color3.fromRGB(40, 40, 46)
    t.BorderSizePixel = 0
    t.Text = ""
    t.AutoButtonColor = false
    t.Parent = frame
    local c1 = Instance.new("UICorner") c1.CornerRadius = UDim.new(1, 0) c1.Parent = t
    local k = Instance.new("Frame")
    k.Size = UDim2.new(0, 16, 0, 16)
    k.Position = UDim2.new(0, 2, 0, 2)
    k.BackgroundColor3 = Color3.fromRGB(180, 180, 180)
    k.BorderSizePixel = 0
    k.Parent = t
    local c2 = Instance.new("UICorner") c2.CornerRadius = UDim.new(1, 0) c2.Parent = k
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, -70, 0, 20)
    l.Position = UDim2.new(0, 8, 0, y)
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextColor3 = Color3.fromRGB(160, 160, 160)
    l.Font = Enum.Font.Code
    l.TextSize = 12
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = frame
    return { track = t, knob = k, label = l }
end

local farmT = makeToggle(30,  "Farm: OFF")
local buyT  = makeToggle(56,  "Auto Buy: OFF")
local upT   = makeToggle(82,  "Pitchfork Upg: OFF")
local candT = makeToggle(108, "Auto Candle1: OFF")

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -16, 0, 80)
status.Position = UDim2.new(0, 8, 0, 134)
status.BackgroundTransparency = 1
status.Text = IS_MOBILE and "mobile — drag circle over swing button" or "pc — left click auto"
status.TextColor3 = Color3.fromRGB(120, 120, 120)
status.Font = Enum.Font.Code
status.TextSize = 10
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextYAlignment = Enum.TextYAlignment.Top
status.TextWrapped = true
status.Parent = frame

local function renderToggle(t, on, onText, offText)
    t.track.BackgroundColor3 = on and Color3.fromRGB(255, 170, 40) or Color3.fromRGB(40, 40, 46)
    t.knob.Position = on and UDim2.new(1, -18, 0, 2) or UDim2.new(0, 2, 0, 2)
    t.knob.BackgroundColor3 = on and Color3.fromRGB(20, 20, 20) or Color3.fromRGB(180, 180, 180)
    t.label.Text = on and onText or offText
    t.label.TextColor3 = on and Color3.fromRGB(255, 170, 40) or Color3.fromRGB(160, 160, 160)
end

renderToggle(farmT, false, "Farm: ON",          "Farm: OFF")
renderToggle(buyT,  false, "Auto Buy: ON",      "Auto Buy: OFF")
renderToggle(upT,   false, "Pitchfork Upg: ON", "Pitchfork Upg: OFF")
renderToggle(candT, false, "Auto Candle1: ON",  "Auto Candle1: OFF")

------------------------------------------------------------
-- MOBILE TOUCH ANCHOR
------------------------------------------------------------
local anchor
if IS_MOBILE then
    anchor = Instance.new("Frame")
    anchor.Name = "CC_TouchAnchor"
    anchor.Size = UDim2.new(0, 90, 0, 90)
    anchor.Position = UDim2.new(0.7, 0, 0.6, 0)
    anchor.BackgroundTransparency = 0.55
    anchor.BackgroundColor3 = Color3.fromRGB(255, 170, 40)
    anchor.BorderSizePixel = 0
    anchor.Active = true
    anchor.ZIndex = 10000
    anchor.Parent = gui

    local ac = Instance.new("UICorner") ac.CornerRadius = UDim.new(1, 0) ac.Parent = anchor

    local astroke = Instance.new("UIStroke")
    astroke.Color = Color3.fromRGB(255, 220, 120)
    astroke.Thickness = 2
    astroke.Parent = anchor

    local alabel = Instance.new("TextLabel")
    alabel.Size = UDim2.new(1, 0, 1, 0)
    alabel.BackgroundTransparency = 1
    alabel.Text = "SWING"
    alabel.TextColor3 = Color3.fromRGB(20, 20, 20)
    alabel.Font = Enum.Font.Code
    alabel.TextSize = 12
    alabel.Parent = anchor

    state.touchAnchor = Vector2.new(
        anchor.AbsolutePosition.X + anchor.AbsoluteSize.X / 2,
        anchor.AbsolutePosition.Y + anchor.AbsoluteSize.Y / 2
    )

    local dragging, dragStart, startPos
    anchor.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging  = true
            dragStart = input.Position
            startPos  = anchor.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            anchor.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            if dragging then
                dragging = false
                state.touchAnchor = Vector2.new(
                    anchor.AbsolutePosition.X + anchor.AbsoluteSize.X / 2,
                    anchor.AbsolutePosition.Y + anchor.AbsoluteSize.Y / 2
                )
                print("[CC] touch anchor:", state.touchAnchor)
            end
        end
    end)
end

------------------------------------------------------------
-- ANTI-AFK
------------------------------------------------------------
player.Idled:Connect(function()
    if not state.antiAFK then return end
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)

------------------------------------------------------------
-- PITCHFORK — INPUT SIMULATION
------------------------------------------------------------
local function screenCenter()
    local vps = camera.ViewportSize
    return Vector2.new(vps.X / 2, vps.Y / 2)
end

local function getAnchorPoint()
    if IS_MOBILE then
        return state.touchAnchor or screenCenter()
    end
    return screenCenter()
end

local function tapAt(pos)
    if not pos then return end

    -- Path A: VirtualUser (universal)
    pcall(function() VirtualUser:Button1Down(pos) end)
    task.wait(0.05)
    pcall(function() VirtualUser:Button1Up(pos) end)

    -- Path B: executor globals if present
    if IS_MOBILE then
        pcall(function() if touchclick then touchclick(pos.X, pos.Y) end end)
        pcall(function() if tap        then tap(pos.X, pos.Y)        end end)
    end
end

local function swingPitchfork()
    tapAt(getAnchorPoint())
    return true
end

------------------------------------------------------------
-- HOVER / TP LOOP
------------------------------------------------------------
local hoverBV, hoverBG, loopConn

local function ensureHoverInstances(hrp)
    if not hoverBV or hoverBV.Parent ~= hrp then
        if hoverBV then hoverBV:Destroy() end
        hoverBV = Instance.new("BodyVelocity")
        hoverBV.Name = "CC_HoverBV"
        hoverBV.MaxForce = Vector3.new(1e5, 1e5, 1e5)
        hoverBV.P = 1e4
        hoverBV.Parent = hrp
    end
    if not hoverBG or hoverBG.Parent ~= hrp then
        if hoverBG then hoverBG:Destroy() end
        hoverBG = Instance.new("BodyGyro")
        hoverBG.Name = "CC_HoverBG"
        hoverBG.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
        hoverBG.P = 1e4
        hoverBG.Parent = hrp
    end
end

local function clearHover()
    if hoverBV then hoverBV:Destroy() hoverBV = nil end
    if hoverBG then hoverBG:Destroy() hoverBG = nil end
end

local function groundY()
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { char }
    local origin = hrp.Position + Vector3.new(0, 50, 0)
    local result = workspace:Raycast(origin, Vector3.new(0, -500, 0), params)
    if result then return result.Position.Y end
    return nil
end

local lastSwing = 0

local function startLoop()
    if loopConn then return end
    loopConn = RunService.Heartbeat:Connect(function()
        if not state.farming then return end

        local char = player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        ensureHoverInstances(hrp)

        local target = resolveSkeletonTarget()
        if target then
            local tPos = target.Position
            hrp.CFrame = CFrame.new(Vector3.new(tPos.X, tPos.Y + state.hoverHeight, tPos.Z))
            hoverBV.Velocity = Vector3.new(0, 0, 0)
            status.Text = "skeleton: " .. target.Name
        else
            local gy = groundY()
            if gy then
                local wantY = gy + state.groundClear
                local cur = hrp.Position
                hrp.CFrame = CFrame.new(Vector3.new(cur.X, wantY, cur.Z))
                status.Text = string.format("no skeleton — hover @ y=%.1f", wantY)
            else
                status.Text = "no skeleton — no ground ray"
            end
            hoverBV.Velocity = Vector3.new(0, 0, 0)
        end

        hoverBG.CFrame = CFrame.new(hrp.Position, hrp.Position + Vector3.new(0, 0, -1))

        local now = tick()
        if now - lastSwing >= state.swingRate then
            lastSwing = now
            swingPitchfork()
        end

        task.wait(state.interval)
    end)
end

local function stopLoop()
    if loopConn then loopConn:Disconnect() loopConn = nil end
    clearHover()
end

------------------------------------------------------------
-- CAMERA PITCH
------------------------------------------------------------
local function installLookDown()
    pcall(function() RunService:UnbindFromRenderStep("CC_LookDown") end)
    if not state.lookDown then return end
    RunService:BindToRenderStep("CC_LookDown", Enum.RenderPriority.Camera.Value + 3, function()
        if not state.farming or not state.lookDown then return end
        local origin = camera.CFrame.Position
        local pitch = math.rad(state.pitchDeg)
        local dir = Vector3.new(0, -math.sin(pitch), -math.cos(pitch))
        camera.CFrame = CFrame.new(origin, origin + dir)
    end)
end

installLookDown()

------------------------------------------------------------
-- CANDLE1 PIPELINE
------------------------------------------------------------
local candleConn
local candleRestY = nil
local candleStage = "wait"
local pickedUpAt  = 0

local function candleAirborne(inner)
    if not inner then return false, nil end
    if candleRestY == nil then
        candleRestY = inner.Position.Y
        return false, candleRestY
    end
    if inner.Position.Y < candleRestY then
        candleRestY = inner.Position.Y
    end
    return (inner.Position.Y - candleRestY) > state.candleLiftTol, candleRestY
end

local function tpTo(pos)
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    hrp.CFrame = CFrame.new(pos + state.candleOffset)
    hrp.Velocity = Vector3.zero
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero
    return true
end

local function firePickUp(wrapper)
    if not pickUpCandle or not wrapper then return false end
    pickUpCandle:FireServer(wrapper)
    return true
end

local function firePlace(spot)
    if not placeCandle or not spot then return false end
    placeCandle:FireServer(spot)
    return true
end

local function candleOnce()
    local inner, wrapper = resolveCandle()
    if not inner or not wrapper then return false, "no Candle1" end

    if candleStage == "wait" then
        local airborne, rest = candleAirborne(inner)
        if not airborne then
            return true, string.format("grounded — waiting | y=%.2f rest=%.2f",
                inner.Position.Y, rest or 0)
        end
        tpTo(inner.Position)
        local fired = firePickUp(wrapper)
        for _, root in ipairs({ inner, wrapper }) do
            if root then
                for _, d in ipairs(root:GetDescendants()) do
                    if d:IsA("ClickDetector") then
                        pcall(function() fireclickdetector(d) end)
                    elseif d:IsA("ProximityPrompt") then
                        pcall(function() fireproximityprompt(d) end)
                    end
                end
            end
        end
        candleStage = "pickedUp"
        pickedUpAt  = tick()
        return true, string.format("PICKUP=%s — placing in %.2fs", tostring(fired), state.placeDelay)
    end

    if candleStage == "pickedUp" then
        local elapsed = tick() - pickedUpAt
        if elapsed < state.placeDelay then
            return true, string.format("holding — %.2fs until place", state.placeDelay - elapsed)
        end
        local spot = resolvePlaceSpot()
        if not spot then return true, "no WhereToPlaceCandles['1']" end
        tpTo(spot.Position)
        local fired = firePlace(spot)
        candleStage = "wait"
        candleRestY = nil
        return true, string.format("PLACE=%s — cycle done", tostring(fired))
    end

    return true, "unknown stage"
end

local function startCandles()
    if candleConn then return end
    candleRestY = nil
    candleStage = "wait"
    candleConn = task.spawn(function()
        while state.candles do
            local ok, msg = candleOnce()
            status.Text = msg
            task.wait(state.candleRate)
        end
    end)
end

local function stopCandles()
    state.candles = false
    if candleConn then
        pcall(function() task.cancel(candleConn) end)
        candleConn = nil
    end
end

------------------------------------------------------------
-- AUTO BUY
------------------------------------------------------------
local function fireBuy()
    if not buyShopItem then
        status.Text = "BuyShopItem remote missing"
        return false
    end
    buyShopItem:FireServer("Pitchfork")
    return true
end

------------------------------------------------------------
-- UPGRADE LOOP
------------------------------------------------------------
local upgradeConn

local function startUpgrade()
    if upgradeConn then return end
    upgradeConn = task.spawn(function()
        while state.upgrading do
            if buyUpgrade then
                buyUpgrade:FireServer("PitchforkCooldown")
                buyUpgrade:FireServer("PitchforkHold")
                buyUpgrade:FireServer("Pitchfork")
                status.Text = "upgrading..."
            else
                status.Text = "BuyUpgrade remote missing"
            end
            task.wait(state.upgradeRate)
        end
    end)
end

local function stopUpgrade()
    state.upgrading = false
    if upgradeConn then
        pcall(function() task.cancel(upgradeConn) end)
        upgradeConn = nil
    end
end

------------------------------------------------------------
-- WIRING
------------------------------------------------------------
farmT.track.MouseButton1Click:Connect(function()
    state.farming = not state.farming
    renderToggle(farmT, state.farming, "Farm: ON", "Farm: OFF")
    if state.farming then startLoop() status.Text = "farm on" else stopLoop() status.Text = "idle" end
end)

buyT.track.MouseButton1Click:Connect(function()
    if fireBuy() then status.Text = "bought pitchfork" end
    renderToggle(buyT, true, "Auto Buy: ON", "Auto Buy: OFF")
    task.wait(0.15)
    renderToggle(buyT, false, "Auto Buy: ON", "Auto Buy: OFF")
end)

upT.track.MouseButton1Click:Connect(function()
    state.upgrading = not state.upgrading
    renderToggle(upT, state.upgrading, "Pitchfork Upg: ON", "Pitchfork Upg: OFF")
    if state.upgrading then startUpgrade() else stopUpgrade() status.Text = "upgrade stopped" end
end)

candT.track.MouseButton1Click:Connect(function()
    state.candles = not state.candles
    renderToggle(candT, state.candles, "Auto Candle1: ON", "Auto Candle1: OFF")
    if state.candles then startCandles() else stopCandles() status.Text = "candle stopped" end
end)

------------------------------------------------------------
-- CONSOLE HELPERS
------------------------------------------------------------
function setPitch(d)       state.pitchDeg = math.clamp(d, 0, 89) end
function setHover(h)       state.hoverHeight = h end
function setGround(h)      state.groundClear = h end
function setUpgradeRate(r) state.upgradeRate = r end
function setSwingRate(r)   state.swingRate = r end
function setCandleRate(r)  state.candleRate = r end
function setPlaceDelay(d)  state.placeDelay = d print("[CC] placeDelay", d) end
function setCandleOffset(x, y, z)
    state.candleOffset = Vector3.new(x, y, z)
    print("[CC] candleOffset", state.candleOffset)
end
function setCandleLiftTol(t)
    state.candleLiftTol = t
    print("[CC] candleLiftTol", t)
end

function setTouchAnchor(x, y)
    state.touchAnchor = Vector2.new(x, y)
    if anchor then
        anchor.Position = UDim2.new(0, x - 45, 0, y - 45)
    end
    print("[CC] touchAnchor", state.touchAnchor)
end

function resetCandleBaseline()
    candleRestY = nil
    candleStage = "wait"
    print("[CC] candle baseline reset")
end

function candleInfo()
    local inner, wrapper = resolveCandle()
    if not inner then print("[CC] no Candle1") return end
    local air, rest = candleAirborne(inner)
    print("[CC] y:", inner.Position.Y, "rest:", rest, "airborne:", air, "stage:", candleStage)
end

function whereCandle()
    local inner, wrapper = resolveCandle()
    if not inner then print("[CC] no Candle1") return end
    print("[CC] wrapper:", wrapper:GetFullName(), wrapper.Position)
    print("[CC] inner:  ", inner:GetFullName(), inner.Position)
    local spot = resolvePlaceSpot()
    if spot then print("[CC] place spot:", spot:GetFullName(), spot.Position) end
end

function swingOnce()
    print("[CC] tap at", getAnchorPoint())
    swingPitchfork()
end

function platform()
    print("[CC] mobile:", IS_MOBILE, "pc:", IS_PC, "anchor:", state.touchAnchor)
end

function tpCandleOnce()  print("[CC]", select(2, candleOnce())) end
function firePlaceOnce()
    local spot = resolvePlaceSpot()
    if not spot then print("[CC] no place spot") return end
    print("[CC] place fired:", firePlace(spot))
end

_G.setPitch            = setPitch
_G.setHover            = setHover
_G.setGround           = setGround
_G.setUpgradeRate      = setUpgradeRate
_G.setSwingRate        = setSwingRate
_G.setCandleRate       = setCandleRate
_G.setPlaceDelay       = setPlaceDelay
_G.setCandleOffset     = setCandleOffset
_G.setCandleLiftTol    = setCandleLiftTol
_G.setTouchAnchor      = setTouchAnchor
_G.resetCandleBaseline = resetCandleBaseline
_G.candleInfo          = candleInfo
_G.whereCandle         = whereCandle
_G.swingOnce           = swingOnce
_G.platform            = platform
_G.tpCandleOnce        = tpCandleOnce
_G.firePlaceOnce       = firePlaceOnce

print("[CC] loaded. platform:", IS_MOBILE and "mobile" or "pc")
