--// Client-Sided Lock-On System

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

--==================================================
-- SETTINGS
--==================================================

local DEFAULT_FOV = 150
local MAX_FOV = 1000

local DEFAULT_DRIFT = 100
local MIN_DRIFT = 25
local MAX_DRIFT = 100

local LOCK_KEY = Enum.KeyCode.Q
local NEXT_TARGET_KEY = Enum.KeyCode.E
local DELETE_KEY = Enum.KeyCode.F2

local TARGET_PARTS = {
	"Head",
	"Neck",
	"HumanoidRootPart",
	"Torso",
}

local TARGET_PART_INDEX = 1 -- Default: Head

--==================================================
-- STATE
--==================================================

local systemEnabled = false
local locked = false

local fov = DEFAULT_FOV
local drift = DEFAULT_DRIFT
local npcTargetingEnabled = true
local currentTarget = nil
local targetQueue = {}

local gui
local mainFrame
local fovBox
local driftBox
local circle
local lockButton
local statusLabel
local targetPartButton

local character
local camera

local espObjects = {}
local npcEspObjects = {}

-- Players added here are ignored by lock-on.
local allowList = {}
local allowListOpen = false
local allowListFrame
local allowListButton
local allowListLayout

--==================================================
-- CHARACTER / CAMERA
--==================================================

local function updateCharacter(char)
	character = char
end

local function updateCamera()
	camera = workspace.CurrentCamera
end

updateCamera()

if LocalPlayer.Character then
	updateCharacter(LocalPlayer.Character)
end

LocalPlayer.CharacterAdded:Connect(updateCharacter)

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(updateCamera)

--==================================================
-- TARGET PART
--==================================================

local function getSelectedPartName()
	return TARGET_PARTS[TARGET_PART_INDEX]
end

local function getTargetPart(targetCharacter)
	if not targetCharacter then
		return nil
	end

	local partName = getSelectedPartName()

	-- "Neck" locks onto the area between Head and Torso.
	-- We return the Head part; the camera lock offsets downward
	-- to aim at the neck. If a rig has an actual "Neck" BasePart,
	-- use that directly.
	if partName == "Neck" then
		local neck = targetCharacter:FindFirstChild("Neck")
		if neck and neck:IsA("BasePart") then
			return neck
		end
		local head = targetCharacter:FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			return head
		end
		return targetCharacter:FindFirstChild("HumanoidRootPart")
	end

	local part = targetCharacter:FindFirstChild(partName)

	-- R15 characters normally use UpperTorso instead of Torso.
	if partName == "Torso" and not part then
		part = targetCharacter:FindFirstChild("UpperTorso")
	end

	if part and part:IsA("BasePart") then
		return part
	end

	-- Fallback so a missing requested body part doesn't break the system.
	local head = targetCharacter:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head
	end

	return targetCharacter:FindFirstChild("HumanoidRootPart")
end

local function getESPParts(targetCharacter)
	if not targetCharacter then
		return nil, nil
	end

	local partName = getSelectedPartName()

	if partName == "Neck" then
		local head = targetCharacter:FindFirstChild("Head")
		local torso = targetCharacter:FindFirstChild("Torso") or targetCharacter:FindFirstChild("UpperTorso")
		if head and head:IsA("BasePart") and torso and torso:IsA("BasePart") then
			return head, torso
		end
		if head and head:IsA("BasePart") then
			return head, nil
		end
		return nil, nil
	end

	local part = targetCharacter:FindFirstChild(partName)
	if partName == "Torso" and not part then
		part = targetCharacter:FindFirstChild("UpperTorso")
	end

	if part and part:IsA("BasePart") then
		return part, nil
	end

	-- Fallback to Head
	local head = targetCharacter:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head, nil
	end

	return targetCharacter:FindFirstChild("HumanoidRootPart"), nil
end

local function updateTargetPartButton()
	if targetPartButton then
		targetPartButton.Text = "TARGET: " .. getSelectedPartName()
	end
end

--==================================================
-- GUI
--==================================================

gui = Instance.new("ScreenGui")
gui.Name = "ClientLockOnGUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 2147483647
gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

mainFrame = Instance.new("Frame")
mainFrame.Name = "ControlPanel"
mainFrame.Size = UDim2.fromOffset(230, 285)
mainFrame.Position = UDim2.fromOffset(25, 250)
mainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
mainFrame.BackgroundTransparency = 0.1
mainFrame.BorderSizePixel = 0
mainFrame.ZIndex = 10
mainFrame.Parent = gui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 10)
mainCorner.Parent = mainFrame

--==================================================
-- TITLE
--==================================================

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 30)
title.BackgroundTransparency = 1
title.Text = "CLIENT LOCK-ON"
title.TextColor3 = Color3.new(1, 1, 1)
title.TextSize = 15
title.Font = Enum.Font.GothamBold
title.Parent = mainFrame

--==================================================
-- FOV
--==================================================

local fovLabel = Instance.new("TextLabel")
fovLabel.Position = UDim2.fromOffset(10, 38)
fovLabel.Size = UDim2.fromOffset(30, 25)
fovLabel.BackgroundTransparency = 1
fovLabel.Text = "FOV:"
fovLabel.TextColor3 = Color3.new(1, 1, 1)
fovLabel.TextSize = 14
fovLabel.Font = Enum.Font.Gotham
fovLabel.TextXAlignment = Enum.TextXAlignment.Left
fovLabel.Parent = mainFrame

fovBox = Instance.new("TextBox")
fovBox.Position = UDim2.fromOffset(42, 36)
fovBox.Size = UDim2.fromOffset(63, 28)
fovBox.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
fovBox.BorderSizePixel = 0
fovBox.Text = tostring(DEFAULT_FOV)
fovBox.TextColor3 = Color3.new(1, 1, 1)
fovBox.TextSize = 14
fovBox.Font = Enum.Font.Gotham
fovBox.ClearTextOnFocus = false
fovBox.Parent = mainFrame

local fovCorner = Instance.new("UICorner")
fovCorner.CornerRadius = UDim.new(0, 6)
fovCorner.Parent = fovBox

--==================================================
-- DRIFT
-- 100 = instant snap, lower = gradual drift
--==================================================

local driftLabel = Instance.new("TextLabel")
driftLabel.Position = UDim2.fromOffset(110, 38)
driftLabel.Size = UDim2.fromOffset(35, 25)
driftLabel.BackgroundTransparency = 1
driftLabel.Text = "Drift:"
driftLabel.TextColor3 = Color3.new(1, 1, 1)
driftLabel.TextSize = 14
driftLabel.Font = Enum.Font.Gotham
driftLabel.TextXAlignment = Enum.TextXAlignment.Left
driftLabel.Parent = mainFrame

driftBox = Instance.new("TextBox")
driftBox.Position = UDim2.fromOffset(145, 36)
driftBox.Size = UDim2.fromOffset(65, 28)
driftBox.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
driftBox.BorderSizePixel = 0
driftBox.Text = tostring(DEFAULT_DRIFT)
driftBox.TextColor3 = Color3.new(1, 1, 1)
driftBox.TextSize = 14
driftBox.Font = Enum.Font.Gotham
driftBox.ClearTextOnFocus = false
driftBox.Parent = mainFrame

local driftCorner = Instance.new("UICorner")
driftCorner.CornerRadius = UDim.new(0, 6)
driftCorner.Parent = driftBox

--==================================================
-- LOCK STATUS BUTTON
-- Non-clickable: Q controls the system.
--==================================================

lockButton = Instance.new("TextButton")
lockButton.Position = UDim2.fromOffset(10, 70)
lockButton.Size = UDim2.fromOffset(200, 32)
lockButton.BackgroundColor3 = Color3.fromRGB(180, 45, 45)
lockButton.BorderSizePixel = 0
lockButton.Text = "LOCK-ON: DISABLED"
lockButton.TextColor3 = Color3.new(1, 1, 1)
lockButton.TextSize = 13
lockButton.Font = Enum.Font.GothamBold
lockButton.AutoButtonColor = false
lockButton.Active = false
lockButton.Selectable = false
lockButton.Parent = mainFrame

local buttonCorner = Instance.new("UICorner")
buttonCorner.CornerRadius = UDim.new(0, 7)
buttonCorner.Parent = lockButton

--==================================================
-- TARGET PART BUTTON
--==================================================

targetPartButton = Instance.new("TextButton")
targetPartButton.Position = UDim2.fromOffset(10, 107)
targetPartButton.Size = UDim2.fromOffset(200, 30)
targetPartButton.BackgroundColor3 = Color3.fromRGB(55, 55, 55)
targetPartButton.BorderSizePixel = 0
targetPartButton.TextColor3 = Color3.new(1, 1, 1)
targetPartButton.TextSize = 12
targetPartButton.Font = Enum.Font.GothamBold
targetPartButton.AutoButtonColor = true
targetPartButton.Parent = mainFrame

local targetPartCorner = Instance.new("UICorner")
targetPartCorner.CornerRadius = UDim.new(0, 7)
targetPartCorner.Parent = targetPartButton

--==================================================
-- NPC TOGGLE
-- Enables or disables NPC targeting and ESP.
--==================================================

local npcToggleButton = Instance.new("TextButton")
npcToggleButton.Position = UDim2.fromOffset(10, 140)
npcToggleButton.Size = UDim2.fromOffset(200, 30)
npcToggleButton.BackgroundColor3 = Color3.fromRGB(55, 130, 75)
npcToggleButton.BorderSizePixel = 0
npcToggleButton.Text = "NPCs: ON"
npcToggleButton.TextColor3 = Color3.new(1, 1, 1)
npcToggleButton.TextSize = 12
npcToggleButton.Font = Enum.Font.GothamBold
npcToggleButton.AutoButtonColor = true
npcToggleButton.Parent = mainFrame

local npcToggleCorner = Instance.new("UICorner")
npcToggleCorner.CornerRadius = UDim.new(0, 7)
npcToggleCorner.Parent = npcToggleButton

--==================================================
-- ALLOW LIST
-- Click a player's name to toggle whether they can
-- ever be locked onto.
--==================================================

allowListButton = Instance.new("TextButton")
allowListButton.Position = UDim2.fromOffset(10, 175)
allowListButton.Size = UDim2.fromOffset(200, 30)
allowListButton.BackgroundColor3 = Color3.fromRGB(55, 55, 55)
allowListButton.BorderSizePixel = 0
allowListButton.Text = "ALLOW LIST ▼"
allowListButton.TextColor3 = Color3.new(1, 1, 1)
allowListButton.TextSize = 12
allowListButton.Font = Enum.Font.GothamBold
allowListButton.AutoButtonColor = true
allowListButton.Parent = mainFrame

local allowListCorner = Instance.new("UICorner")
allowListCorner.CornerRadius = UDim.new(0, 7)
allowListCorner.Parent = allowListButton

allowListFrame = Instance.new("ScrollingFrame")
allowListFrame.Name = "AllowList"
allowListFrame.Position = UDim2.fromOffset(10, 210)
allowListFrame.Size = UDim2.fromOffset(200, 100)
allowListFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
allowListFrame.BorderSizePixel = 0
allowListFrame.ScrollBarThickness = 4
allowListFrame.Visible = false
allowListFrame.ZIndex = 100
allowListFrame.CanvasSize = UDim2.fromOffset(0, 0)
allowListFrame.Parent = mainFrame

local allowListFrameCorner = Instance.new("UICorner")
allowListFrameCorner.CornerRadius = UDim.new(0, 6)
allowListFrameCorner.Parent = allowListFrame

allowListLayout = Instance.new("UIListLayout")
allowListLayout.Padding = UDim.new(0, 2)
allowListLayout.Parent = allowListFrame

allowListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	if allowListFrame then
		allowListFrame.CanvasSize = UDim2.fromOffset(
			0,
			allowListLayout.AbsoluteContentSize.Y + 4
		)
	end
end)

--==================================================
-- STATUS
--==================================================

statusLabel = Instance.new("TextLabel")
statusLabel.Position = UDim2.fromOffset(10, 245)
statusLabel.Size = UDim2.fromOffset(200, 20)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "Status: Disabled"
statusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
statusLabel.TextSize = 11
statusLabel.Font = Enum.Font.Gotham
statusLabel.Parent = mainFrame

--==================================================
-- KEYBINDS INFO
--==================================================

local keybindsLabel = Instance.new("TextLabel")
keybindsLabel.Position = UDim2.fromOffset(10, 265)
keybindsLabel.Size = UDim2.fromOffset(200, 15)
keybindsLabel.BackgroundTransparency = 1
keybindsLabel.Text = "Q: Lock-On  E: Next  F2: Delete"
keybindsLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
keybindsLabel.TextSize = 10
keybindsLabel.Font = Enum.Font.Gotham
keybindsLabel.TextXAlignment = Enum.TextXAlignment.Left
keybindsLabel.TextYAlignment = Enum.TextYAlignment.Top
keybindsLabel.Parent = mainFrame

updateTargetPartButton()

--==================================================
-- DRAGGING
--==================================================

local dragging = false
local dragStart
local startPosition

title.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		dragging = true
		dragStart = input.Position
		startPosition = mainFrame.Position

		local connection
		connection = input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false

				if connection then
					connection:Disconnect()
				end
			end
		end)
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
		local delta = input.Position - dragStart

		mainFrame.Position = UDim2.new(
			startPosition.X.Scale,
			startPosition.X.Offset + delta.X,
			startPosition.Y.Scale,
			startPosition.Y.Offset + delta.Y
		)
	end
end)

--==================================================
-- FOV CIRCLE
--==================================================

circle = Instance.new("Frame")
circle.Name = "CursorFOV"
circle.AnchorPoint = Vector2.new(0.5, 0.5)
circle.Size = UDim2.fromOffset(fov * 2, fov * 2)
circle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
circle.BackgroundTransparency = 0.75
circle.BorderSizePixel = 0
circle.Active = false
circle.Selectable = false
circle.ZIndex = 1
circle.Parent = gui

local circleCorner = Instance.new("UICorner")
circleCorner.CornerRadius = UDim.new(1, 0)
circleCorner.Parent = circle

--==================================================
-- UPDATE UI
--==================================================

local function updateUI()
	if not lockButton or not lockButton.Parent then
		return
	end

	if systemEnabled then
		lockButton.BackgroundColor3 = Color3.fromRGB(45, 180, 75)
		lockButton.Text = "LOCK-ON: ENABLED"

		statusLabel.Text = "Status: Trigger Active"
		statusLabel.TextColor3 = Color3.fromRGB(100, 255, 120)
	else
		lockButton.BackgroundColor3 = Color3.fromRGB(180, 45, 45)
		lockButton.Text = "LOCK-ON: DISABLED"

		statusLabel.Text = "Status: Disabled"
		statusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
	end
end

--==================================================
-- FOV INPUT
--==================================================

local function updateFOV()
	if not fovBox or not fovBox.Parent then
		return
	end

	local number = tonumber(fovBox.Text)

	if not number then
		fovBox.Text = tostring(fov)
		return
	end

	number = math.clamp(math.floor(number), 1, MAX_FOV)

	fov = number
	fovBox.Text = tostring(fov)

	if circle then
		circle.Size = UDim2.fromOffset(fov * 2, fov * 2)
	end
end

fovBox.FocusLost:Connect(updateFOV)

--==================================================
-- DRIFT INPUT
--==================================================

local function updateDrift()
	if not driftBox or not driftBox.Parent then
		return
	end

	local number = tonumber(driftBox.Text)

	if not number then
		driftBox.Text = tostring(drift)
		return
	end

	number = math.clamp(math.floor(number), MIN_DRIFT, MAX_DRIFT)

	drift = number
	driftBox.Text = tostring(drift)
end

driftBox.FocusLost:Connect(updateDrift)

--==================================================
-- ALLOW LIST FUNCTIONS
--==================================================

local function isAllowed(player)
	return player and allowList[player] == true
end

local function updateAllowListButton()
	if not allowListButton then
		return
	end

	local count = 0
	for player, enabled in pairs(allowList) do
		if enabled and player and player.Parent == Players then
			count += 1
		end
	end

	allowListButton.Text = "ALLOW LIST (" .. count .. ") " .. (allowListOpen and "▲" or "▼")
end

local function refreshAllowList()
	if not allowListFrame then
		return
	end

	for _, child in ipairs(allowListFrame:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then
			local button = Instance.new("TextButton")
			button.Size = UDim2.new(1, -6, 0, 26)
			button.BackgroundColor3 = isAllowed(player)
				and Color3.fromRGB(65, 130, 75)
				or Color3.fromRGB(50, 50, 50)
			button.BorderSizePixel = 0
			button.Text = (isAllowed(player) and "✓ " or "  ") .. player.DisplayName
				.. "  @" .. player.Name
			button.TextColor3 = Color3.new(1, 1, 1)
			button.TextSize = 10
			button.Font = Enum.Font.Gotham
			button.TextXAlignment = Enum.TextXAlignment.Left
			button.Parent = allowListFrame

			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 4)
			corner.Parent = button

			button.MouseButton1Click:Connect(function()
				allowList[player] = not isAllowed(player)

				-- If this player is currently locked, immediately unlock
				-- and move to the next queued enemy.
				if currentTarget and currentTarget.Player == player and isAllowed(player) then
					unlock()
					if systemEnabled then
						lockNextQueuedTarget()
						if not locked then
							findFirstTarget()
						end
					end
				end

				refreshAllowList()
				updateAllowListButton()
			end)
		end
	end

	updateAllowListButton()
end

allowListButton.MouseButton1Click:Connect(function()
	allowListOpen = not allowListOpen
	allowListFrame.Visible = allowListOpen

	if allowListOpen then
		refreshAllowList()
	end
end)

--==================================================
-- ALLOW LIST AUTO-REFRESH (every 1 second)
-- Keeps the list updated as players join/leave.
--==================================================

task.spawn(function()
	while true do
		task.wait(1)
		if allowListOpen and allowListFrame and allowListFrame.Parent then
			refreshAllowList()
		end
	end
end)

--==================================================
-- TARGET PART CYCLE
--==================================================

targetPartButton.MouseButton1Click:Connect(function()
	TARGET_PART_INDEX += 1

	if TARGET_PART_INDEX > #TARGET_PARTS then
		TARGET_PART_INDEX = 1
	end

	updateTargetPartButton()

	-- Refresh ESP immediately.
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then
			updateESP(player)
		end
	end

	-- Refresh NPC ESP immediately.
	for model in pairs(npcEspObjects) do
		if model and model.Parent then
			updateNPCEsp(model)
		end
	end

	-- If already locked, immediately switch the lock point.
	if currentTarget then
		if currentTarget.IsNPC and currentTarget.Character then
			currentTarget.Part = getTargetPart(currentTarget.Character)
		elseif currentTarget.Player then
			currentTarget.Part = getTargetPart(currentTarget.Player.Character)
		end
	end
end)

--==================================================
-- NPC TOGGLE HANDLER
--==================================================

npcToggleButton.MouseButton1Click:Connect(function()
	npcTargetingEnabled = not npcTargetingEnabled

	if npcTargetingEnabled then
		npcToggleButton.Text = "NPCs: ON"
		npcToggleButton.BackgroundColor3 = Color3.fromRGB(55, 130, 75)
	else
		npcToggleButton.Text = "NPCs: OFF"
		npcToggleButton.BackgroundColor3 = Color3.fromRGB(130, 45, 45)

		-- Remove all NPC ESP immediately.
		for model in pairs(npcEspObjects) do
			removeNPCEsp(model)
		end

		-- If currently locked on an NPC, unlock and find a new target.
		if currentTarget and currentTarget.IsNPC then
			unlock()
			if systemEnabled then
				findFirstTarget()
			end
		end

		-- Rebuild the queue without NPCs.
		targetQueue = {}
		if systemEnabled then
			rebuildQueue()
		end
	end
end)

--==================================================
-- TARGET SCREEN POSITION
--==================================================

local function getTargetScreenPosition(part)
	if not part or not camera then
		return nil
	end

	local position, visible = camera:WorldToViewportPoint(part.Position)

	if not visible or position.Z <= 0 then
		return nil
	end

	return Vector2.new(position.X, position.Y)
end

--==================================================
-- FOV CHECK
--==================================================

local function isInsideFOV(part)
	local screenPosition = getTargetScreenPosition(part)

	if not screenPosition then
		return false
	end

	local mousePosition = UserInputService:GetMouseLocation()

	return (screenPosition - mousePosition).Magnitude <= fov
end

--==================================================
-- WALL CHECK
--==================================================

local function hasLineOfSight(part)
	if not character or not part or not camera then
		return false
	end

	local origin = camera.CFrame.Position
	local direction = part.Position - origin

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {
		character
	}
	params.IgnoreWater = true

	local result = workspace:Raycast(
		origin,
		direction,
		params
	)

	if not result then
		return true
	end

	return result.Instance:IsDescendantOf(part.Parent)
end

--==================================================
-- TEAM CHECK
--==================================================

local function isEnemy(player)
	if not player or player == LocalPlayer then
		return false
	end

	-- Allow-listed players can never be targets.
	if isAllowed(player) then
		return false
	end

	-- Players on the same team can never be targets.
	if LocalPlayer.Team ~= nil and player.Team == LocalPlayer.Team then
		return false
	end

	return true
end

--==================================================
-- GET VALID TARGET
--==================================================

local function getValidTargetData(player, requireFOV)
	if not isEnemy(player) then
		return nil
	end

	local targetCharacter = player.Character

	if not targetCharacter then
		return nil
	end

	local humanoid = targetCharacter:FindFirstChildOfClass("Humanoid")
	local part = getTargetPart(targetCharacter)

	if not humanoid or humanoid.Health <= 0 or not part then
		return nil
	end

	if requireFOV and not isInsideFOV(part) then
		return nil
	end

	if not hasLineOfSight(part) then
		return nil
	end

	local screenPosition = getTargetScreenPosition(part)

	if not screenPosition then
		return nil
	end

	local mousePosition = UserInputService:GetMouseLocation()
	local distance = (screenPosition - mousePosition).Magnitude

	return {
		Player = player,
		Part = part,
		Distance = distance,
	}
end

--==================================================
-- GET VALID NPC TARGET DATA
--==================================================

-- Forward-declared so it can be used before its full definition below.
local isNPC

local function getValidNPCTargetData(npcModel, requireFOV)
	if not isNPC(npcModel) then
		return nil
	end

	local humanoid = npcModel:FindFirstChildOfClass("Humanoid")
	local part = getTargetPart(npcModel)

	-- If there's a Humanoid, check health. If no Humanoid (rig), always valid.
	if humanoid and humanoid.Health <= 0 then
		return nil
	end

	if not part then
		return nil
	end

	if requireFOV and not isInsideFOV(part) then
		return nil
	end

	if not hasLineOfSight(part) then
		return nil
	end

	local screenPosition = getTargetScreenPosition(part)

	if not screenPosition then
		return nil
	end

	local mousePosition = UserInputService:GetMouseLocation()
	local distance = (screenPosition - mousePosition).Magnitude

	return {
		Player = nil,
		Character = npcModel,
		Part = part,
		Distance = distance,
		IsNPC = true,
	}
end

--==================================================
-- BUILD QUEUE
-- First person in the FOV gets priority.
-- Everyone else currently inside the FOV follows.
--==================================================

local function getTargetsInFOV()
	local targets = {}

	for _, player in ipairs(Players:GetPlayers()) do
		local target = getValidTargetData(player, true)

		if target then
			table.insert(targets, target)
		end
	end

	-- Also scan for NPCs in workspace (if NPC targeting is enabled).
	if npcTargetingEnabled then
		for _, descendant in ipairs(workspace:GetDescendants()) do
			if isNPC(descendant) then
				local target = getValidNPCTargetData(descendant, true)

				if target then
					table.insert(targets, target)
				end
			end
		end
	end

	table.sort(targets, function(a, b)
		return a.Distance < b.Distance
	end)

	return targets
end

local function rebuildQueue()
	targetQueue = getTargetsInFOV()
end

--==================================================
-- QUEUE HELPERS
--==================================================

local function removePlayerFromQueue(player)
	for index = #targetQueue, 1, -1 do
		if targetQueue[index].Player == player then
			table.remove(targetQueue, index)
		end
	end
end

local function removeNPCFromQueue(npcModel)
	for index = #targetQueue, 1, -1 do
		if targetQueue[index].Character == npcModel then
			table.remove(targetQueue, index)
		end
	end
end

local function getNextQueuedTarget()
	while #targetQueue > 0 do
		local target = table.remove(targetQueue, 1)

		if target.IsNPC then
			if target.Character and getValidNPCTargetData(target.Character, false) then
				target.Part = getTargetPart(target.Character)
				return target
			end
		elseif target and getValidTargetData(target.Player, false) then
			target.Part = getTargetPart(target.Player.Character)
			return target
		end
	end

	return nil
end

--==================================================
-- ESP
-- Username + health above head, visible through walls.
-- Dead players have no ESP.
--==================================================

local function getESPColor(player)
	if isAllowed(player) then
		return Color3.fromRGB(60, 140, 255)
	end
	if LocalPlayer.Team ~= nil and player.Team == LocalPlayer.Team then
		return Color3.fromRGB(60, 140, 255)
	end
	return Color3.fromRGB(255, 70, 70)
end

local function createESP(player)
	if player == LocalPlayer or espObjects[player] then return end

	local folder = Instance.new("Folder")
	folder.Name = "LockOnESP"
	folder.Parent = gui

	local highlight = Instance.new("Highlight")
	highlight.Name = "Highlight"
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillTransparency = 0.45
	highlight.OutlineTransparency = 0
	highlight.Enabled = false
	highlight.Parent = folder

	local highlight2 = Instance.new("Highlight")
	highlight2.Name = "Highlight2"
	highlight2.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight2.FillTransparency = 0.45
	highlight2.OutlineTransparency = 0
	highlight2.Enabled = false
	highlight2.Parent = folder

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PlayerInfo"
	billboard.Size = UDim2.fromOffset(240, 55)
	billboard.StudsOffset = Vector3.new(0, 3.25, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Enabled = false
	billboard.Parent = folder

	local username = Instance.new("TextLabel")
	username.Name = "Username"
	username.Size = UDim2.new(1, 0, 0, 27)
	username.BackgroundTransparency = 1
	username.TextColor3 = Color3.new(1, 1, 1)
	username.TextStrokeTransparency = 0
	username.TextStrokeColor3 = Color3.new(0, 0, 0)
	username.TextSize = 16
	username.Font = Enum.Font.GothamBold
	username.Parent = billboard

	local health = Instance.new("TextLabel")
	health.Name = "Health"
	health.Position = UDim2.fromOffset(0, 25)
	health.Size = UDim2.new(1, 0, 0, 25)
	health.BackgroundTransparency = 1
	health.TextColor3 = Color3.fromRGB(100, 255, 100)
	health.TextStrokeTransparency = 0
	health.TextStrokeColor3 = Color3.new(0, 0, 0)
	health.TextSize = 13
	health.Font = Enum.Font.GothamBold
	health.Parent = billboard

	espObjects[player] = {
		Folder = folder,
		Highlight = highlight,
		Highlight2 = highlight2,
		Billboard = billboard,
		Username = username,
		Health = health,
	}
end

local function updateESP(player)
	if player == LocalPlayer then return end
	createESP(player)

	local esp = espObjects[player]
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local head = char and char:FindFirstChild("Head")
	local part1, part2 = getESPParts(char)

	if not esp or not char or not humanoid or humanoid.Health <= 0 or not part1 then
		if esp then
			esp.Highlight.Enabled = false
			esp.Highlight.Adornee = nil
			if esp.Highlight2 then
				esp.Highlight2.Enabled = false
				esp.Highlight2.Adornee = nil
			end
			esp.Billboard.Enabled = false
			esp.Billboard.Adornee = nil
		end
		return
	end

	local color = getESPColor(player)
	local hp = math.max(0, humanoid.Health)
	local maxHp = math.max(1, humanoid.MaxHealth)

	esp.Highlight.Adornee = part1
	esp.Highlight.FillColor = color
	esp.Highlight.OutlineColor = color
	esp.Highlight.Enabled = true

	if esp.Highlight2 then
		if part2 then
			esp.Highlight2.Adornee = part2
			esp.Highlight2.FillColor = color
			esp.Highlight2.OutlineColor = color
			esp.Highlight2.Enabled = true
		else
			esp.Highlight2.Enabled = false
			esp.Highlight2.Adornee = nil
		end
	end

	esp.Billboard.Adornee = head
	esp.Billboard.Enabled = true
	esp.Username.Text = player.DisplayName .. "  @" .. player.Name
	esp.Health.Text = string.format("HP: %d / %d", math.floor(hp + 0.5), math.floor(maxHp + 0.5))
	esp.Health.TextColor3 = Color3.fromHSV(math.clamp(hp / maxHp, 0, 1) * 0.33, 0.85, 1)
end

local function removeESP(player)
	local esp = espObjects[player]
	if esp then
		if esp.Folder then esp.Folder:Destroy() end
		espObjects[player] = nil
	end
end

for _, player in ipairs(Players:GetPlayers()) do
	if player ~= LocalPlayer then createESP(player) end
end

Players.PlayerAdded:Connect(function(player)
	createESP(player)
	if allowListOpen then refreshAllowList() end
end)

Players.PlayerRemoving:Connect(function(player)
	removeESP(player)
	allowList[player] = nil
	if allowListOpen then refreshAllowList() end
	if currentTarget and currentTarget.Player == player then
		currentTarget = nil
		locked = false
	end
	removePlayerFromQueue(player)
end)

--==================================================
-- NPC ESP & DETECTION
-- NPCs are models with a Humanoid in workspace that
-- are NOT player characters.  ESP is purple.
--==================================================

isNPC = function(model)
	if not model or not model:IsA("Model") then return false end
	-- Detect anything with a root part, torso, and head (no Humanoid required)
	if not model:FindFirstChild("HumanoidRootPart") then return false end
	if not (model:FindFirstChild("Torso") or model:FindFirstChild("UpperTorso")) then return false end
	if not model:FindFirstChild("Head") then return false end
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character == model then
			return false
		end
	end
	return true
end

local function createNPCEsp(npcModel)
	if npcEspObjects[npcModel] then return end

	local folder = Instance.new("Folder")
	folder.Name = "LockOnNPCEsp"
	folder.Parent = gui

	local highlight = Instance.new("Highlight")
	highlight.Name = "Highlight"
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillTransparency = 0.45
	highlight.OutlineTransparency = 0
	highlight.FillColor = Color3.fromRGB(170, 0, 255)
	highlight.OutlineColor = Color3.fromRGB(170, 0, 255)
	highlight.Enabled = false
	highlight.Parent = folder

	local highlight2 = Instance.new("Highlight")
	highlight2.Name = "Highlight2"
	highlight2.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight2.FillTransparency = 0.45
	highlight2.OutlineTransparency = 0
	highlight2.FillColor = Color3.fromRGB(170, 0, 255)
	highlight2.OutlineColor = Color3.fromRGB(170, 0, 255)
	highlight2.Enabled = false
	highlight2.Parent = folder

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "NPCInfo"
	billboard.Size = UDim2.fromOffset(240, 55)
	billboard.StudsOffset = Vector3.new(0, 3.25, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Enabled = false
	billboard.Parent = folder

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.Size = UDim2.new(1, 0, 0, 27)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextColor3 = Color3.fromRGB(200, 100, 255)
	nameLabel.TextStrokeTransparency = 0
	nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	nameLabel.TextSize = 16
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Parent = billboard

	local healthLabel = Instance.new("TextLabel")
	healthLabel.Name = "Health"
	healthLabel.Position = UDim2.fromOffset(0, 25)
	healthLabel.Size = UDim2.new(1, 0, 0, 25)
	healthLabel.BackgroundTransparency = 1
	healthLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
	healthLabel.TextStrokeTransparency = 0
	healthLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	healthLabel.TextSize = 13
	healthLabel.Font = Enum.Font.GothamBold
	healthLabel.Visible = false
	healthLabel.Parent = billboard

	npcEspObjects[npcModel] = {
		Folder = folder,
		Highlight = highlight,
		Highlight2 = highlight2,
		Billboard = billboard,
		NameLabel = nameLabel,
		HealthLabel = healthLabel,
	}
end

local function updateNPCEsp(npcModel)
	createNPCEsp(npcModel)

	local esp = npcEspObjects[npcModel]
	local head = npcModel:FindFirstChild("Head")
	local humanoid = npcModel:FindFirstChildOfClass("Humanoid")
	local part1, part2 = getESPParts(npcModel)

	-- If there's a humanoid and it's dead, hide ESP.
	-- If there's no humanoid, ESP stays visible (rigs don't have health).
	if humanoid and humanoid.Health <= 0 then
		if esp then
			esp.Highlight.Enabled = false
			esp.Highlight.Adornee = nil
			if esp.Highlight2 then
				esp.Highlight2.Enabled = false
				esp.Highlight2.Adornee = nil
			end
			esp.Billboard.Enabled = false
			esp.Billboard.Adornee = nil
		end
		return
	end

	if not part1 then
		if esp then
			esp.Highlight.Enabled = false
			esp.Highlight.Adornee = nil
			if esp.Highlight2 then
				esp.Highlight2.Enabled = false
				esp.Highlight2.Adornee = nil
			end
			esp.Billboard.Enabled = false
			esp.Billboard.Adornee = nil
		end
		return
	end

	esp.Highlight.Adornee = part1
	esp.Highlight.Enabled = true

	if esp.Highlight2 then
		if part2 then
			esp.Highlight2.Adornee = part2
			esp.Highlight2.Enabled = true
		else
			esp.Highlight2.Enabled = false
			esp.Highlight2.Adornee = nil
		end
	end

	if head then
		esp.Billboard.Adornee = head
		esp.Billboard.Enabled = true
	else
		esp.Billboard.Enabled = false
		esp.Billboard.Adornee = nil
	end
	esp.NameLabel.Text = npcModel.Name

	-- Show health info if the NPC has a Humanoid.
	if humanoid and esp.HealthLabel then
		local hp = math.max(0, humanoid.Health)
		local maxHp = math.max(1, humanoid.MaxHealth)
		esp.HealthLabel.Text = string.format("HP: %d / %d", math.floor(hp + 0.5), math.floor(maxHp + 0.5))
		esp.HealthLabel.TextColor3 = Color3.fromHSV(math.clamp(hp / maxHp, 0, 1) * 0.33, 0.85, 1)
		esp.HealthLabel.Visible = true
	elseif esp.HealthLabel then
		esp.HealthLabel.Visible = false
	end
end

local function removeNPCEsp(npcModel)
	local esp = npcEspObjects[npcModel]
	if esp then
		if esp.Folder then esp.Folder:Destroy() end
		npcEspObjects[npcModel] = nil
	end
end

local function refreshNPCs()
	-- Remove ESP for destroyed NPCs or when NPC targeting is disabled.
	for model in pairs(npcEspObjects) do
		if not model or not model.Parent or not isNPC(model) or not npcTargetingEnabled then
			removeNPCEsp(model)
		end
	end

	-- Add/update ESP for current NPCs (only if NPC targeting is enabled).
	if npcTargetingEnabled then
		for _, descendant in ipairs(workspace:GetDescendants()) do
			if isNPC(descendant) then
				updateNPCEsp(descendant)
			end
		end
	end
end

-- Periodic NPC scan (every 0.5 seconds).
task.spawn(function()
	while true do
		task.wait(0.5)
		if gui then
			refreshNPCs()
		end
	end
end)

-- Clean up ESP when an NPC is destroyed.
workspace.DescendantRemoving:Connect(function(descendant)
	if isNPC(descendant) then
		removeNPCEsp(descendant)
		if currentTarget and currentTarget.IsNPC and currentTarget.Character == descendant then
			currentTarget = nil
			locked = false
		end
		removeNPCFromQueue(descendant)
	end
end)

--==================================================
-- VALIDATE CURRENT TARGET
--==================================================

local function isTargetValid()
	if not currentTarget then
		return false
	end

	if currentTarget.IsNPC then
		local npcModel = currentTarget.Character
		if not npcModel or not npcModel.Parent then
			return false
		end

		local humanoid = npcModel:FindFirstChildOfClass("Humanoid")
		local part = getTargetPart(npcModel)

		-- If there's a Humanoid, check health. If no Humanoid (rig), always valid.
		if humanoid and humanoid.Health <= 0 then
			return false
		end

		if not part then
			return false
		end

		if not hasLineOfSight(part) then
			return false
		end

		currentTarget.Part = part
		return true
	end

	if not currentTarget.Player then
		return false
	end

	local player = currentTarget.Player

	if not isEnemy(player) then
		return false
	end

	local targetCharacter = player.Character

	if not targetCharacter then
		return false
	end

	local humanoid = targetCharacter:FindFirstChildOfClass("Humanoid")
	local part = getTargetPart(targetCharacter)

	if not humanoid or humanoid.Health <= 0 or not part then
		return false
	end

	if not hasLineOfSight(part) then
		return false
	end

	currentTarget.Part = part

	return true
end

--==================================================
-- LOCK / UNLOCK
--==================================================

local function lockTarget(target)
	if not target then
		return
	end

	if target.IsNPC then
		local npcModel = target.Character
		if not npcModel or not npcModel.Parent then
			return
		end

		local humanoid = npcModel:FindFirstChildOfClass("Humanoid")
		-- If there's a Humanoid, check health. If no Humanoid (rig), always valid.
		if humanoid and humanoid.Health <= 0 then
			return
		end

		local part = getTargetPart(npcModel)
		if not part then
			return
		end

		currentTarget = {
			Player = nil,
			Character = npcModel,
			Part = part,
			Distance = target.Distance,
			IsNPC = true,
		}

		locked = true
		return
	end

	if not target.Player then
		return
	end

	if not isEnemy(target.Player) then
		return
	end

	local targetCharacter = target.Player.Character
	local humanoid = targetCharacter and targetCharacter:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local part = getTargetPart(targetCharacter)

	if not part then
		return
	end

	currentTarget = {
		Player = target.Player,
		Part = part,
		Distance = target.Distance,
	}

	locked = true
end

local function unlock()
	currentTarget = nil
	locked = false
end

--==================================================
-- AUTOMATIC TARGET ACQUISITION
--==================================================

local function findFirstTarget()
	rebuildQueue()

	if #targetQueue > 0 then
		local firstTarget = table.remove(targetQueue, 1)
		lockTarget(firstTarget)
	end
end

--==================================================
-- MOVE TO NEXT QUEUED TARGET
--==================================================

local function lockNextQueuedTarget()
	local nextTarget = getNextQueuedTarget()

	if nextTarget then
		lockTarget(nextTarget)
		return true
	end

	unlock()
	return false
end

--==================================================
-- TOGGLE SYSTEM
-- Q = trigger on/off
-- When enabled, it automatically locks the first
-- enemy inside the FOV circle.
--==================================================

local function toggleSystem()
	systemEnabled = not systemEnabled

	if not systemEnabled then
		unlock()
		targetQueue = {}
	else
		findFirstTarget()
	end

	updateUI()
end

--==================================================
-- NEXT TARGET
-- E = manually skip to the next queued target.
-- If the queue is empty, rebuild it from the FOV.
--==================================================

local function nextTarget()
	if not systemEnabled then
		return
	end

	if #targetQueue == 0 then
		rebuildQueue()
	end

	if not lockNextQueuedTarget() then
		findFirstTarget()
	end
end

--==================================================
-- KEYBOARD
-- No MouseButton1 game-input handling is used here.
-- Left-click remains normal Roblox mouse input.
--==================================================

UserInputService.InputBegan:Connect(function(input, processed)
	if input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end

	-- Lock-on toggle (Q) works even if the game processed the input.
	if input.KeyCode == LOCK_KEY then
		toggleSystem()
		return
	end

	-- Remaining keys respect the processed flag.
	if processed then
		return
	end

	if input.KeyCode == NEXT_TARGET_KEY then
		nextTarget()
		return
	end

	if input.KeyCode == DELETE_KEY then
		systemEnabled = false
		unlock()
		targetQueue = {}

		if gui then
			gui:Destroy()
			gui = nil
		end

		allowList = {}
		allowListOpen = false

		for player, esp in pairs(espObjects) do
			if esp and esp.Folder then
				esp.Folder:Destroy()
			end
			espObjects[player] = nil
		end

		for model, esp in pairs(npcEspObjects) do
			if esp and esp.Folder then
				esp.Folder:Destroy()
			end
			npcEspObjects[model] = nil
		end

		circle = nil
		mainFrame = nil
		fovBox = nil
		driftBox = nil
		lockButton = nil
		targetPartButton = nil
		statusLabel = nil

		return
	end
end)

--==================================================
-- CAMERA LOCK
-- Uses the selected body part.
-- CameraType is NOT changed, so normal mouse input
-- is preserved when the system is disabled/unlocked.
--==================================================

local function updateCamera()
	if not systemEnabled or not locked or not currentTarget then
		return
	end

	if not isTargetValid() then
		-- The current target died or disappeared.
		-- Immediately snap to the next queued enemy.
		if not lockNextQueuedTarget() then
			-- Nothing remains. Look for a fresh enemy in FOV.
			findFirstTarget()
		end

		return
	end

	if not camera then
		updateCamera()
		return
	end

	local part = currentTarget.Part

	if not part then
		return
	end

	local cameraPosition = camera.CFrame.Position
	local targetPosition = part.Position

	-- When "Neck" is selected, offset the look position downward
	-- to target the neck area (between Head and Torso).
	if getSelectedPartName() == "Neck" then
		targetPosition = targetPosition - Vector3.new(0, 0.5, 0)
	end

	-- Preserve the camera's position and only change its
	-- look direction.
	local targetCFrame = CFrame.lookAt(cameraPosition, targetPosition)

	if drift >= 100 then
		-- Instant snap onto the opponent.
		camera.CFrame = targetCFrame
	else
		-- Gradually drift toward the target at the listed speed.
		-- Lower drift values produce slower camera movement.
		local driftFactor = drift / 200
		camera.CFrame = camera.CFrame:Lerp(targetCFrame, driftFactor)
	end
end

--==================================================
-- MAIN LOOP
--==================================================

RunService:BindToRenderStep(
	"ClientLockOnUpdate",
	Enum.RenderPriority.Camera.Value + 1,
	function()
		if not gui then
			return
		end

		-- Move circle to cursor.
		if circle then
			local mousePosition = UserInputService:GetMouseLocation()

			circle.Position = UDim2.fromOffset(
				mousePosition.X,
				mousePosition.Y
			)
		end

		-- Keep ESP updated.
		for _, player in ipairs(Players:GetPlayers()) do
			if player ~= LocalPlayer then
				updateESP(player)
			end
		end

		-- Keep NPC ESP updated.
		for model in pairs(npcEspObjects) do
			if model and model.Parent then
				updateNPCEsp(model)
			else
				removeNPCEsp(model)
			end
		end

		-- If the current target is dead, immediately skip to the
		-- next alive target BEFORE updating the camera, so the
		-- camera never points at a corpse.
		if systemEnabled and locked and currentTarget then
			local isDead = false

			if currentTarget.IsNPC then
				local npcModel = currentTarget.Character
				isDead = not npcModel or not npcModel.Parent
				if not isDead then
					local humanoid = npcModel:FindFirstChildOfClass("Humanoid")
					isDead = humanoid ~= nil and humanoid.Health <= 0
				end
			elseif currentTarget.Player then
				local targetChar = currentTarget.Player.Character
				isDead = not targetChar
				if not isDead then
					local humanoid = targetChar:FindFirstChildOfClass("Humanoid")
					isDead = humanoid == nil or humanoid.Health <= 0
				end
			else
				isDead = true
			end

			if isDead then
				if not lockNextQueuedTarget() then
					findFirstTarget()
				end
			end
		end

		-- Trigger behavior:
		-- If enabled and there is no target, automatically
		-- select the closest enemy inside the circle.
		if systemEnabled and not locked then
			findFirstTarget()
		end

		updateCamera()
	end
)

--==================================================
-- INITIAL UI STATE
--==================================================

updateTargetPartButton()
updateAllowListButton()
updateUI()