--// Instant Proximity Prompts + Auto-Interact
-- 1. Makes every ProximityPrompt in the game instant (HoldDuration = 0).
-- 2. Automatically interacts with every prompt the player is in range of.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

local AUTO_INTERACT_COOLDOWN = 0.1 -- 100ms cooldown between auto-interactions.

local paused = false
local instantEnabled = true -- Prompts forced instant (HoldDuration = 0)
local autoInteractEnabled = true -- Prompts auto-interacted with when in range
local prompts = {}

--==================================================
-- AUTO INTERACT GUI (draggable)
--==================================================

local gui = Instance.new("ScreenGui")
gui.Name = "AutoInteractGui"
gui.ResetOnSpawn = false
gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local mainFrame = Instance.new("Frame")
mainFrame.Position = UDim2.fromOffset(280, 250)
mainFrame.Size = UDim2.fromOffset(200, 95)
mainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Parent = gui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 8)
mainCorner.Parent = mainFrame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 28)
title.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
title.BorderSizePixel = 0
title.Text = "AUTO INTERACT"
title.TextColor3 = Color3.new(1, 1, 1)
title.TextSize = 12
title.Font = Enum.Font.GothamBold
mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 8)
mainCorner.Parent = title
title.Parent = mainFrame

local statusLabel = Instance.new("TextLabel")
statusLabel.Position = UDim2.fromOffset(10, 36)
statusLabel.Size = UDim2.fromOffset(180, 22)
statusLabel.BackgroundTransparency = 1
statusLabel.TextColor3 = Color3.fromRGB(120, 255, 120)
statusLabel.TextSize = 12
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.Parent = mainFrame

-- Setting indicators: show whether each feature is ON or OFF.
-- Click them to toggle that feature individually.

local function createIndicator(name, y)
	local indicator = Instance.new("TextButton")
	indicator.Name = name
	indicator.Position = UDim2.fromOffset(10, y)
	indicator.Size = UDim2.fromOffset(180, 24)
	indicator.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	indicator.BorderSizePixel = 0
	indicator.TextColor3 = Color3.new(1, 1, 1)
	indicator.TextSize = 11
	indicator.Font = Enum.Font.GothamBold
	indicator.AutoButtonColor = true
	indicator.Parent = mainFrame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = indicator

	return indicator
end

local instantIndicator = createIndicator("InstantIndicator", 60)
local autoInteractIndicator = createIndicator("AutoInteractIndicator", 88)

local toggleButton = Instance.new("TextButton")
toggleButton.Position = UDim2.fromOffset(10, 116)
toggleButton.Size = UDim2.fromOffset(180, 26)
toggleButton.BackgroundColor3 = Color3.fromRGB(55, 55, 55)
toggleButton.BorderSizePixel = 0
toggleButton.TextColor3 = Color3.new(1, 1, 1)
toggleButton.TextSize = 12
toggleButton.Font = Enum.Font.GothamBold
toggleButton.AutoButtonColor = true
toggleButton.Parent = mainFrame

local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 7)
toggleCorner.Parent = toggleButton

local keybindLabel = Instance.new("TextLabel")
keybindLabel.Position = UDim2.fromOffset(10, 146)
keybindLabel.Size = UDim2.fromOffset(180, 16)
keybindLabel.BackgroundTransparency = 1
keybindLabel.Text = "F3 = pause/resume"
keybindLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
keybindLabel.TextSize = 10
keybindLabel.Font = Enum.Font.Gotham
keybindLabel.TextXAlignment = Enum.TextXAlignment.Left
keybindLabel.Parent = mainFrame

mainFrame.Size = UDim2.fromOffset(200, 166)

local function updateGuiState()
	if paused then
		statusLabel.Text = "STATUS: PAUSED"
		statusLabel.TextColor3 = Color3.fromRGB(255, 120, 120)
		toggleButton.Text = "RESUME"
	else
		statusLabel.Text = "STATUS: RUNNING"
		statusLabel.TextColor3 = Color3.fromRGB(120, 255, 120)
		toggleButton.Text = "PAUSE"
	end

	if instantEnabled then
		instantIndicator.Text = "● INSTANT PROMPTS: ON"
		instantIndicator.TextColor3 = Color3.fromRGB(120, 255, 120)
	else
		instantIndicator.Text = "○ INSTANT PROMPTS: OFF"
		instantIndicator.TextColor3 = Color3.fromRGB(255, 120, 120)
	end

	if autoInteractEnabled then
		autoInteractIndicator.Text = "● AUTO INTERACT: ON"
		autoInteractIndicator.TextColor3 = Color3.fromRGB(120, 255, 120)
	else
		autoInteractIndicator.Text = "○ AUTO INTERACT: OFF"
		autoInteractIndicator.TextColor3 = Color3.fromRGB(255, 120, 120)
	end
end

local function setPaused(value)
	paused = value
	updateGuiState()
end

local function setInstant(value)
	instantEnabled = value
	updateGuiState()
end

local function setAutoInteract(value)
	autoInteractEnabled = value
	updateGuiState()
end

updateGuiState()

instantIndicator.MouseButton1Click:Connect(function()
	setInstant(not instantEnabled)
end)

autoInteractIndicator.MouseButton1Click:Connect(function()
	setAutoInteract(not autoInteractEnabled)
end)

-- Dragging via the title bar.
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

local function getPromptPosition(prompt)
	local parent = prompt.Parent
	if parent then
		if parent:IsA("BasePart") then
			return parent.Position
		elseif parent:IsA("Attachment") then
			return parent.WorldPosition
		end
	end
	return nil
end

local function isInRange(prompt)
	if not prompt.Enabled then
		return false
	end

	local position = getPromptPosition(prompt)
	if not position then
		return true -- Can't determine position; allow the attempt.
	end

	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end

	return (position - root.Position).Magnitude <= prompt.MaxActivationDistance + 2
end

local function watchPrompt(prompt)
	-- Keep the prompt instant even if something changes it back (unless paused).
	prompt:GetPropertyChangedSignal("HoldDuration"):Connect(function()
		if instantEnabled and not paused and prompt.HoldDuration > 0 then
			prompt.HoldDuration = 0
		end
	end)
end

local function trackPrompt(descendant)
	if descendant:IsA("ProximityPrompt") then
		if instantEnabled and not paused then
			descendant.HoldDuration = 0
		end
		prompts[descendant] = { lastTrigger = 0 }
		watchPrompt(descendant)
	end
end

-- Track every existing prompt in the game.
for _, descendant in ipairs(game:GetDescendants()) do
	trackPrompt(descendant)
end

-- Track prompts added later.
game.DescendantAdded:Connect(trackPrompt)

game.DescendantRemoving:Connect(function(descendant)
	if descendant:IsA("ProximityPrompt") then
		prompts[descendant] = nil
	end
end)

-- F3 toggles pausing/resuming the script.
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.KeyCode == Enum.KeyCode.F3 then
		setPaused(not paused)
	end
end)

toggleButton.MouseButton1Click:Connect(function()
	setPaused(not paused)
end)

-- Auto-interact loop: triggers every prompt the player is in range of.
RunService.Heartbeat:Connect(function()
	if paused or not autoInteractEnabled then
		return
	end

	local now = os.clock()

	for prompt, state in pairs(prompts) do
		if prompt.Parent and isInRange(prompt) then
			if now - state.lastTrigger >= AUTO_INTERACT_COOLDOWN then
				state.lastTrigger = now

				pcall(function()
					prompt:InputHoldBegin()
					prompt:InputHoldEnd()
				end)
			end
		end
	end
end)