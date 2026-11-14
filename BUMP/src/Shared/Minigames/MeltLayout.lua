--!nonstrict
--[[
	MELTDOWN's tower, as data: where every platform, pad and chimney goes, made from a seed so the
	server builds it and a spec can check it without a single part. Positions are relative to the
	arena's origin (World.ArenaOrigin), each platform's at the middle of its top.

	    local layout = MeltLayout.Build(seed, options)  -- options: Tiers, TierGap, BaseInner, BaseOuter, BounceHeight
	    layout.Base        { Vector3 }: the start ring's hex tile centres (tile corner radius BaseTile)
	    layout.Pit         { Vector3 }: the pit floor's under the tower, PitDrop below the ring
	    layout.Platforms   { [id] = { Id, Tier, Position, Size (corner radius), Kind, Mover?, Pad?, Links } }
	                       Kind "Solid" | "Crumble" | "Mover" | "Summit"
	                       Mover { Axis, Amp, Period, Phase }: slides along Axis (MeltLayout.MoverOffset)
	                       Pad { Height, To }: a bounce pad on its top, aimed at platform To
	                       Links { { To, Kind = "Jump" | "Pad" | "Chimney" } }: where a bot can get to from here
	    layout.Chimneys    { { Position (bottom middle), Height, Across (unit, wall to wall), Gap, From, To } }
	    layout.StartLinks  ids reachable from the base
	    layout.Summit      the summit's id
	    layout.Core        { Radius, Top }: the pillar up the middle

	The tower climbs round a core pillar in tiers (TierGap apart), wide and many at the bottom, few
	and close in at the top, each tier turned half a step against the one below, so no platform
	sits right on top of the next one up. A bot's jump (MeltBots) reaches 9 studs up and 9 across
	(edge to edge); a player's reach is a lot more (float jump, long jump), so they find shortcuts.
	The layout is rebuilt from the next seed until the summit can be reached from the base.
]]

local Hex = require("@Shared/Minigames/Hex")

local MeltLayout = {}

MeltLayout.BaseTile = 7
MeltLayout.CoreRadius = 8
MeltLayout.SummitSize = 9
MeltLayout.ChimneyHeight = 30
MeltLayout.ChimneyGap = 8 -- wall to wall
MeltLayout.ChimneyWidth = 8
MeltLayout.JumpUp = 9 -- a bot's jump: this far up
MeltLayout.JumpDown = 14 -- or down
MeltLayout.JumpAcross = 14 -- and this far across, edge to edge (a float jump goes much further)
MeltLayout.HeadClear = 17 -- no platform overlaps another this close above or below it
MeltLayout.HeadMargin = 2 -- by at least this, edge to edge (corner radii)
MeltLayout.StartAcross = 16 -- the first leap, off the start ring onto the tower, can be this far
local BAND = 5 -- the inner and outer rings are this far either side of the tier's middle
local INNER = 0.866 -- a hex's flat side is this share of its corner radius

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- How far apart two platforms' edges are, flat (negative when they overlap).
local function gap(a, b): number
	return flat(a.Position - b.Position).Magnitude - INNER * (a.Size + b.Size)
end

function MeltLayout.Gap(a, b): number
	return gap(a, b)
end

-- Whether a bot can jump from platform a to platform b.
function MeltLayout.CanJump(a, b): boolean
	local dy = b.Position.Y - a.Position.Y
	return dy <= MeltLayout.JumpUp and dy >= -MeltLayout.JumpDown and gap(a, b) <= MeltLayout.JumpAcross
end

-- A mover's offset from its home at time t (server time, so every machine agrees).
function MeltLayout.MoverOffset(mover, t: number): Vector3
	return mover.Axis * (mover.Amp * math.sin(2 * math.pi * t / mover.Period + mover.Phase))
end

function MeltLayout.MoverVelocity(mover, t: number): Vector3
	local w = 2 * math.pi / mover.Period
	return mover.Axis * (mover.Amp * w * math.cos(w * t + mover.Phase))
end

-- The places a platform can be over its travel (a mover's ends and middle).
local function sweep(spec): { Vector3 }
	if not spec.Mover then
		return { spec.Position }
	end
	local reach = spec.Mover.Axis * spec.Mover.Amp
	return { spec.Position - reach, spec.Position, spec.Position + reach }
end

-- Whether `spec` fits among `placed`: nobody's head hits the platform above (anything within
-- HEAD_CLEAR up or down must be clear by HEAD_MARGIN: a float jump rises about 14 studs, so two
-- tiers), and a tier's platforms keep room between them. (The user, 2026-11-14: "the platforms of
-- the tower should be spread out a bit more. Make the player utilise their float jump and less
-- likely to bang their heads on platforms that are directly above each other".)
local function fits(spec, placed): boolean
	for _, other in placed do
		local dy = math.abs(other.Position.Y - spec.Position.Y)
		if dy < MeltLayout.HeadClear then
			local need = dy < 0.5 and (spec.Size + other.Size + 8) or (spec.Size + other.Size + MeltLayout.HeadMargin)
			for _, a in sweep(spec) do
				for _, b in sweep(other) do
					if flat(a - b).Magnitude < need then
						return false
					end
				end
			end
		end
	end
	return true
end

local function link(layout)
	for _, platform in layout.Platforms do
		platform.Links = {}
	end
	for _, a in layout.Platforms do
		for _, b in layout.Platforms do
			if a ~= b and a.Kind ~= "Summit" and MeltLayout.CanJump(a, b) then
				table.insert(a.Links, { To = b.Id, Kind = "Jump" })
			end
		end
		if a.Pad then
			table.insert(a.Links, { To = a.Pad.To, Kind = "Pad" })
		end
	end
	for _, chimney in layout.Chimneys do
		table.insert(layout.Platforms[chimney.From].Links, { To = chimney.To, Kind = "Chimney" })
	end
	layout.StartLinks = {}
	for _, platform in layout.Platforms do
		local out = flat(platform.Position).Magnitude + INNER * platform.Size
		if platform.Position.Y <= MeltLayout.JumpUp and layout.BaseInner - out <= MeltLayout.StartAcross then
			table.insert(layout.StartLinks, platform.Id)
		end
	end
end

-- Whether the summit can be reached from the base, link by link.
function MeltLayout.SummitReachable(layout): boolean
	local seen, queue = {}, {}
	for _, id in layout.StartLinks do
		seen[id] = true
		table.insert(queue, id)
	end
	while #queue > 0 do
		local id = table.remove(queue, 1)
		if id == layout.Summit then
			return true
		end
		for _, edge in layout.Platforms[id].Links do
			if not seen[edge.To] then
				seen[edge.To] = true
				table.insert(queue, edge.To)
			end
		end
	end
	return false
end

-- The platforms in the way of a column rising `height` from `at`, `clear` studs round it.
local function blockers(layout, at: Vector3, height: number, clear: number, except)
	local list = {}
	for _, platform in layout.Platforms do
		if not except[platform.Id] then
			local dy = platform.Position.Y - at.Y
			if dy > 0.5 and dy <= height then
				for _, place in sweep(platform) do
					if flat(place - at).Magnitude < platform.Size + clear then
						table.insert(list, platform)
						break
					end
				end
			end
		end
	end
	return list
end

-- Takes `list` out of the tower if the summit can still be reached without them (true), else
-- leaves everything as it was.
local function tryRemove(layout, list): boolean
	if #list == 0 then
		return true
	end
	if #list > 3 then
		return false
	end
	-- never one a pad or a chimney already leads to or from
	local used = {}
	for _, platform in layout.Platforms do
		if platform.Pad then
			used[platform.Id] = true
			used[platform.Pad.To] = true
		end
	end
	for _, chimney in layout.Chimneys do
		used[chimney.From] = true
		used[chimney.To] = true
	end
	for _, platform in list do
		if platform.Kind == "Summit" or used[platform.Id] then
			return false
		end
	end
	for _, platform in list do
		layout.Platforms[platform.Id] = nil
	end
	link(layout)
	if MeltLayout.SummitReachable(layout) then
		return true
	end
	for _, platform in list do
		layout.Platforms[platform.Id] = platform
	end
	link(layout)
	return false
end

local function attempt(seed: number, options, keepAnyway: boolean?)
	local rng = Random.new(seed)
	local tiers, tierGap = options.Tiers, options.TierGap
	local layout = {
		Seed = seed,
		Tiers = tiers,
		TierGap = tierGap,
		BaseInner = options.BaseInner,
		BaseOuter = options.BaseOuter,
		Base = {},
		Pit = {},
		Platforms = {},
		Chimneys = {},
		Core = { Radius = MeltLayout.CoreRadius, Top = tiers * tierGap - 2.5 },
	}
	-- the start ring
	local rings = math.ceil(options.BaseOuter / (MeltLayout.BaseTile * 1.5)) + 1
	for _, tile in Hex.Tiles(rings) do
		local at = Hex.Position(tile.q, tile.r, MeltLayout.BaseTile)
		local distance = at.Magnitude
		-- tiles poking in to BaseInner at most (half a tile in from their middles): taking only
		-- whole tiles past it left notches up to 10 studs deep in the inner edge, which bots walked
		-- into
		if distance - MeltLayout.BaseTile * 0.5 >= options.BaseInner and distance <= options.BaseOuter then
			table.insert(layout.Base, at)
		end
		-- the pit's floor: everywhere inside the ring (and a little under it), round the core
		if distance <= options.BaseInner + MeltLayout.BaseTile and distance > MeltLayout.CoreRadius then
			table.insert(layout.Pit, at - Vector3.new(0, options.PitDrop or 10, 0))
		end
	end

	-- the tiers
	local placed = {}
	local nextId = 0
	local offset = rng:NextNumber(0, math.pi * 2)
	for tier = 1, tiers - 1 do
		local u = (tier - 1) / math.max(tiers - 2, 1)
		local count = 5 -- the same on every tier, so the turn a tier makes always means the same
		local size = 6.5 - 1.5 * u
		-- tiers alternate between an inner and an outer ring, a third of a step round from the one
		-- below: a platform is well clear of the two tiers over it (a float jump's reach) and lines
		-- up again only three tiers up, while the next tier stays a jump away, in and up or out and up
		local middle = 37 - 14 * u + (tier % 2 == 1 and -BAND or BAND)
		offset += 2 * math.pi / count / 3 + rng:NextNumber(-0.1, 0.1)
		for index = 0, count - 1 do
			local kind = "Solid"
			if tier >= 3 and tier <= tiers - 3 then
				local roll = rng:NextNumber()
				kind = roll < 0.2 and "Crumble" or roll < 0.34 and "Mover" or "Solid"
			end
			for try = 0, 6 do
				local angle = offset + index * 2 * math.pi / count + rng:NextNumber(-0.12, 0.12) + (try > 0 and rng:NextNumber(-0.3, 0.3) or 0)
				local radius = math.max(middle + rng:NextNumber(-2, 2), MeltLayout.CoreRadius + size + 3)
				if tier >= tiers - 2 then
					-- clear of the summit's underside too (it's wider than the core)
					radius = math.max(radius, MeltLayout.SummitSize + size + 2.6)
				end
				local spec = {
					Tier = tier,
					Position = Vector3.new(math.cos(angle) * radius, tier * tierGap, math.sin(angle) * radius),
					Size = size + rng:NextNumber(-0.5, 0.5),
					Kind = kind,
				}
				if kind == "Mover" then
					spec.Mover = {
						-- along its ring (out and in would cross into the next ring's way)
						Axis = Vector3.new(-math.sin(angle), 0, math.cos(angle)),
						Amp = 4,
						Period = rng:NextNumber(4, 6),
						Phase = rng:NextNumber(0, math.pi * 2),
					}
				end
				if fits(spec, placed) then
					nextId += 1
					spec.Id = nextId
					layout.Platforms[nextId] = spec
					table.insert(placed, spec)
					break
				end
			end
		end
	end
	-- the summit, on top of the core
	nextId += 1
	layout.Summit = nextId
	layout.Platforms[nextId] = {
		Id = nextId,
		Tier = tiers,
		Position = Vector3.new(0, tiers * tierGap, 0),
		Size = MeltLayout.SummitSize,
		Kind = "Summit",
	}
	link(layout)
	if not MeltLayout.SummitReachable(layout) then
		return keepAnyway and layout or nil
	end

	-- bounce pads: on a solid platform with a clear column above, aimed at a platform 3 to 5 tiers up
	local candidates = {}
	for _, platform in layout.Platforms do
		if platform.Kind == "Solid" and platform.Tier >= 2 and platform.Tier <= tiers - 6 then
			table.insert(candidates, platform)
		end
	end
	table.sort(candidates, function(a, b)
		return a.Id < b.Id
	end)
	local pads = 0
	while #candidates > 0 and pads < 4 do
		local platform = table.remove(candidates, rng:NextInteger(1, #candidates))
		if layout.Platforms[platform.Id] then
			local landing = nil
			for _, other in layout.Platforms do
				local dy = other.Position.Y - platform.Position.Y
				local across = flat(other.Position - platform.Position).Magnitude
				if (other.Kind == "Solid" or other.Kind == "Summit") and dy >= 2.5 * tierGap and dy <= options.BounceHeight - 2
					and across >= INNER * other.Size + 2 and across <= 16 then
					landing = other
					break
				end
			end
			if landing then
				local inWay = blockers(layout, platform.Position, options.BounceHeight + 3, 3, { [platform.Id] = true, [landing.Id] = true })
				if tryRemove(layout, inWay) then
					platform.Pad = { Height = options.BounceHeight, To = landing.Id }
					pads += 1
					link(layout)
				end
			end
		end
	end

	-- chimneys: two facing walls standing on a solid platform, out to a platform near their top
	candidates = {}
	for _, platform in layout.Platforms do
		if platform.Kind == "Solid" and not platform.Pad and platform.Size >= 5 and platform.Tier >= 3 and platform.Tier <= tiers - 8 then
			table.insert(candidates, platform)
		end
	end
	table.sort(candidates, function(a, b)
		return a.Id < b.Id
	end)
	local height = MeltLayout.ChimneyHeight
	while #candidates > 0 and #layout.Chimneys < 3 do
		local platform = table.remove(candidates, rng:NextInteger(1, #candidates))
		if layout.Platforms[platform.Id] then
			local exit = nil
			for _, other in layout.Platforms do
				local dy = other.Position.Y - platform.Position.Y
				local across = flat(other.Position - platform.Position).Magnitude
				if (other.Kind == "Solid" or other.Kind == "Summit") and dy >= height - 4 and dy <= height + 4 and across >= 8 and across <= 15 then
					exit = other
					break
				end
			end
			local spread = false
			for _, chimney in layout.Chimneys do
				if math.abs(chimney.Position.Y - platform.Position.Y) < height then
					spread = true -- one at a time up the tower
				end
			end
			if exit and not spread then
				local inWay = blockers(layout, platform.Position, height, 6.5, { [platform.Id] = true, [exit.Id] = true })
				if tryRemove(layout, inWay) then
					local out = flat(platform.Position).Unit
					table.insert(layout.Chimneys, {
						Position = platform.Position,
						Height = height,
						Across = Vector3.new(-out.Z, 0, out.X),
						Gap = MeltLayout.ChimneyGap,
						From = platform.Id,
						To = exit.Id,
					})
					link(layout)
				end
			end
		end
	end
	link(layout)
	if not MeltLayout.SummitReachable(layout) then
		return nil
	end
	return layout
end

-- One try at a seed (nil if its summit can't be reached), for looking into a layout.
MeltLayout.Attempt = attempt

function MeltLayout.Build(seed: number, options)
	for try = 0, 40 do
		local layout = attempt(seed + try * 7919, options)
		if layout then
			return layout
		end
	end
	error("MeltLayout: no climbable tower from seed " .. tostring(seed))
end

return MeltLayout
