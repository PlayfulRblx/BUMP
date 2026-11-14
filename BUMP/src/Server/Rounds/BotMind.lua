--!nonstrict
--[[
	What every bot shares, whichever game it plays: a personality and a skill, and the floor
	sense the games' brains use to stay alive.

	The user (2026-11-13): "Let's get 4 more AIs in and improve the AI massively"; what was wrong:
	bots "die stupidly", are "too passive / predictable" and have "no personality".

	Each bot is dealt a mind for the whole session (BotMind.Assign, from RoundServer):
	    Style      Bully (goes for people, players most, charges head-on), Opportunist (hangs
	               back, then pounces on whoever is wobbling or near an edge), Coward (keeps
	               away, dodges, shields, hides behind others from the bomb) or Wildcard (a bit
	               of everything, at random, with feints)
	    Skill      0.55 to 0.95: how far ahead it looks for holes, how well it aims and leads,
	               how sure its dodges are
	    Reaction   seconds between its decisions (quicker with skill)
	    plus the style's leanings: Aggro, Caution, Dodge, Steal, EdgeBias, WobbleBias,
	    HumanBias, Random
	A session deals the styles round so a game has a mix.

	    BotMind.Assign(seats)                      gives every bot seat a Mind
	    BotMind.Of(participant)                    its Mind (a middling one if it has none)
	    BotMind.Think(brain, mind)                 true when it's time for its next decision
	    BotMind.HoleDistance(arena, at, max)       how far to the nearest missing floor, and which way
	    BotMind.PathClear(arena, from, dir, dist)  floor all along a straight line
	    BotMind.Wobble(dir, mind)                  a direction off by its aim error
	    BotMind.PickTarget(brain, mind, candidates, score, distanceTo)
	                                               who to go after (below)

	Targets (the user, 2026-11-14: bots "seem to run back after me as the closest target ... almost
	randomise their targets", and "update their targets based on changing factors like distance to
	other targets and aggro"): each game scores the candidates its own way (distance, cornered,
	players, its style's leanings); PickTarget adds what every bot weighs the same way: a whim per
	target that changes every few seconds (so bots, and one bot over time, pick differently), staying
	with the current target unless another is clearly better as things change, and giving up for a
	while on one it has chased without closing in.
]]

local BotMind = {}

BotMind.Styles = {
	Bully = { Aggro = 0.95, Caution = 0.45, Dodge = 0.35, Steal = 0.9, EdgeBias = 0.6, WobbleBias = 0.8, HumanBias = 1.2, Random = 0.3, Counter = true },
	Opportunist = { Aggro = 0.6, Caution = 0.7, Dodge = 0.65, Steal = 0.7, EdgeBias = 1.6, WobbleBias = 1.6, HumanBias = 0.3, Random = 0.3 },
	Coward = { Aggro = 0.3, Caution = 0.95, Dodge = 0.9, Steal = 0.35, EdgeBias = 1.2, WobbleBias = 1.2, HumanBias = 0, Random = 0.2, Hides = true },
	Wildcard = { Aggro = 0.75, Caution = 0.55, Dodge = 0.55, Steal = 0.8, EdgeBias = 0.8, WobbleBias = 0.8, HumanBias = 0.5, Random = 1.4, Feints = true },
}
local ORDER = { "Bully", "Opportunist", "Coward", "Wildcard" }

local DIRECTIONS = {}
for index = 0, 11 do
	local angle = index / 12 * math.pi * 2
	table.insert(DIRECTIONS, Vector3.new(math.cos(angle), 0, math.sin(angle)))
end

local function make(styleName: string, skill: number)
	local style = BotMind.Styles[styleName]
	local mind = table.clone(style)
	mind.Style = styleName
	mind.Skill = skill
	mind.Reaction = 0.4 - 0.26 * skill + math.random() * 0.06
	mind.AimError = math.rad(14) * (1 - skill)
	return mind
end

function BotMind.Assign(seats)
	local offset = math.random(0, #ORDER - 1)
	local index = 0
	for _, participant in seats do
		if participant.Bot then
			index += 1
			local styleName = ORDER[(index + offset) % #ORDER + 1]
			participant.Mind = make(styleName, 0.55 + math.random() * 0.4)
			print(string.format("[Bots] %s: %s, skill %.2f, reacts in %.2f s", participant.Name, styleName, participant.Mind.Skill, participant.Mind.Reaction))
		end
	end
end

local fallback = nil
function BotMind.Of(participant)
	if participant.Mind then
		return participant.Mind
	end
	fallback = fallback or make("Opportunist", 0.7)
	return fallback
end

function BotMind.Think(brain, mind): boolean
	local clock = os.clock()
	if clock < (brain.thinkAt or 0) then
		return false
	end
	brain.thinkAt = clock + mind.Reaction * (0.8 + math.random() * 0.4)
	return true
end

-- How far it is (up to `max` studs) to floor that won't hold, the nearest of twelve directions
-- sampled every `step`, and which way. (max, nil) if there's none that close.
function BotMind.HoleDistance(arena, at: Vector3, max: number, step: number?): (number, Vector3?)
	step = step or 3
	local best, bestDirection = max, nil
	for _, direction in DIRECTIONS do
		local distance = step
		while distance < best do
			if not arena:FloorAt(at + direction * distance) then
				best, bestDirection = distance, direction
				break
			end
			distance += step
		end
	end
	return best, bestDirection
end

-- Floor that will hold all along the line from `from`, `distance` studs that way.
function BotMind.PathClear(arena, from: Vector3, direction: Vector3, distance: number, step: number?): boolean
	if direction.Magnitude < 0.01 then
		return arena:FloorAt(from)
	end
	direction = Vector3.new(direction.X, 0, direction.Z).Unit
	step = step or 3
	local travelled = 0
	while travelled <= distance do
		if not arena:FloorAt(from + direction * travelled) then
			return false
		end
		travelled += step
	end
	return arena:FloorAt(from + direction * distance)
end

local WHIM_MIN, WHIM_MAX = 2, 4.5 -- seconds a bot's whims last before they're dealt again
local WHIM_SIZE = 1.5 -- how much a whim can add to a target's score (times 0.6 + the style's Random)
local SWITCH_MARGIN = 0.5 -- another target has to beat the current one by this much
local FED_UP_AFTER = 4 -- seconds chasing without getting 3 studs closer (plus up to 2 for skill)
local FED_UP_FOR = 3 -- and then that target is left alone this long (plus up to 3)

-- Who to go after. `score(candidate)` is the game's own score, nil for "not a candidate";
-- `distanceTo(candidate)` how far they are (for giving up on a chase). Returns a candidate or nil.
function BotMind.PickTarget(brain, mind, candidates, score, distanceTo)
	local clock = os.clock()
	brain.whims = brain.whims or {}
	brain.fedUp = brain.fedUp or {}
	if clock >= (brain.whimAt or 0) then
		brain.whimAt = clock + WHIM_MIN + math.random() * (WHIM_MAX - WHIM_MIN)
		table.clear(brain.whims)
	end
	-- a chase that isn't closing in: give up on them for a while
	local current = brain.target
	local currentDistance = current and distanceTo(current)
	if currentDistance then
		local chase = brain.chase
		if not chase or chase.target ~= current then
			brain.chase = { target = current, since = clock, best = currentDistance }
		elseif currentDistance < chase.best - 3 then
			chase.best, chase.since = currentDistance, clock
		elseif clock - chase.since > FED_UP_AFTER + mind.Skill * 2 then
			brain.fedUp[current] = clock + FED_UP_FOR + math.random() * 3
			brain.chase = nil
		end
	end
	local best, bestScore, currentScore = nil, -math.huge, nil
	for _, candidate in candidates do
		local base = (brain.fedUp[candidate] or 0) < clock and score(candidate)
		if base then
			local whim = brain.whims[candidate]
			if not whim then
				whim = math.random() * WHIM_SIZE
				brain.whims[candidate] = whim
			end
			local total = base + whim * (0.6 + mind.Random)
			if candidate == current then
				currentScore = total
			end
			if total > bestScore then
				best, bestScore = candidate, total
			end
		end
	end
	if currentScore and best ~= current and bestScore < currentScore + SWITCH_MARGIN then
		return current, currentScore
	end
	if not best and next(brain.fedUp) then
		-- fed up with everyone left: start afresh
		table.clear(brain.fedUp)
		return BotMind.PickTarget(brain, mind, candidates, score, distanceTo)
	end
	return best, bestScore
end

-- A flat direction turned by up to the mind's aim error.
function BotMind.Wobble(direction: Vector3, mind): Vector3
	if direction.Magnitude < 0.01 or mind.AimError <= 0 then
		return direction
	end
	local angle = (math.random() * 2 - 1) * mind.AimError
	local c, s = math.cos(angle), math.sin(angle)
	return Vector3.new(direction.X * c - direction.Z * s, 0, direction.X * s + direction.Z * c)
end

return BotMind
