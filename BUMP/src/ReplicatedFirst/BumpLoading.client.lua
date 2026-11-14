--!nonstrict
--[[
	BUMP's loading screen (the user, 2026-11-14: "change the loading screen for this game to
	something super simple? Let it say "Pls hire me Cinnamon, hehe""; then: "something quick and
	simple with a bit of comedic value to it"; they picked a kazoo fanfare, as the meme voice clips
	they named are other people's recordings). Runs from ReplicatedFirst before anything else:
	removes Roblox's default loading screen and shows a plain dark screen over the engine's own
	loading screen (its UI LoadingScreen, Sunshine Valley's art, at DisplayOrder 100000; left
	alone, engine code). "Pls hire me Cinnamon," bounces in to a pompous kazoo fanfare (Pro Sound
	Effects, licensed), then "hehe" pops in under it, tilted and wiggling. It fades out (the kazoo
	with it) once the game has loaded, your data and character are in, and the engine's screen has
	finished and faded (at least MIN_SECONDS on screen, at most MAX_SECONDS). Self-contained: no
	requires, so it can run before the engine's libraries have arrived.
]]

local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local TEXT = "Pls hire me Cinnamon,"
local AFTER = "hehe"
local KAZOO = "rbxassetid://9114898444" -- Pro Sound Effects "Kazoo Fanfare 3": announcing royalty, 4.3 s
local MIN_SECONDS = 2.4 -- long enough for the joke to land
local MAX_SECONDS = 30
local FADE_SECONDS = 0.5
local BACKGROUND = Color3.fromRGB(20, 18, 30)
local INK = Color3.fromRGB(255, 250, 242)
local GIGGLE = Color3.fromRGB(255, 214, 54)

local player = Players.LocalPlayer
local shownAt = os.clock()

local gui = Instance.new("ScreenGui")
gui.Name = "BumpLoading"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 1000000 -- over the engine's loading screen (100000) and splashes (100002)
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local backdrop = Instance.new("Frame")
backdrop.Name = "Backdrop"
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = BACKGROUND
backdrop.BorderSizePixel = 0
backdrop.Parent = gui

local label = Instance.new("TextLabel")
label.Name = "Line"
label.AnchorPoint = Vector2.new(0.5, 0.5)
label.Position = UDim2.fromScale(0.5, 0.5)
label.Size = UDim2.new(0.8, 0, 0, 48)
label.BackgroundTransparency = 1
label.Text = TEXT
label.TextColor3 = INK
label.TextScaled = true
label.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
label.Parent = backdrop

local limit = Instance.new("UITextSizeConstraint")
limit.MaxTextSize = 40
limit.Parent = label

local labelScale = Instance.new("UIScale")
labelScale.Scale = 0
labelScale.Parent = label

local hehe = Instance.new("TextLabel")
hehe.Name = "Hehe"
hehe.AnchorPoint = Vector2.new(0.5, 0.5)
hehe.Position = UDim2.new(0.5, 0, 0.5, 52)
hehe.Size = UDim2.new(0.4, 0, 0, 40)
hehe.BackgroundTransparency = 1
hehe.Text = AFTER
hehe.TextColor3 = GIGGLE
hehe.TextScaled = true
hehe.Rotation = 8
hehe.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
hehe.Parent = backdrop
local heheLimit = Instance.new("UITextSizeConstraint")
heheLimit.MaxTextSize = 34
heheLimit.Parent = hehe
local heheScale = Instance.new("UIScale")
heheScale.Scale = 0
heheScale.Parent = hehe

local kazoo = Instance.new("Sound")
kazoo.Name = "BumpLoadingKazoo"
kazoo.SoundId = KAZOO
kazoo.Volume = 0.6
kazoo.Parent = SoundService

gui.Parent = player:WaitForChild("PlayerGui")
ReplicatedFirst:RemoveDefaultLoadingScreen()

-- the bit: the line bounces in as the kazoo starts (given a moment to load, so they land together),
-- then "hehe" pops in under it and wiggles
task.spawn(function()
	local loadedBy = os.clock() + 1
	task.spawn(function()
		pcall(ContentProvider.PreloadAsync, ContentProvider, { kazoo })
	end)
	while not kazoo.IsLoaded and os.clock() < loadedBy do
		task.wait()
	end
	kazoo:Play()
	label.Rotation = -6
	TweenService:Create(labelScale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(label, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Rotation = 0 }):Play()
	task.wait(0.7)
	TweenService:Create(heheScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false), { Scale = 1 }):Play()
	local wiggleFrom = os.clock()
	local wiggle
	wiggle = RunService.RenderStepped:Connect(function()
		if not gui.Parent then
			wiggle:Disconnect()
			return
		end
		local t = os.clock() - wiggleFrom
		hehe.Rotation = 8 + math.sin(t * 9) * 6
	end)
end)

-- wait for the game, then for your character, within the limit
local function waitUntil(check)
	while not check() and os.clock() - shownAt < MAX_SECONDS do
		task.wait(0.1)
	end
end
waitUntil(function()
	return game:IsLoaded()
end)
waitUntil(function()
	local character = player.Character
	return player:GetAttribute("PlayerDataLoaded") == true
		and character ~= nil
		and character:FindFirstChild("HumanoidRootPart") ~= nil
end)
-- the engine's screen: its stack says it's done, and its fade has hidden it
waitUntil(function()
	if player:GetAttribute("LoadingScreenActive") == true then
		return false
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local fade = playerGui and playerGui:FindFirstChild("LoadingScreenFade", true)
	return fade == nil or not fade:IsA("GuiObject") or not fade.Visible
end)
local playerGuiNow = player:FindFirstChildOfClass("PlayerGui")
local engineFade = playerGuiNow and playerGuiNow:FindFirstChild("LoadingScreenFade", true)
print(string.format("[Loading] hiding after %.1f s (engine screen %s)", os.clock() - shownAt,
	engineFade and (engineFade.Visible and "still showing" or "hidden") or "not found"))
local left = MIN_SECONDS - (os.clock() - shownAt)
if left > 0 then
	task.wait(left)
end

local info = TweenInfo.new(FADE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
TweenService:Create(backdrop, info, { BackgroundTransparency = 1 }):Play()
TweenService:Create(label, info, { TextTransparency = 1 }):Play()
TweenService:Create(hehe, info, { TextTransparency = 1 }):Play()
TweenService:Create(kazoo, TweenInfo.new(FADE_SECONDS + 0.4), { Volume = 0 }):Play()
task.wait(FADE_SECONDS)
gui:Destroy()
task.delay(0.5, function()
	kazoo:Destroy()
end)
