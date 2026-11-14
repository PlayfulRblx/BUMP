--!nonstrict
--[[
	Falling under the map, Mario style (the user, 2026-11-14: "When falling under the map, we should
	have a mario style camera follow disappearing into the screen turning black"; their choices:
	everywhere, an iris, and in a game only when nobody knocked you off, since then the knockout
	camera shows who did it).

	The camera stops where it is and only turns a little to watch you drop away at full speed; an
	iris (a black ring closing on a shrinking circle) closes on where you're vanishing; it holds on
	black until you're back on solid ground, then opens on the normal camera.

	- In a game: KnockoutCam hands a fall with nobody to blame here (FallCam.Play); the game moves
	  your body to the stand after RoundInfo.KnockoutHold.
	- Anywhere else (the lobby's pit, off the yard): this module notices your own body falling
	  below FALL_Y, plays the same, and once it's black asks the server to put you back
	  (Remotes "Fallen", Server/Systems/Lobby), as the server can't always see a falling body.

	The iris is a round frame with a huge black stroke round it, so there's no image to load; it
	sits under the HUD (DisplayOrder below the engine's UI), so the HUD stays up through the black.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local CameraHandlerClient = require("@Engine/Client/EngineSystems/CameraHandler/CameraHandlerClient")
local CameraState = require("@Engine/Client/EngineSystems/CameraHandler/Camera/CameraState")
local Remotes = require("@Shared/Movement/Remotes")
local RoundInfo = require("@Shared/Rounds/RoundInfo")

local FallCam = {}

local FALL_Y = -40 -- below this and still dropping, outside a game, it's a fall under the map
local FALL_SPEED = -15 -- dropping at least this fast (studs a second, so a hop down a ledge isn't one)
local WATCH = 0.45 -- seconds the camera turns to follow you before it lets you go
local CLOSE_AT, CLOSE = 0.35, 0.75 -- the iris starts closing this far in, and takes this long
local BLACK_MIN, BLACK_MAX = 0.35, 3 -- held on black at least this, at most this while you're moved
local OPEN = 0.5
local LAND_Y = -20 -- back above this, you've been put somewhere solid
local LAYER_PRIORITY = 46 -- over the knockout camera's (45), under the intro's (50)

local player = Players.LocalPlayer
local running = false
local serial = 0
local layer = nil -- the camera layer while a fall plays

local gui, hole, ring
local function iris()
	if gui and gui.Parent then
		return
	end
	gui = Instance.new("ScreenGui")
	gui.Name = "BumpFallIris"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = -10 -- under the HUD
	gui.Enabled = false
	hole = Instance.new("Frame")
	hole.Name = "Hole"
	hole.AnchorPoint = Vector2.new(0.5, 0.5)
	hole.BackgroundTransparency = 1
	hole.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = hole
	ring = Instance.new("UIStroke")
	ring.Color = Color3.new(0, 0, 0)
	ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ring.Parent = hole
	gui.Parent = player:WaitForChild("PlayerGui")
end

-- The iris: a clear circle of `radius` pixels at `centre`, black everywhere else.
local function setIris(centre: Vector2, radius: number)
	local viewport = Workspace.CurrentCamera.ViewportSize
	local reach = viewport.Magnitude * 1.5
	hole.Position = UDim2.fromOffset(centre.X, centre.Y)
	hole.Size = UDim2.fromOffset(radius * 2, radius * 2)
	ring.Thickness = reach
end

local function root(): BasePart?
	local character = player.Character
	local part = character and character:FindFirstChild("HumanoidRootPart")
	return part and part:IsA("BasePart") and part or nil
end

-- Plays the fall. `askToBeMoved`: once it's black, ask the server to put you back (outside a game).
function FallCam.Play(askToBeMoved: boolean?)
	local service = CameraHandlerClient.getService()
	local body = root()
	if running or not service or not body then
		return
	end
	running = true
	serial += 1
	local mine = serial
	iris()
	local camera = Workspace.CurrentCamera
	local eye = camera.CFrame.Position
	local look = camera.CFrame.LookVector
	local fov = camera.FieldOfView
	local startedAt = os.clock()
	local lastScreen = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)

	-- the camera stays put and only turns after you a little, then lets you go
	local function provider(_dt, base)
		if serial ~= mine then
			return base
		end
		local t = os.clock() - startedAt
		local current = root()
		if current and t < WATCH then
			local toBody = (current.Position - eye).Unit
			look = look:Lerp(toBody, 0.12).Unit
		end
		local cf = CFrame.lookAt(eye, eye + look)
		return CameraState.new(cf, fov, CFrame.new(eye + look * 10))
	end
	local ok, added = pcall(function()
		return service:AddLayer(provider, LAYER_PRIORITY, { KeepBaseCamera = true })
	end)
	if not ok or not added then
		running = false
		return
	end
	layer = added
	layer:setWeight(1)

	task.spawn(function()
		-- closing on where you are on screen (held at the last place you were seen)
		gui.Enabled = true
		local viewport = camera.ViewportSize
		local full = viewport.Magnitude * 0.75
		setIris(lastScreen, full)
		while serial == mine do
			local t = os.clock() - startedAt
			local current = root()
			if current then
				local point, onScreen = camera:WorldToViewportPoint(current.Position)
				if onScreen then
					lastScreen = Vector2.new(
						math.clamp(point.X, 0, viewport.X),
						math.clamp(point.Y, 0, viewport.Y)
					)
				end
			end
			local u = math.clamp((t - CLOSE_AT) / CLOSE, 0, 1)
			-- eased in: slow at first, snapping shut
			local radius = full * (1 - u * u)
			setIris(lastScreen, radius)
			if u >= 1 then
				break
			end
			RunService.RenderStepped:Wait()
		end
		if serial ~= mine then
			return
		end
		setIris(lastScreen, 0)
		-- held still in the dark, so it can't fall on to the kill plane (Workspace.FallenPartsDestroyHeight,
		-- -500, which would respawn you) while it waits to be moved
		local held = root()
		if held then
			held.AssemblyLinearVelocity = Vector3.zero
			held.Anchored = true
		end
		if askToBeMoved then
			Remotes.Act("Fallen")
		end
		-- black until you're somewhere solid again (or long enough)
		local blackAt = os.clock()
		while os.clock() - blackAt < BLACK_MAX do
			local current = root()
			if os.clock() - blackAt >= BLACK_MIN and current and current.Position.Y > LAND_Y then
				break
			end
			task.wait(0.05)
		end
		if held and held.Parent then
			held.Anchored = false
		end
		pcall(function()
			added:remove()
		end)
		layer = nil
		-- open from the middle on the normal camera
		local middle = Vector2.new(viewport.X / 2, viewport.Y / 2)
		local openedAt = os.clock()
		while os.clock() - openedAt < OPEN do
			local u = (os.clock() - openedAt) / OPEN
			setIris(middle, full * (1 - (1 - u) * (1 - u)))
			RunService.RenderStepped:Wait()
		end
		gui.Enabled = false
		running = false
	end)
end

function FallCam.Running(): boolean
	return running
end

-- Whether you're in a game right now (falls in a game are the game's to judge).
local function inGame(): boolean
	local round = ReplicatedStorage:FindFirstChild(RoundInfo.Folder)
	if not round then
		return false
	end
	local phase = round:GetAttribute("Phase")
	if phase ~= "Play" and phase ~= "Intro" then
		return false
	end
	local ok, list = pcall(HttpService.JSONDecode, HttpService, round:GetAttribute("Players") or "[]")
	if not ok or type(list) ~= "table" then
		return false
	end
	for _, entry in list do
		if type(entry) == "table" and entry.UserId == player.UserId then
			return not entry.Out
		end
	end
	return false
end

function FallCam.start()
	-- falls outside a game: the lobby's pit, off the yard
	RunService.Heartbeat:Connect(function()
		if running then
			return
		end
		local body = root()
		local character = player.Character
		if not body or not character or character:GetAttribute(RoundInfo.KnockoutHoldAttr) then
			return
		end
		if body.Position.Y < FALL_Y and body.AssemblyLinearVelocity.Y < FALL_SPEED and not inGame() then
			FallCam.Play(true)
		end
	end)
	player.CharacterAdded:Connect(function()
		serial += 1
		running = false
		if layer then
			pcall(function()
				layer:remove()
			end)
			layer = nil
		end
		if gui then
			gui.Enabled = false
		end
	end)
end

return FallCam
