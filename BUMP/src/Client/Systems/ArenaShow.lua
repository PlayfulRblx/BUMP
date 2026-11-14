--!nonstrict
--[[
	The arena's entrance and exit (the user, 2026-11-13: "Each time we change the map, could we have
	a AAA ADHD sequence of the map loading in piece (or chunk) by piece?").

	When a game's hex arena appears (a Workspace folder with the "HexArena" attribute, HexArena on
	the server, during the game's intro while everyone is frozen), each client plays it in: the
	tiles slam down from the sky ring by ring from the middle out, sweeping round each ring,
	spinning as they fall, bouncing as they land with a flash, a burst of sparkles and a ping that
	climbs ring by ring; when the last lands, a shockwave rolls across the arena with a bang, a
	burst of confetti and a camera shake. When a game ends (the folder's "Leaving" attribute) the
	tiles fly off upward in waves from the edge in.

	Drawn here only: the real tiles are in place (and solid) from the start, hidden on this client
	(LocalTransparencyModifier) while copies of them do the show, so nobody can fall through.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ArenaShow = {}

local SPARKLE = "rbxassetid://128453777673840" -- VFX IKEA sparkle (BumpFx uses it too)
local RING_FLIPBOOK = "rbxassetid://75804565349970" -- VFX IKEA circleboom2
local PING = "rbxasset://sounds/electronicpingshort.wav"
local BOOM = "rbxasset://sounds/impact_explosion_03.mp3"
local WHITE = Color3.new(1, 1, 1)
local CONFETTI = {
	Color3.fromRGB(60, 225, 255), Color3.fromRGB(255, 80, 200), Color3.fromRGB(150, 100, 255),
	Color3.fromRGB(255, 220, 60), Color3.fromRGB(90, 255, 140), Color3.fromRGB(255, 140, 50),
}

local RING_GAP = 0.2 -- seconds between rings starting
local SWEEP = 0.16 -- how long a ring takes to sweep round
local FALL = 0.42 -- a tile's drop
local SETTLE = 0.2 -- its bounce
local DROP_HEIGHT = 55

local rng = Random.new()
local lastPing = 0

-- ═══ little helpers ══════════════════════════════════════════════════════════════

local function ease(t: number): number
	return t * t * t
end

local function sound(id: string, volume: number, speed: number, at: Vector3)
	local holder = Instance.new("Attachment")
	holder.WorldPosition = at
	holder.Parent = Workspace.Terrain
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.PlaybackSpeed = speed
	s.RollOffMinDistance = 30
	s.RollOffMaxDistance = 600
	s.Parent = holder
	s:Play()
	Debris:AddItem(holder, 4)
end

local function burst(at: Vector3, color: Color3, size: number, count: number)
	local holder = Instance.new("Attachment")
	holder.WorldPosition = at
	holder.Parent = Workspace.Terrain
	local ring = Instance.new("ParticleEmitter")
	ring.Texture = RING_FLIPBOOK
	ring.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
	ring.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
	ring.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
	ring.EmissionDirection = Enum.NormalId.Top
	ring.Speed = NumberRange.new(0.01)
	ring.Lifetime = NumberRange.new(0.4)
	ring.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.2), NumberSequenceKeypoint.new(1, size) })
	ring.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	ring.Color = ColorSequence.new(color)
	ring.LightEmission = 0.8
	ring.Rate = 0
	ring.Parent = holder
	ring:Emit(1)
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = SPARKLE
	sparks.Speed = NumberRange.new(8, 18)
	sparks.SpreadAngle = Vector2.new(70, 70)
	sparks.Lifetime = NumberRange.new(0.3, 0.6)
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
	sparks.Color = ColorSequence.new(color)
	sparks.LightEmission = 1
	sparks.Drag = 3
	sparks.Acceleration = Vector3.new(0, -20, 0)
	sparks.Rate = 0
	sparks.Parent = holder
	sparks:Emit(count)
	Debris:AddItem(holder, 1)
end

local function kick(amount: number)
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 0.4 do
			local fade = 1 - (os.clock() - t0) / 0.4
			humanoid.CameraOffset = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), 0) * amount * fade
			RunService.RenderStepped:Wait()
		end
		humanoid.CameraOffset = Vector3.zero
	end)
end

-- Hide or show a tile's real parts on this client.
local function hide(tile: Model, hidden: boolean)
	for _, part in tile:GetDescendants() do
		if part:IsA("BasePart") then
			part.LocalTransparencyModifier = hidden and 1 or 0
		end
	end
end

-- A copy of a tile to animate: not solid, not queried, shown even though the real one is hidden.
local function copyOf(tile: Model): Model
	local copy = tile:Clone()
	for _, part in copy:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.LocalTransparencyModifier = 0
		end
	end
	return copy
end

local function tilesOf(folder: Instance, centre: Vector3)
	local list = {}
	for _, tile in folder:GetChildren() do
		local ring = tile:IsA("Model") and tile:GetAttribute("Ring")
		if ring then
			local at = tile:GetPivot().Position - centre
			table.insert(list, { model = tile, ring = ring, angle = math.atan2(at.Z, at.X), home = tile:GetPivot() })
		end
	end
	return list
end

local function centreOf(folder: Instance): Vector3
	-- an arena that says where its middle is (MELTDOWN's tower: its ring-0 tiles are the start ring)
	local given = folder:GetAttribute("Centre")
	if typeof(given) == "Vector3" then
		return given
	end
	local sum, count = Vector3.zero, 0
	for _, tile in folder:GetChildren() do
		if tile:IsA("Model") and tile:GetAttribute("Ring") == 0 then
			return tile:GetPivot().Position
		elseif tile:IsA("Model") then
			sum += tile:GetPivot().Position
			count += 1
		end
	end
	return count > 0 and sum / count or Vector3.zero
end

local function edgeColour(model: Model): Color3
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and part.Name:find("Edge") then
			return part.Color
		end
	end
	return WHITE
end

-- ═══ the entrance ════════════════════════════════════════════════════════════════

local function finale(centre: Vector3, reach: number)
	-- a shockwave across the whole arena, confetti, a bang, a shake
	local wave = Instance.new("Part")
	wave.Shape = Enum.PartType.Cylinder
	wave.Anchored, wave.CanCollide, wave.CanQuery, wave.CanTouch, wave.CastShadow = true, false, false, false, false
	wave.Material = Enum.Material.Neon
	wave.Color = WHITE
	wave.Transparency = 0.2
	wave.Size = Vector3.new(0.3, 4, 4)
	wave.CFrame = CFrame.new(centre + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, 0, math.rad(90))
	wave.Parent = Workspace
	TweenService:Create(wave, TweenInfo.new(0.7, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.1, reach * 2.4, reach * 2.4),
		Transparency = 1,
	}):Play()
	Debris:AddItem(wave, 0.8)
	local holder = Instance.new("Attachment")
	holder.WorldPosition = centre + Vector3.new(0, 4, 0)
	holder.Parent = Workspace.Terrain
	for _, colour in CONFETTI do
		local confetti = Instance.new("ParticleEmitter")
		confetti.Texture = SPARKLE
		confetti.Speed = NumberRange.new(40, 70)
		confetti.SpreadAngle = Vector2.new(35, 35)
		confetti.Lifetime = NumberRange.new(1.4, 2.2)
		confetti.Acceleration = Vector3.new(0, -40, 0)
		confetti.Drag = 1.5
		confetti.Size = NumberSequence.new(1.3)
		confetti.Color = ColorSequence.new(colour)
		confetti.LightEmission = 0.7
		confetti.RotSpeed = NumberRange.new(-300, 300)
		confetti.Rate = 0
		confetti.Parent = holder
		confetti:Emit(18)
	end
	Debris:AddItem(holder, 3)
	sound(BOOM, 0.7, 1.15, centre)
	sound(PING, 0.8, 1.6, centre)
	kick(0.9)
end

local function playIn(folder: Instance)
	local centre = centreOf(folder)
	local tiles = tilesOf(folder, centre)
	if #tiles == 0 then
		return
	end
	-- the order: ring by ring from the middle, sweeping round each ring
	for _, tile in tiles do
		hide(tile.model, true)
		tile.start = tile.ring * RING_GAP + ((tile.angle + math.pi) / (math.pi * 2)) * SWEEP + rng:NextNumber(0, 0.04)
		tile.spin = CFrame.Angles(rng:NextNumber(-1.2, 1.2), rng:NextNumber(-3, 3), rng:NextNumber(-1.2, 1.2))
		tile.colour = edgeColour(tile.model)
	end
	local stage = Instance.new("Folder")
	stage.Name = "ArenaShow"
	stage.Parent = Workspace
	local reach = 0
	for _, tile in tiles do
		local out = tile.home.Position - centre
		reach = math.max(reach, Vector3.new(out.X, 0, out.Z).Magnitude) -- across, not up (a tower is tall)
	end
	local started = os.clock()
	local left = #tiles
	local connection
	connection = RunService.RenderStepped:Connect(function()
		if not folder.Parent or folder:GetAttribute("Leaving") then
			connection:Disconnect()
			stage:Destroy()
			return
		end
		local now = os.clock() - started
		for _, tile in tiles do
			if not tile.done and now >= tile.start then
				local t = now - tile.start
				if not tile.copy then
					tile.copy = copyOf(tile.model)
					tile.copy.Parent = stage
				end
				if t < FALL then
					local q = t / FALL
					local height = DROP_HEIGHT * (1 - ease(q))
					local spin = tile.spin:Lerp(CFrame.identity, ease(q))
					tile.copy:PivotTo(tile.home * CFrame.new(0, height, 0) * spin)
				elseif t < FALL + SETTLE then
					if not tile.landed then
						tile.landed = true
						local at = tile.home.Position + Vector3.new(0, 0.4, 0)
						burst(at, tile.colour, 14, 5)
						for _, part in tile.copy:GetChildren() do
							if part:IsA("BasePart") then
								part:SetAttribute("ShowColour", part.Color)
								part.Color = WHITE
							end
						end
						-- a ping per landing, climbing ring by ring (throttled: a ring lands together)
						if os.clock() - lastPing > 0.035 then
							lastPing = os.clock()
							sound(PING, 0.35, 0.8 + tile.ring * 0.12 + rng:NextNumber(-0.03, 0.03), at)
						end
					end
					local q = (t - FALL) / SETTLE
					local dip = -1.1 * math.sin(q * math.pi) * (1 - q * 0.5)
					tile.copy:PivotTo(tile.home * CFrame.new(0, dip, 0))
					for _, part in tile.copy:GetChildren() do
						local base = part:IsA("BasePart") and part:GetAttribute("ShowColour")
						if base then
							part.Color = WHITE:Lerp(base, q)
						end
					end
				else
					tile.done = true
					tile.copy:Destroy()
					hide(tile.model, false)
					left -= 1
				end
			end
		end
		if left == 0 then
			connection:Disconnect()
			stage:Destroy()
			finale(centre, reach)
		end
	end)
end

-- ═══ the exit ════════════════════════════════════════════════════════════════════

local function playOut(folder: Instance)
	local centre = centreOf(folder)
	local tiles = tilesOf(folder, centre)
	local outer = 0
	for _, tile in tiles do
		outer = math.max(outer, tile.ring)
	end
	local stage = Instance.new("Folder")
	stage.Name = "ArenaShowOut"
	stage.Parent = Workspace
	for _, tile in tiles do
		if tile.model.Parent then
			hide(tile.model, true)
			tile.copy = copyOf(tile.model)
			tile.copy.Parent = stage
			-- outside in: the rim goes first
			tile.start = (outer - tile.ring) * 0.09 + rng:NextNumber(0, 0.06)
			tile.spin = CFrame.Angles(rng:NextNumber(-2, 2), rng:NextNumber(-4, 4), rng:NextNumber(-2, 2))
			tile.drift = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)) * 10
		end
	end
	local started = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local now = os.clock() - started
		local all = true
		for _, tile in tiles do
			if tile.copy then
				local t = math.max(0, now - tile.start)
				if t > 0 and not tile.launched then
					tile.launched = true
					burst(tile.home.Position, edgeColour(tile.copy), 10, 3)
				end
				local q = math.min(t / 0.9, 1)
				local rise = 70 * q * q
				tile.copy:PivotTo(tile.home * CFrame.new(tile.drift * q + Vector3.new(0, rise, 0)) * CFrame.identity:Lerp(tile.spin, q))
				for _, part in tile.copy:GetChildren() do
					if part:IsA("BasePart") then
						part.Transparency = math.max(part.Transparency, q)
					end
				end
				if q < 1 then
					all = false
				end
			end
		end
		if all or now > 2.5 then
			connection:Disconnect()
			stage:Destroy()
		end
	end)
	sound(PING, 0.5, 0.6, centre)
end

-- ═══ watching for arenas ═════════════════════════════════════════════════════════

local function watch(folder: Instance)
	if not folder:GetAttribute("HexArena") then
		return
	end
	if not folder:GetAttribute("Leaving") then
		task.defer(playIn, folder)
	end
	folder:GetAttributeChangedSignal("Leaving"):Connect(function()
		if folder:GetAttribute("Leaving") then
			playOut(folder)
		end
	end)
end

function ArenaShow.start()
	Workspace.ChildAdded:Connect(watch)
end

return ArenaShow
