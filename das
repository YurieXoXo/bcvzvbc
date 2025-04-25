-- AutoParry with Skin Changer and Hit Effects Integration

-- Load UI Library
local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/Jxereas/UI-Libraries/main/cerberus.lua"))()
local window = Library.new("Yamaz")
window:LockScreenBoundaries(true)

-- Tabs
local parryTab   = window:Tab("Parry")
local visualTab  = window:Tab("Visual")
local skinTab    = window:Tab("Skin Changer")

-- Sections
local parrySection  = parryTab:Section("Parry Settings")
local visualSection = visualTab:Section("Visual Settings")
local skinSection   = skinTab:Section("Skin Changer")

-- Toggles & Keybind
local autoParryEnabled = false
local autoSpamEnabled  = false
local beamEnabled      = false
local spamIndicator
local hitEffectsEnabled = false
local selectedEffectId = "18865989002" -- Default Halo

parrySection:Toggle("Auto Parry", function(val)
    autoParryEnabled = val
end)

spamIndicator = parrySection:Label("Spamming: Off [Press G to spam]")

visualSection:Toggle("Trajectory Beam", function(val)
    beamEnabled = val
end)

visualSection:Toggle("Hit Effects", function(val)
    hitEffectsEnabled = val
end)

local effectsDropdown = visualSection:Dropdown("Effects")
effectsDropdown:Toggle("Halo ", function()
    selectedEffectId = "18865989002"
end)
effectsDropdown:Toggle("UwU ", function()
    selectedEffectId = "8679659744"
end)
effectsDropdown:Toggle("lazer ", function()
    selectedEffectId = "1624609598"
end)
effectsDropdown:Toggle("chicken ", function()
    selectedEffectId = "4510529019"
end)

-- Bind G key for spam toggle
local UserInputService = game:GetService("UserInputService")
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.G then
        autoSpamEnabled = not autoSpamEnabled
        spamIndicator:ChangeText("Spamming: " .. (autoSpamEnabled and "On" or "Off") .. " [Press G to spam]")
    end
end)

-- Services
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local VirtualInputManager = game:GetService("VirtualInputManager")
local LocalPlayer = Players.LocalPlayer
local ballsFolder = Workspace:WaitForChild("Balls")

-- Beam Setup
local beam = Instance.new("Beam")
beam.Width0, beam.Width1 = 2, 2
beam.Color = ColorSequence.new{
    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 255)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255))
}
beam.Transparency = NumberSequence.new(0)
beam.FaceCamera = true
beam.LightInfluence = 1
beam.Texture = "rbxassetid://4483345998"
beam.TextureSpeed = 2
beam.TextureLength = 1

local startAttachment = Instance.new("Attachment")
startAttachment.Name = "TrajectoryStart"
local endAttachment = Instance.new("Attachment")
endAttachment.Name = "TrajectoryEnd"

-- Radius Visualizer
local radiusPart = Instance.new("Part")
radiusPart.Anchored = true
radiusPart.CanCollide = false
radiusPart.Transparency = 0.6
radiusPart.Color = Color3.fromRGB(170, 0, 255)
radiusPart.Material = Enum.Material.ForceField
radiusPart.Shape = Enum.PartType.Cylinder
radiusPart.Size = Vector3.new(0.2, 30, 30)
radiusPart.Name = "RadiusVisualizer"
radiusPart.Parent = Workspace
radiusPart.Orientation = Vector3.new(0, 0, 90)

-- Utility & State
local timeAccumulator = 0
local lastParryTime = 0
local parryDelay = 0.3

local function getBall()
    for _, b in ipairs(ballsFolder:GetChildren()) do
        if b:IsA("BasePart") and b:IsDescendantOf(Workspace) then
            return b
        end
    end
    return nil
end

local function playEffect()
    if hitEffectsEnabled then
        local sound = Instance.new("Sound")
        sound.SoundId = "rbxassetid://" .. selectedEffectId
        sound.Volume = 3
        sound.Parent = Workspace
        sound:Play()
        game.Debris:AddItem(sound, 2)
    end
end

-- Skin Changer Data & Functions
local modelList = {}
local modelDropdown

local function findAttachmentInfo(model, character)
    for _, part in pairs(model:GetDescendants()) do
        if part:IsA("WeldConstraint") and character:FindFirstChild(part.Part1.Name) then
            return { partName = part.Part1.Name, offset = part.Part0.CFrame:ToObjectSpace(part.Part1.CFrame), useWeld = true }
        elseif part:IsA("Motor6D") and character:FindFirstChild(part.Part1.Name) then
            return { partName = part.Part1.Name, offset = part.C0, useWeld = false }
        end
    end
    if model.PrimaryPart and character:FindFirstChild("HumanoidRootPart") then
        local offset = character.HumanoidRootPart.CFrame:ToObjectSpace(model.PrimaryPart.CFrame)
        return { partName = "HumanoidRootPart", offset = offset, useWeld = true }
    end
    return nil
end

local function refreshModels()
    modelList = {}
    for _, player in pairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            for _, child in pairs(player.Character:GetChildren()) do
                if child:IsA("Model") then
                    table.insert(modelList, child)
                end
            end
        end
    end
end

local function attachModel(sourceModel)
    local localChar = LocalPlayer.Character
    if not localChar then return end
    for _, old in pairs(localChar:GetChildren()) do
        if old:IsA("Model") then old:Destroy() end
    end
    local attachInfo = findAttachmentInfo(sourceModel, sourceModel.Parent)
    if not attachInfo then warn("No valid attachment info for model: "..sourceModel.Name); return end
    local clone = sourceModel:Clone()
    clone.Parent = localChar
    if not clone.PrimaryPart then
        for _, p in ipairs(clone:GetDescendants()) do
            if p:IsA("BasePart") then
                clone.PrimaryPart = p
                break
            end
        end
    end
    local targetPart, modelPart = localChar:FindFirstChild(attachInfo.partName), clone.PrimaryPart
    if targetPart and modelPart then
        modelPart.CFrame = targetPart.CFrame * attachInfo.offset
        if attachInfo.useWeld then
            local weld = Instance.new("WeldConstraint")
            weld.Part0, weld.Part1, weld.Parent = modelPart, targetPart, modelPart
        else
            local motor = Instance.new("Motor6D")
            motor.Part0, motor.Part1, motor.C0, motor.Name, motor.Parent = targetPart, modelPart, attachInfo.offset, "AttachMotor", targetPart
        end
    end
end

local function rebuildDropdown()
    if modelDropdown.Clear then modelDropdown:Clear() end
    for _, mdl in ipairs(modelList) do
        modelDropdown:Toggle(mdl.Name, function(selected)
            if selected then attachModel(mdl) end
        end)
    end
end

-- Initialize Skin Changer UI
modelDropdown = skinSection:Dropdown("Models")
skinSection:Button("Refresh Models", function() refreshModels(); rebuildDropdown() end)
refreshModels()
rebuildDropdown()

-- Main Render Loop
RunService.RenderStepped:Connect(function(delta)
    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then return end

    local ball = getBall()
    if not ball then beam.Enabled = false; return end

    -- Beam
    if beamEnabled then
        startAttachment.Parent = ball
        endAttachment.Parent = ball
        if beam.Parent ~= ball then
            beam.Attachment0, beam.Attachment1, beam.Parent = startAttachment, endAttachment, ball
        end
        local vel, dir = ball.AssemblyLinearVelocity, ball.AssemblyLinearVelocity.Magnitude > 0 and ball.AssemblyLinearVelocity.Unit or Vector3.new(1,0,0)
        endAttachment.WorldPosition = ball.Position + dir * 150
        timeAccumulator += delta
        local pulse = math.abs(math.sin(timeAccumulator * 3)) * 0.1
        beam.Width0, beam.Width1 = 2 + pulse, 2 + pulse
        beam.Enabled = true
    else
        beam.Enabled = false
    end

    -- Radius
    local velocity = ball.AssemblyLinearVelocity
    local speed = velocity.Magnitude
    local distance = (ball.Position - root.Position).Magnitude
    local adjustedRadius = 30 + speed * 0.25 + math.clamp((30 - distance) * 0.3, -10, 20)
    radiusPart.Size = Vector3.new(0.2, adjustedRadius, adjustedRadius)
    radiusPart.Position = root.Position - Vector3.new(0, 3, 0)

    -- AutoParry
    if autoParryEnabled then
        local hasHighlight = character:FindFirstChildWhichIsA("Highlight")
        if distance <= adjustedRadius and hasHighlight then
            local now = tick()
            if now - lastParryTime >= parryDelay then
                lastParryTime = now
                VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F, false, game)
                VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, game)
                playEffect()
            end
        end
    end

    -- AutoSpam
    if autoSpamEnabled then
        spamIndicator:ChangeText("Spamming: On [Press G to spam]")
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F, false, game)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, game)
    else
        spamIndicator:ChangeText("Spamming: Off [Press G to spam]")
    end
end)
