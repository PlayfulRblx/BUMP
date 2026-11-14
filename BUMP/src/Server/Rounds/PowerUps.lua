--!nonstrict
--[[
	Power-ups in a game (Shared/PowerUps/PowerUpInfo has what each one is).

	Each contestant brings one: a player their equipped one (Server/Systems/Progress), a bot a
	random one at level 1 or 2. It's used once a game: a player presses the power-up button
	(Act "PowerUp"), a bot's brain calls PowerUps.Use; Second Chance goes off by itself when its
	owner falls (the games call PowerUps.TryRescue before knocking someone out).

	    PowerUps.Arm(ctx)                 RoundServer, once everyone is placed on the arena
	    PowerUps.Disarm(ctx)              RoundServer, when the game is cleaned up
	    PowerUps.SetGame(handlers)        a game's own effects, from its Setup:
	        Turbo(participant, stats)     -> true if it dealt with it (riding a ball)
	        Shockwave(participant, at, radius)
	        Rescue(participant)           put them back on safe floor
	    PowerUps.Use(participant)         -> true if it went off
	    PowerUps.Ready(participant, id?)  -> the stats if they hold this one (any) unused
	    PowerUps.Shielded(model)          -> true while a shield is up
	    PowerUps.TryRescue(participant)   -> true if a Second Chance caught them

	What it leaves on a contestant's character: PowerAttr ("Shield:2"), UsedAttr, ShieldAttr and
	BoostAttr/BoostScaleAttr (a Turbo on foot: the platformer reads them; a bot's walk speed is
	raised here). Every use fires Fx "PowerUp" { Id, Level, Holder (the character), Position }.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local PowerUpInfo = require("@Shared/PowerUps/PowerUpInfo")
local Ragdoll = require("@Shared/Ragdoll")
local Remotes = require("@Shared/Movement/Remotes")
local RoundInfo = require("@Shared/Rounds/RoundInfo")
local BumpServer = require("@GameServer/Systems/BumpServer")
local Progress = require("@GameServer/Systems/Progress")

local PowerUps = {}

local current = nil -- the game being played: { ctx }
local handlers = {} -- its effects (SetGame), set from its Setup, before Arm

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function rootOf(model: Model?): BasePart?
	local root = model and model:FindFirstChild("HumanoidRootPart")
	return root and root:IsA("BasePart") and root or nil
end

local function playing(): boolean
	local folder = ReplicatedStorage:FindFirstChild(RoundInfo.Folder)
	return folder ~= nil and folder:GetAttribute("Phase") == "Play"
end

local function clearAttributes(character: Model?)
	if not character then
		return
	end
	character:SetAttribute(PowerUpInfo.PowerAttr, nil)
	character:SetAttribute(PowerUpInfo.UsedAttr, nil)
	character:SetAttribute(PowerUpInfo.ShieldAttr, nil)
	character:SetAttribute(PowerUpInfo.BoostAttr, nil)
	character:SetAttribute(PowerUpInfo.BoostScaleAttr, nil)
end

local function spend(participant, character: Model?, at: Vector3?)
	local power = participant.Power
	power.Used = true
	if character then
		character:SetAttribute(PowerUpInfo.UsedAttr, true)
	end
	print(string.format("[Power] %s used %s (level %d)", participant.Name, power.Id, power.Level))
	Remotes.Fx("PowerUp", { Id = power.Id, Level = power.Level, Holder = character, Position = at })
end

local function shield(character: Model, seconds: number)
	local untilTime = math.max(character:GetAttribute(PowerUpInfo.ShieldAttr) or 0, now() + seconds)
	character:SetAttribute(PowerUpInfo.ShieldAttr, untilTime)
end

-- A Turbo on foot: the platformer reads the attributes; a bot walks faster for a while.
local function boostOnFoot(participant, character: Model, stats)
	character:SetAttribute(PowerUpInfo.BoostScaleAttr, stats.Run)
	character:SetAttribute(PowerUpInfo.BoostAttr, now() + stats.Seconds)
	if participant.Bot then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local base = humanoid.WalkSpeed
			local boosted = base * stats.Run
			humanoid.WalkSpeed = boosted
			task.delay(stats.Seconds, function()
				-- unless something else has set it since (Bomber's holder speed)
				if humanoid.Parent and humanoid.WalkSpeed == boosted then
					humanoid.WalkSpeed = base
				end
			end)
		end
	end
end

function PowerUps.SetGame(gameHandlers)
	handlers = gameHandlers or {}
end

function PowerUps.Arm(ctx)
	current = { ctx = ctx }
	for _, participant in ctx.Alive() do
		local id, level
		if participant.Player then
			id, level = Progress.Equipped(participant.Player)
		else
			id = PowerUpInfo.List[math.random(#PowerUpInfo.List)]
			level = math.random(1, 2)
		end
		participant.Power = id and { Id = id, Level = level, Used = false } or nil
		local character = ctx.Character(participant)
		clearAttributes(character)
		if character and id then
			character:SetAttribute(PowerUpInfo.PowerAttr, PowerUpInfo.Encode(id, level))
			character:SetAttribute(PowerUpInfo.UsedAttr, false)
		end
	end
end

function PowerUps.Disarm(ctx)
	for _, participant in ctx.Seats do
		participant.Power = nil
		clearAttributes(ctx.Character(participant))
	end
	current = nil
	handlers = {}
end

function PowerUps.Shielded(model: Model?): boolean
	return model ~= nil and (model:GetAttribute(PowerUpInfo.ShieldAttr) or 0) > now()
end

-- The stats of the power-up they hold, if it's unused (and is `id`, if given).
function PowerUps.Ready(participant, id: string?)
	local power = participant and participant.Power
	if not power or power.Used or (id and power.Id ~= id) then
		return nil
	end
	return PowerUpInfo.Stats(power.Id, power.Level)
end

function PowerUps.Use(participant): boolean
	if not current or not participant or participant.Out or not playing() then
		return false
	end
	local power = participant.Power
	local item = power and PowerUpInfo.Get(power.Id)
	if not item or power.Used or item.Automatic then
		return false
	end
	local character = current.ctx.Character(participant)
	local root = rootOf(character)
	if not root then
		return false
	end
	-- flat on your back you can still throw up a shield, nothing else
	if Ragdoll.IsDown(character) and power.Id ~= "Shield" then
		return false
	end
	local stats = PowerUpInfo.Stats(power.Id, power.Level)
	if power.Id == "Shield" then
		shield(character, stats.Seconds)
	elseif power.Id == "Turbo" then
		if not (handlers.Turbo and handlers.Turbo(participant, stats)) then
			boostOnFoot(participant, character, stats)
		end
	elseif power.Id == "Shockwave" then
		if handlers.Shockwave then
			handlers.Shockwave(participant, root.Position, stats.Radius)
		end
	end
	spend(participant, character, root.Position)
	return true
end

-- Someone has fallen off: if they hold an unused Second Chance, it puts them back.
function PowerUps.TryRescue(participant): boolean
	if not current or not handlers.Rescue then
		return false
	end
	local stats = PowerUps.Ready(participant, "SecondChance")
	if not stats then
		return false
	end
	local character = current.ctx.Character(participant)
	if not character then
		return false
	end
	handlers.Rescue(participant)
	if stats.Shield > 0 then
		shield(character, stats.Shield)
	end
	local root = rootOf(character)
	spend(participant, character, root and root.Position)
	return true
end

local function onUse(player: Player)
	if not current then
		return
	end
	local id = tostring(player.UserId)
	for _, participant in current.ctx.Seats do
		if participant.Id == id then
			PowerUps.Use(participant)
			return
		end
	end
end

function PowerUps.Init()
	BumpServer.OnAct("PowerUp", onUse)
end

return PowerUps
