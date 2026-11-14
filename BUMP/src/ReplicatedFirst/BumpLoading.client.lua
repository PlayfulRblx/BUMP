--!nonstrict
--[[
	BUMP's loading screen (the user, 2026-11-14: "change the loading screen for this game to
	something super simple? Let it say "Pls hire me Cinnamon, hehe""). Runs from ReplicatedFirst
	before anything else: removes Roblox's default loading screen and shows one line of text on a
	plain dark screen, over the engine's own loading screen (its UI LoadingScreen, Sunshine
	Valley's art, at DisplayOrder 100000; left alone, engine code), then fades out once the game
	has loaded, your data and character are in, and the engine's screen has finished and faded
	(at least MIN_SECONDS on screen, at most MAX_SECONDS). Self-contained: no requires, so it can
	run before the engine's libraries have arrived.
]]

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TweenService = game:GetService("TweenService")

local TEXT = "Pls hire me Cinnamon, hehe"
local MIN_SECONDS = 1.5
local MAX_SECONDS = 30
local FADE_SECONDS = 0.5
local BACKGROUND = Color3.fromRGB(20, 18, 30)
local INK = Color3.fromRGB(255, 250, 242)

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

gui.Parent = player:WaitForChild("PlayerGui")
ReplicatedFirst:RemoveDefaultLoadingScreen()

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
task.wait(FADE_SECONDS)
gui:Destroy()
