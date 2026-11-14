--!nonstrict
--[[
	Your power-up buttons (Shared/PowerUps/PowerUpInfo, Server/Rounds/PowerUps).

	- Use (Q, gamepad Y, the touch ring's third button): asks the server to fire the power-up you
	  hold in this game (Act "PowerUp"). Its input chip names the power-up, only while you hold
	  one, and is dimmed once it's used, outside play, or for Second Chance (which works by
	  itself).
	- Shop (B, gamepad Select): opens and closes the shop (RoundClient's ShopOpen). Not while
	  you're playing a game; it closes itself when your game starts.
	- A Second Chance catching you ("Rescue"): the server has put your body back on the floor;
	  this drops the fall speed your own client was carrying and gives a little bounce.

	The HUD's shop button and power-up slot read the same RoundClient values.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local InputHandler = require("@Engine/Shared/Handlers/InputHandler")
local PowerUpInfo = require("@Shared/PowerUps/PowerUpInfo")
local Remotes = require("@Shared/Movement/Remotes")
local RoundClient = require("@Client/Systems/RoundClient")

local PowerUpClient = {}

local BINDING_PRIORITY = 3
local USE_ID = "BumpPower"
local SHOP_ID = "BumpShop"

local player = Players.LocalPlayer
local useHint = nil -- { handle, label, enabled, visible }

-- Whether you're a contestant in a game that's under way (intro or play).
local function inAGame(): boolean
	local phase = RoundClient.Get("Phase")
	if phase ~= "Intro" and phase ~= "Play" then
		return false
	end
	for _, entry in RoundClient.Get("Players") or {} do
		if entry.You then
			return not entry.Out
		end
	end
	return false
end

local function useState(): (string, boolean, boolean)
	local power = RoundClient.Get("Power")
	local item = power and PowerUpInfo.Get(power.Id)
	if not item or not inAGame() then
		return "Power-up", false, false
	end
	local ready = not power.Used and not item.Automatic and RoundClient.Get("Phase") == "Play"
	local label = item.Automatic and (item.Name .. " (auto)") or item.Name
	return label, ready, true
end

local function refresh()
	if not useHint then
		return
	end
	local label, enabled, visible = useState()
	if label ~= useHint.label or enabled ~= useHint.enabled or visible ~= useHint.visible then
		useHint.label, useHint.enabled, useHint.visible = label, enabled, visible
		useHint.handle:Update({ Label = label, Enabled = enabled, Visible = visible })
	end
end

local function bind()
	InputHandler:BindInput(USE_ID, {
		DESKTOP = { Enum.KeyCode.Q },
		GAMEPAD = { Enum.KeyCode.ButtonY },
		MOBILE = { "primary3" },
	}, BINDING_PRIORITY, function(state)
		if state ~= Enum.UserInputState.Begin or UserInputService:GetFocusedTextBox() then
			return
		end
		local _, ready = useState()
		if ready then
			Remotes.Act("PowerUp")
		end
	end, { Hint = { Label = "Power-up", Group = "Moves", Order = 4 } })
	local handle = InputHandler:RegisterInputHint({
		Id = USE_ID, InputName = USE_ID, Label = "Power-up", Group = "Moves", Order = 4, Visible = false,
	})
	if handle then
		useHint = { handle = handle, label = "Power-up", enabled = true, visible = false }
	end

	InputHandler:BindInput(SHOP_ID, {
		DESKTOP = { Enum.KeyCode.B },
		GAMEPAD = { Enum.KeyCode.ButtonSelect },
	}, BINDING_PRIORITY, function(state)
		if state ~= Enum.UserInputState.Begin or UserInputService:GetFocusedTextBox() then
			return
		end
		if not inAGame() then
			RoundClient.Do("ShopToggle")
		end
	end, { Hint = false }) -- no chip: the HUD's shop button wears its key cap
end

local function onRescue()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		root.AssemblyLinearVelocity = Vector3.new(0, 30, 0)
	end
end

function PowerUpClient.start()
	bind()
	Remotes.HookYou(function(name)
		if name == "Rescue" then
			onRescue()
		end
	end)
	-- the shop shuts when your game starts
	RoundClient.Subscribe(function(key)
		if (key == "Phase" or key == "Players") and RoundClient.Get("ShopOpen") and inAGame() then
			RoundClient.Do("ShopClose")
		end
	end)
	RunService.Heartbeat:Connect(refresh)
end

return PowerUpClient
