--!nonstrict
--[[
	MELTDOWN's tower in the world: built from a MeltLayout (Shared/Minigames/MeltLayout) in the
	lobby's pit, with its bookkeeping, platform by platform.

	    local tower = Tower.new(layout, origin)
	    tower:Step(t, bodies)          -- every frame: movers move (carrying the bots on them), a
	                                   -- crumbling platform someone stands on starts to go
	    tower:PlatformUnder(position)  -- the platform a body stands on (or nil), by height too;
	                                   -- the start ring is Tower.Base, the pit's floor Tower.Pit
	    tower:Centre(platform)         -- where its top's middle is right now (movers move)
	    tower:Crumble(platform, warn, back)  -- shake and flash, then fall; back after `back`
	                                   -- seconds (never, if nil) unless the lava's there by then
	    tower:SafeAbove(y)             -- the middle of a solid platform's top above y, the nearest
	    tower:SetLava(y, rate)         -- the lava's height now and how fast it's rising
	    tower:Lava()                   -- its height now
	    tower:Destroy()

	The folder carries "HexArena" (so every client plays it in, Client/Systems/ArenaShow, tier
	pairs as rings from the bottom up) and "Centre" (the arena's middle; its first ring-0 tile is
	out on the start ring). A platform's model carries "Ring", "PlatformId", "Kind"; a moving one
	RoundInfo.MoverAttr and its path ("MoverAxis", "MoverAmp", "MoverPeriod", "MoverPhase",
	"MoverHome"), so every client moves its own copy smoothly (Client/Systems/MeltClient); a bounce
	pad is a part named "Pad" with RoundInfo.BounceAttr. The lava is a part named "Lava" the
	clients move themselves, from the folder's "LavaY" / "LavaAt" / "LavaRate".
]]

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Hex = require("@Shared/Minigames/Hex")
local MeltLayout = require("@Shared/Minigames/MeltLayout")
local Remotes = require("@Shared/Movement/Remotes")
local RoundInfo = require("@Shared/Rounds/RoundInfo")
local World = require("@Shared/World")

local Tower = {}
Tower.__index = Tower

local SLAB = 2.5
local WARN_COLOR = Color3.fromRGB(255, 70, 70)
local TOP = Color3.fromRGB(70, 62, 78) -- dark tops, the edges carry the colour
local CRUMBLE_TOP = Color3.fromRGB(150, 112, 92) -- sandy and cracked: it won't hold you long
local MOVER_EDGE = Color3.fromRGB(255, 90, 210)
local PAD_COLOR = Color3.fromRGB(90, 255, 140)
local BASE_EDGE = Color3.fromRGB(255, 96, 60)
local PIT_EDGE = Color3.fromRGB(150, 60, 50)
local CORE_EDGE = Color3.fromRGB(255, 140, 60)
local WALL_COLOR = Color3.fromRGB(48, 42, 60)
local WALL_STRIP = Color3.fromRGB(255, 220, 90)
-- edges by height: red-hot at the bottom, through orange and yellow, to cool at the top
local HEIGHT_EDGES = {
	Color3.fromRGB(255, 70, 50),
	Color3.fromRGB(255, 130, 50),
	Color3.fromRGB(255, 200, 70),
	Color3.fromRGB(190, 240, 110),
	Color3.fromRGB(110, 225, 255),
}
local LAVA_COLOR = Color3.fromRGB(235, 62, 18)
local LAVA_THICK = 60

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function heightEdge(u: number): Color3
	u = math.clamp(u, 0, 1) * (#HEIGHT_EDGES - 1)
	local index = math.floor(u)
	local a = HEIGHT_EDGES[index + 1]
	local b = HEIGHT_EDGES[math.min(index + 2, #HEIGHT_EDGES)]
	return a:Lerp(b, u - index)
end

local function part(parent: Instance, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, name: string?): Part
	local p = Instance.new("Part")
	p.Name = name or "Part"
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function ringOf(tier: number): number
	return math.ceil(tier / 2)
end

-- One platform's model, at home.
local function buildPlatform(spec, origin: Vector3, tiers: number): Model
	local top = spec.Kind == "Crumble" and CRUMBLE_TOP or TOP
	local edge = spec.Kind == "Mover" and MOVER_EDGE or heightEdge(spec.Tier / tiers)
	local centre = origin + spec.Position - Vector3.new(0, SLAB / 2, 0)
	local model = Hex.BuildTile(spec.Size, SLAB, CFrame.new(centre), top, nil, edge)
	model.Name = string.format("Platform_%d", spec.Id)
	model:SetAttribute("Ring", ringOf(spec.Tier))
	model:SetAttribute("PlatformId", spec.Id)
	model:SetAttribute("Kind", spec.Kind)
	if spec.Kind == "Crumble" then
		-- cracks across the top
		for index = 0, 2 do
			local crack = part(model, Vector3.new(spec.Size * 1.2, 0.08, 0.25), CFrame.new(centre + Vector3.new(0, SLAB / 2 + 0.07, 0)) * CFrame.Angles(0, math.rad(60 * index + 17), 0), Color3.fromRGB(70, 46, 40), Enum.Material.SmoothPlastic, "Crack")
			crack.CanCollide = false
			crack.CanQuery = false
		end
	end
	if spec.Mover then
		model:SetAttribute(RoundInfo.MoverAttr, true)
		model:SetAttribute("MoverAxis", spec.Mover.Axis)
		model:SetAttribute("MoverAmp", spec.Mover.Amp)
		model:SetAttribute("MoverPeriod", spec.Mover.Period)
		model:SetAttribute("MoverPhase", spec.Mover.Phase)
		model:SetAttribute("MoverHome", model:GetPivot())
	end
	if spec.Pad then
		local pad = part(model, Vector3.new(0.6, 5.5, 5.5), CFrame.new(centre + Vector3.new(0, SLAB / 2 + 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)), PAD_COLOR, Enum.Material.Neon, "Pad")
		pad.Shape = Enum.PartType.Cylinder
		pad:SetAttribute(RoundInfo.BounceAttr, spec.Pad.Height)
		local ring = part(model, Vector3.new(0.4, 7, 7), pad.CFrame - Vector3.new(0, 0.1, 0), Color3.fromRGB(30, 90, 50), Enum.Material.SmoothPlastic, "PadRim")
		ring.Shape = Enum.PartType.Cylinder
		local glow = Instance.new("PointLight")
		glow.Color = PAD_COLOR
		glow.Range = 12
		glow.Brightness = 1.5
		glow.Parent = pad
	end
	return model
end

local function buildChimney(chimney, origin: Vector3, tier: number): Model
	local model = Instance.new("Model")
	model.Name = "Chimney"
	model:SetAttribute("Ring", ringOf(tier))
	local bottom = origin + chimney.Position
	for _, side in { -1, 1 } do
		local centre = bottom + chimney.Across * side * (chimney.Gap / 2 + 0.6) + Vector3.new(0, chimney.Height / 2, 0)
		local frame = CFrame.fromMatrix(centre, chimney.Across, Vector3.yAxis)
		part(model, Vector3.new(1.2, chimney.Height, MeltLayout.ChimneyWidth), frame, WALL_COLOR, Enum.Material.SmoothPlastic, "Wall")
		-- a bright strip up each outer edge and along the top, so you can read the shaft from afar
		for _, along in { -1, 1 } do
			local strip = part(model, Vector3.new(1.3, chimney.Height, 0.35), frame * CFrame.new(0, 0, along * (MeltLayout.ChimneyWidth / 2 - 0.15)), WALL_STRIP, Enum.Material.Neon, "Edge")
			strip.CanCollide = false
			strip.CanQuery = false
		end
		local cap = part(model, Vector3.new(1.3, 0.35, MeltLayout.ChimneyWidth), frame * CFrame.new(0, chimney.Height / 2 - 0.15, 0), WALL_STRIP, Enum.Material.Neon, "Edge")
		cap.CanCollide = false
		cap.CanQuery = false
	end
	return model
end

function Tower.new(layout, origin: Vector3)
	local self = setmetatable({}, Tower)
	self.layout = layout
	self.origin = origin
	self.platforms = {} -- [id] = { spec, model, template, state, keep }
	self.lavaY, self.lavaAt, self.lavaRate = origin.Y - 20, now(), 0
	self.pitDrop = layout.Pit[1] and -layout.Pit[1].Y or 10
	local folder = Instance.new("Folder")
	folder.Name = "MeltTower"
	self.folder = folder
	local tiers = layout.Tiers

	-- the start ring
	local tile = MeltLayout.BaseTile
	for index, at in layout.Base do
		local color = TOP
		if index % 2 == 0 then
			color = color:Lerp(Color3.new(1, 1, 1), 0.12)
		end
		local model = Hex.BuildTile(tile * 0.97, SLAB, CFrame.new(origin + at - Vector3.new(0, SLAB / 2, 0)), color, nil, BASE_EDGE)
		model.Name = "Base_" .. index
		model:SetAttribute("Ring", 0)
		model.Parent = folder
	end
	-- the pit's floor under the tower, darker, a step below the ring
	for index, at in layout.Pit do
		local color = Color3.fromRGB(46, 40, 52)
		if index % 2 == 0 then
			color = color:Lerp(Color3.new(1, 1, 1), 0.08)
		end
		local model = Hex.BuildTile(tile * 0.97, SLAB, CFrame.new(origin + at - Vector3.new(0, SLAB / 2, 0)), color, nil, PIT_EDGE)
		model.Name = "Pit_" .. index
		model:SetAttribute("Ring", 0)
		model.Parent = folder
	end
	-- the core pillar, up to the summit
	local bottom = origin.Y - 40
	local coreTop = origin.Y + layout.Core.Top
	local core = Hex.BuildTile(layout.Core.Radius, coreTop - bottom, CFrame.new(0, (bottom + coreTop) / 2, 0) + flat(origin), TOP, nil, CORE_EDGE)
	core.Name = "Core"
	core:SetAttribute("Ring", 1)
	core.Parent = folder
	-- the platforms
	for id, spec in layout.Platforms do
		local model = buildPlatform(spec, origin, tiers)
		local entry = { spec = spec, model = model, template = model:Clone(), state = "Solid" }
		self.platforms[id] = entry
		model.Parent = folder
	end
	for _, chimney in layout.Chimneys do
		local from = layout.Platforms[chimney.From]
		buildChimney(chimney, origin, from.Tier).Parent = folder
	end
	-- the lava: one big glowing slab filling the pit, moved by every client from the attributes
	local lava = part(folder, Vector3.new(LAVA_THICK, World.PitRadius * 2 + 6, World.PitRadius * 2 + 6), CFrame.new(flat(origin) + Vector3.new(0, self.lavaY - LAVA_THICK / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), LAVA_COLOR, Enum.Material.Neon, "Lava")
	lava.Shape = Enum.PartType.Cylinder
	lava.CanCollide = false
	lava.CanQuery = false
	lava.CanTouch = false
	lava.CastShadow = false
	self.lava = lava

	folder:SetAttribute("Centre", origin)
	folder:SetAttribute("Tiers", tiers)
	self:SetLava(self.lavaY, 0)
	-- every client plays the tower's build-in show when this appears (Client/Systems/ArenaShow)
	folder:SetAttribute("HexArena", true)
	folder.Parent = Workspace
	return self
end

-- ═══ the lava ═════════════════════════════════════════════════════════════════════

function Tower:Lava(): number
	return self.lavaY + self.lavaRate * (now() - self.lavaAt)
end

function Tower:SetLava(y: number, rate: number)
	self.lavaY, self.lavaAt, self.lavaRate = y, now(), rate
	self.folder:SetAttribute("LavaY", y)
	self.folder:SetAttribute("LavaAt", self.lavaAt)
	self.folder:SetAttribute("LavaRate", rate)
end

-- ═══ platforms ════════════════════════════════════════════════════════════════════

function Tower:Centre(entry): Vector3
	local spec = entry.spec
	if not spec.Position then
		return self.origin -- the start ring has no one middle
	end
	local at = self.origin + spec.Position
	if spec.Mover then
		at += MeltLayout.MoverOffset(spec.Mover, now())
	end
	return at
end

local BASE = { spec = { Id = 0, Kind = "Base", Size = 0 }, state = "Solid" }
Tower.Base = BASE
local PIT = { spec = { Id = -1, Kind = "Pit", Size = 0 }, state = "Solid" }
Tower.Pit = PIT

-- The platform under a body's root (its feet about 3 studs below), or the start ring (BASE), or
-- nil in the air or off the edge.
function Tower:PlatformUnder(position: Vector3, depth: number?)
	depth = depth or 6
	local best, bestTop = nil, -math.huge
	for _, entry in self.platforms do
		if entry.state ~= "Gone" then
			local centre = self:Centre(entry)
			local above = position.Y - centre.Y
			if above > -0.5 and above < depth and centre.Y > bestTop and flat(position - centre).Magnitude < entry.spec.Size * 0.92 then
				best, bestTop = entry, centre.Y
			end
		end
	end
	if best then
		return best
	end
	local out = flat(position - self.origin).Magnitude
	local above = position.Y - self.origin.Y
	if above > -0.5 and above < depth and out > self.layout.BaseInner - 1 and out < self.layout.BaseOuter + MeltLayout.BaseTile then
		return BASE
	end
	local pitAbove = above + self.pitDrop
	if pitAbove > -0.5 and pitAbove < depth and out < self.layout.BaseInner + 2 and self:Lava() < self.origin.Y - self.pitDrop then
		return PIT
	end
	return nil
end

function Tower:Entry(id: number)
	return self.platforms[id]
end

-- Shake and flash for `warn` seconds, then fall. It comes back after `back` seconds (never, if
-- nil) unless the lava has reached it by then.
function Tower:Crumble(entry, warn: number, back: number?)
	if not entry.spec.Position or entry.state ~= "Solid" then
		return
	end
	entry.state = "Warning"
	local model = entry.model
	model:SetAttribute("Falling", true)
	Remotes.Fx("Crumble", { Position = self:Centre(entry), Size = entry.spec.Size })
	local shakeUntil = os.clock() + warn
	task.spawn(function()
		local flip = false
		local bases = {}
		for _, p in model:GetChildren() do
			if p:IsA("BasePart") then
				bases[p] = { color = p.Color, cframe = p.CFrame }
			end
		end
		while os.clock() < shakeUntil and model.Parent do
			flip = not flip
			for p, base in bases do
				p.Color = flip and WARN_COLOR or base.color
				local jitter = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 0.4
				p.CFrame = base.cframe + jitter
			end
			task.wait(shakeUntil - os.clock() < 0.3 and 0.05 or 0.1)
		end
		entry.state = "Gone"
		for p in bases do
			if p.Parent then
				p.Color = WARN_COLOR
				p.CanCollide = false
				p.Anchored = false
				p.AssemblyLinearVelocity = Vector3.new(0, -10, 0)
				p.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 3
				TweenService:Create(p, TweenInfo.new(1.3), { Transparency = 1 }):Play()
			end
		end
		Debris:AddItem(model, 1.5)
		if not back then
			return
		end
		task.wait(back)
		-- back, unless the lava has got there (or the tower has gone)
		if not self.folder.Parent or self.folder:GetAttribute("Leaving") or entry.state ~= "Gone" then
			return
		end
		if self:Lava() > self.origin.Y + entry.spec.Position.Y - 4 then
			return
		end
		local fresh = entry.template:Clone()
		fresh:SetAttribute("Respawned", true)
		entry.model = fresh
		entry.state = "Solid"
		fresh.Parent = self.folder
		Remotes.Fx("Respawn", { Position = self:Centre(entry), Size = entry.spec.Size })
	end)
end

-- The middle of a solid, still platform's top above y (the nearest above), for Second Chance.
function Tower:SafeAbove(y: number): Vector3?
	local best, bestY = nil, math.huge
	for _, entry in self.platforms do
		local top = self.origin.Y + entry.spec.Position.Y
		if entry.state == "Solid" and entry.spec.Kind ~= "Mover" and entry.spec.Kind ~= "Crumble" and top > y and top < bestY then
			best, bestY = entry, top
		end
	end
	return best and self:Centre(best) or nil
end

-- Every frame: movers move to where they are now (carrying any bot stood on them), and a crumbling
-- platform someone has landed on starts to go. `bodies`: { { model, root, bot } }.
function Tower:Step(t: number, bodies, crumbleWarn: number, crumbleBack: number)
	for _, entry in self.platforms do
		local spec = entry.spec
		if spec.Mover and entry.state == "Solid" and entry.model.Parent then
			local home = entry.model:GetAttribute("MoverHome")
			local offset = MeltLayout.MoverOffset(spec.Mover, t)
			local last = entry.lastOffset or offset
			local delta = offset - last
			entry.lastOffset = offset
			entry.model:PivotTo(home + offset)
			if delta.Magnitude > 0 then
				-- a bot standing on it (where it was) goes with it
				local top = self.origin + spec.Position + last
				for _, body in bodies do
					if body.bot then
						local above = body.root.Position.Y - top.Y
						if above > -0.5 and above < 4.5 and flat(body.root.Position - top).Magnitude < spec.Size * 0.92 then
							body.root.CFrame += delta
						end
					end
				end
			end
		end
	end
	for _, body in bodies do
		local entry = self:PlatformUnder(body.root.Position, 4)
		if entry and entry ~= BASE and entry.spec.Kind == "Crumble" and entry.state == "Solid" then
			self:Crumble(entry, crumbleWarn, crumbleBack)
		end
	end
end

-- Leaving: clients fly the pieces off (ArenaShow) and sink the lava, so it lingers a moment.
Tower.LeaveSeconds = 1.6

-- How long the build-in show takes for this tower (as HexArena.ShowSeconds: a ring every 0.2 s,
-- then the fall, bounce and a breath).
function Tower:ShowSeconds(): number
	return ringOf(self.layout.Tiers) * 0.2 + 0.16 + 0.42 + 0.2 + 0.6
end

function Tower:Destroy()
	local folder = self.folder
	for _, p in folder:GetDescendants() do
		if p:IsA("BasePart") then
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
		end
	end
	folder.Name = folder.Name .. "_Leaving"
	folder:SetAttribute("Leaving", true)
	task.delay(Tower.LeaveSeconds, function()
		folder:Destroy()
	end)
end

return Tower
