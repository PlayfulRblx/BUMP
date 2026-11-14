--!nonstrict
--[[
	A game's intro, the camera part (the user, 2026-11-13: "a nice AAA ADHD nintendo level intro
	with title card and camera pan over along with some intro music into a 3 - 2 - 1 countdown";
	their choices: sweep the arena, then glide along the contestants with names popping up, ending
	behind you; about 7 s, then 8.5 s to give you your own moment).

	When the round's phase turns to Intro, every client (contestants and anyone watching) flies the
	camera on one of the engine's camera layers (CameraService:AddLayer with KeepBaseCamera, so the
	gameplay camera is where it was underneath), timed off the phase's EndsAt so every screen agrees:

	    0 to OTHERS_END          one unbroken flight (the user: "the camera should fly in smoothly
	                             past all the characters before settling on the player"): a wide
	                             orbit high over the new arena that dives into the ring and flies on
	                             round it past each of the other contestants in turn, ending at you;
	                             each one's name pops up beside them in their seat colour as the
	                             camera reaches them. It's a curve through timed points (`along`), so
	                             it never stops or turns a corner between them
	    OTHERS_END to HERO_END   your moment (the user: the intro "should take a little bit longer
	                             when showing the final player, which is the player's character
	                             itself"): the flight slows into an orbit round you, pushing in,
	                             while you strike the HeroPose, your spotlight flares, and your name
	                             slams across the screen (HudHero, cued by RoundClient's IntroHero)
	    HERO_END to OUT_END      the layer fades out into the gameplay camera behind you
	    then                     the countdown (HudCountdown) on the normal camera
	Someone watching (not in the game) gets the flight past everyone, ending high over the arena.

	The title card, letterbox and countdown are the HUD's (HudIntro, HudLetterbox, HudCountdown);
	the sting and beeps BumpMusic's. The layer is removed on any phase change, respawn or error,
	so the camera can't be left stuck.
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CameraHandlerClient = require("@Engine/Client/EngineSystems/CameraHandler/CameraHandlerClient")
local CameraState = require("@Engine/Client/EngineSystems/CameraHandler/Camera/CameraState")
local BumpSounds = require("@Shared/Audio/BumpSounds")
local BumpFx = require("@Client/Systems/BumpFx")
local Platformer = require("@Client/Systems/Platformer")
local RoundClient = require("@Client/Systems/RoundClient")
local RoundInfo = require("@Shared/Rounds/RoundInfo")
local Tuning = require("@Shared/Movement/Tuning")
local World = require("@Shared/World")

local Rounds = Tuning.Of("Rounds")

local RoundIntro = {}

-- (doubled 2026-11-14, the user: "the intro cutscene should take twice as long"; were 1.3,
-- 1.75 to 3.05, 3.4, 5.0, 5.5)
local SWEEP_END = 2.6 -- the orbit high over the arena ends and the dive into the ring begins
local FLY_FIRST, FLY_LAST = 3.5, 6.1 -- passing the first and the last of the others
local OTHERS_END = 6.8 -- arriving at you
local HERO_END = 10.0
local OUT_END = 11.0
local SWEEP_FOV, FLY_FOV, HERO_FOV = 80, 56, 46
local PASS_IN, PASS_UP = 16, 4 -- the camera passes each contestant this far inside the ring, and up (10 whipped the view round past them)
local AIM_LAG = 0.14 -- seconds the camera's aim trails the point it's after, so passing someone close never whips it round
local HERO_FROM, HERO_TO = math.rad(-50), math.rad(50) -- the orbit round you, from your left front across your face (wider since the shot got longer)
local HERO_FAR, HERO_NEAR = 16, 11 -- the push-in's distance (closer hid your head behind the raised fist)
local FLARE_BRIGHTNESS = 18
local LAYER_PRIORITY = 50
local NAME_FONT = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local INK = Color3.fromRGB(20, 18, 30)

local player = Players.LocalPlayer
local running = nil -- { layer, pops = {}, serial }
local serial = 0

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Where on a curve through `keys` ({ t, v }, in time order; v a Vector3 or a number) we are at
-- time t: it passes each v at its t, with no stops or corners between (Catmull-Rom in Barry and
-- Goldman's form, so uneven gaps in time don't kink it). Past either end it holds.
local function along(keys, t: number)
	local n = #keys
	if t <= keys[1].t then
		return keys[1].v
	elseif t >= keys[n].t then
		return keys[n].v
	end
	local i = 1
	while keys[i + 1].t < t do
		i += 1
	end
	local k1, k2 = keys[i], keys[i + 1]
	local k0 = keys[i - 1] or { t = 2 * k1.t - k2.t, v = k1.v * 2 - k2.v }
	local k3 = keys[i + 2] or { t = 2 * k2.t - k1.t, v = k2.v * 2 - k1.v }
	local function mix(a, b, ta, tb)
		return a * ((tb - t) / (tb - ta)) + b * ((t - ta) / (tb - ta))
	end
	local a1 = mix(k0.v, k1.v, k0.t, k1.t)
	local a2 = mix(k1.v, k2.v, k1.t, k2.t)
	local a3 = mix(k2.v, k3.v, k2.t, k3.t)
	return mix(mix(a1, a2, k0.t, k2.t), mix(a2, a3, k1.t, k3.t), k1.t, k2.t)
end

-- A body's angle round the arena's middle.
local function angleOf(model: Model): number
	local root = model:FindFirstChild("HumanoidRootPart")
	local offset = root and flat(root.Position - World.ArenaOrigin) or Vector3.new(1, 0, 0)
	return math.atan2(offset.Z, offset.X)
end

local function folder(): Instance?
	return ReplicatedStorage:FindFirstChild(RoundInfo.Folder)
end

-- How far into the intro we are, by the server's clock.
local function elapsed(): number
	local round = folder()
	local endsAt = round and round:GetAttribute("EndsAt") or 0
	return Rounds.Intro - (endsAt - Workspace:GetServerTimeNow())
end

-- The arena coming in: its radius in studs (from the furthest tile out).
local function arenaRadius(): number
	local best = 60
	for _, child in Workspace:GetChildren() do
		if child:GetAttribute("HexArena") ~= nil and not child:GetAttribute("Leaving") then
			for _, tile in child:GetChildren() do
				if tile:IsA("Model") then
					local offset = flat(tile:GetPivot().Position - World.ArenaOrigin).Magnitude
					best = math.max(best, offset + 6)
				end
			end
		end
	end
	return best
end

-- Everyone else in the game round the ring by angle, starting just past you, and you:
-- ({ { model, name, seat } }, mine or nil).
local function contestants()
	local round = folder()
	local ok, list = pcall(HttpService.JSONDecode, HttpService, round and round:GetAttribute("Players") or "[]")
	if not ok or type(list) ~= "table" then
		return {}, nil
	end
	local bots = {}
	for _, model in CollectionService:GetTagged("BumpBot") do
		local id = model:GetAttribute(RoundInfo.IdAttr)
		if id then
			bots[id] = model
		end
	end
	local out, mine = {}, nil
	for _, entry in list do
		if not entry.Out then
			local model
			if entry.UserId then
				local who = Players:GetPlayerByUserId(entry.UserId)
				model = who and who.Character
			else
				model = bots[entry.Id]
			end
			if model then
				local item = { model = model, name = entry.Name, seat = entry.Seat, you = entry.UserId == player.UserId }
				if item.you then
					mine = item
				else
					table.insert(out, item)
				end
			end
		end
	end
	local function angle(item)
		return angleOf(item.model)
	end
	table.sort(out, function(a, b)
		return angle(a) < angle(b)
	end)
	-- start round the ring from just past you, so the glide ends where you are
	if mine then
		local mineAngle = angle(mine)
		local rotated = {}
		for _, item in out do
			if angle(item) > mineAngle then
				table.insert(rotated, item)
			end
		end
		for _, item in out do
			if angle(item) <= mineAngle then
				table.insert(rotated, item)
			end
		end
		out = rotated
	end
	return out, mine
end

-- A name popping up over a contestant in their seat colour.
local function popName(item)
	local head = item.model:FindFirstChild("Head") or item.model:FindFirstChild("HumanoidRootPart")
	if not head then
		return nil
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "BumpIntroName"
	gui.Size = UDim2.fromOffset(240, 70)
	-- beside them on screen (above the head is out of the lineup's frame)
	gui.StudsOffset = Vector3.new(4.2, 0.6, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 600
	gui.Adornee = head
	local color = RoundInfo.SeatColors[item.seat or 0] or Color3.new(1, 1, 1)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0.7, 0)
	label.BackgroundTransparency = 1
	label.Text = string.upper(item.name or "")
	label.FontFace = NAME_FONT
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeColor3 = INK
	label.TextStrokeTransparency = 0
	label.Rotation = math.random(-6, 6)
	label.Parent = gui
	if item.you then
		local tag = Instance.new("TextLabel")
		tag.Position = UDim2.fromScale(0, 0.68)
		tag.Size = UDim2.new(1, 0, 0.32, 0)
		tag.BackgroundTransparency = 1
		tag.Text = "YOU"
		tag.FontFace = NAME_FONT
		tag.TextScaled = true
		tag.TextColor3 = Color3.new(1, 1, 1)
		tag.TextStrokeColor3 = INK
		tag.TextStrokeTransparency = 0
		tag.Parent = gui
	end
	local scale = Instance.new("UIScale")
	scale.Scale = 0.2
	scale.Parent = gui:FindFirstChildOfClass("TextLabel")
	gui.Parent = head
	TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	local holder = Instance.new("Attachment")
	holder.Parent = head
	local pop = Instance.new("Sound")
	pop.SoundId = BumpSounds.Pop
	pop.Volume = 0.35
	pop.PlaybackSpeed = 1.3 + math.random() * 0.2
	pop.Parent = holder
	pop:Play()
	Debris:AddItem(holder, 1.5)
	return gui
end

local function stop()
	if not running then
		return
	end
	local current = running
	running = nil
	RoundClient.Set("IntroHero", false)
	if current.layer then
		pcall(function()
			current.layer:remove()
		end)
	end
	for _, gui in current.pops do
		if gui.Parent then
			local label = gui:FindFirstChildOfClass("TextLabel")
			if label then
				TweenService:Create(label, TweenInfo.new(0.25), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			end
			Debris:AddItem(gui, 0.3)
		end
	end
end

local function begin()
	stop()
	serial += 1
	local mine = serial
	local service = CameraHandlerClient.getService()
	if not service then
		return
	end
	local radius = arenaRadius()
	local centre = World.ArenaOrigin
	local startAngle = nil -- set by the first build so the orbit ends heading for the first contestant
	local path = nil -- { cam, look (keys for along), pops = { { t, item } }, builds }
	local cast, me = {}, nil -- the others and you
	local fading = false
	local aimNow = nil -- where the camera is really looking, trailing the aim (AIM_LAG)
	running = { pops = {}, serial = mine }

	local function trail(aim: Vector3, dt: number): Vector3
		if not aimNow or (aim - aimNow).Magnitude > 200 then
			aimNow = aim
		else
			aimNow = aimNow:Lerp(aim, 1 - math.exp(-math.max(tonumber(dt) or 1 / 60, 0) / AIM_LAG))
		end
		return aimNow
	end

	-- the opening orbit, s from 0 to 1: wide and high inside the pit (from further out the lobby's
	-- buildings cut into the shot), coming down and in
	local function orbit(s: number): Vector3
		local angle = startAngle + s * math.rad(110)
		local far = math.min(radius * 1.25, World.PitRadius * 0.92)
		local distance = far + (radius * 0.75 - far) * s
		local high = math.max(radius * 0.85, 75)
		local height = high + (radius * 0.35 - high) * s
		return centre + Vector3.new(math.cos(angle) * distance, height, math.sin(angle) * distance)
	end

	-- the camera on you, u from 0 to 1: orbiting from your left front across your face, pushing in
	-- and sinking, slowing to rest (the flight arrives moving). Returns (position, aim).
	local function heroShot(item, u: number): (Vector3?, Vector3?)
		local root = item.model.Parent and item.model:FindFirstChild("HumanoidRootPart")
		if not root then
			return nil, nil
		end
		-- round from the way you face (you're placed facing the middle, but go by the body)
		local ahead = flat(root.CFrame.LookVector)
		ahead = ahead.Magnitude > 0.5 and ahead.Unit or flat(centre - root.Position).Unit
		local s = 1 - (1 - math.clamp(u, 0, 1)) ^ 3
		local angle = HERO_FROM + (HERO_TO - HERO_FROM) * s
		local c, n = math.cos(angle), math.sin(angle)
		local around = Vector3.new(ahead.X * c - ahead.Z * n, 0, ahead.X * n + ahead.Z * c)
		local distance = HERO_FAR + (HERO_NEAR - HERO_FAR) * s
		-- the camera at chest height sinking to the waist (a low, heroic angle), framing your whole
		-- body a little right of centre so the name card on the left stays clear of you
		local body = root.Position + Vector3.new(0, 0.2, 0)
		local position = body + around * distance + Vector3.new(0, 2.6 - 2.0 * s, 0)
		local aim = body - CFrame.lookAt(position, body).RightVector * 1.6
		return position, aim
	end

	-- the flight's timed points: the orbit, past each of the others round the ring, into you
	local function build()
		cast, me = contestants()
		if not startAngle then
			-- the orbit ends just short of you, so it dives in ahead of the others round the ring
			-- (by you: the others' bodies may not have streamed in yet)
			if me then
				startAngle = angleOf(me.model) - math.rad(125)
			elseif cast[1] then
				startAngle = angleOf(cast[1].model) - math.rad(140)
			else
				startAngle = math.random() * math.pi * 2
			end
		end
		local cam, look, pops = {}, {}, {}
		local middle = centre + Vector3.new(0, 2, 0)
		-- the orbit looks at the middle, then at the first of the others by the time it dives in
		-- (aiming at the middle while flying in between it and them flipped the view round)
		local firstRoot = cast[1] and cast[1].model:FindFirstChild("HumanoidRootPart")
		local firstAim = firstRoot and firstRoot.Position + Vector3.new(0, 1, 0) or middle
		for _, key in { { 0, 0 }, { SWEEP_END * 0.35, 0.4 }, { SWEEP_END * 0.7, 0.75 }, { SWEEP_END, 1 } } do
			table.insert(cam, { t = key[1], v = orbit(key[2]) })
			table.insert(look, { t = key[1], v = key[1] == SWEEP_END and firstAim or middle })
		end
		local first, last = FLY_FIRST, me and FLY_LAST or (HERO_END - 1)
		for index, item in cast do
			local root = item.model:FindFirstChild("HumanoidRootPart")
			if root then
				local t = #cast == 1 and first or first + (last - first) * (index - 1) / (#cast - 1)
				local inward = flat(centre - root.Position)
				inward = inward.Magnitude > 0.5 and inward.Unit or Vector3.new(1, 0, 0)
				table.insert(cam, { t = t, v = root.Position + inward * PASS_IN + Vector3.new(0, PASS_UP, 0) })
				table.insert(look, { t = t, v = root.Position + Vector3.new(0, 1, 0) })
				table.insert(pops, { t = t - 0.12, item = item })
			end
		end
		if me then
			-- arriving at the hero shot's start, and one point into it so the curve meets its motion
			local heroLength = HERO_END - OTHERS_END
			for _, u in { 0, 0.12 } do
				local position, aim = heroShot(me, u)
				if position then
					table.insert(cam, { t = OTHERS_END + u * heroLength, v = position })
					table.insert(look, { t = OTHERS_END + u * heroLength, v = aim })
				end
			end
		else
			-- someone watching: back up high over the arena
			table.insert(cam, { t = HERO_END, v = orbit(0.55) + Vector3.new(0, 10, 0) })
			table.insert(look, { t = HERO_END, v = middle })
		end
		return { cam = cam, look = look, pops = pops }
	end

	-- your moment's extras, once: the pose, the spotlight flare, the name card's cue, a big pop
	local heroStarted = false
	local function startHero(item)
		heroStarted = true
		RoundClient.Set("IntroHero", true)
		Platformer.Pose("Hero", HERO_END - OTHERS_END)
		local root = item.model:FindFirstChild("HumanoidRootPart")
		local top = root and root:FindFirstChild("BumpSpotTop")
		local light = top and top:FindFirstChildOfClass("SpotLight")
		if light then
			local rest = light.Brightness
			TweenService:Create(light, TweenInfo.new(0.15), { Brightness = FLARE_BRIGHTNESS }):Play()
			task.delay(1.8, function()
				if light.Parent then
					TweenService:Create(light, TweenInfo.new(1.2), { Brightness = rest }):Play()
				end
			end)
		end
		if root then
			local color = RoundInfo.SeatColors[item.seat or 0] or Color3.new(1, 1, 1)
			local recipes = BumpFx.Recipes
			BumpFx.Burst(CFrame.new(root.Position - Vector3.new(0, 2.6, 0)), {
				recipes.Ring(12, color), recipes.Sparkles(18, 0.9), recipes.Stars(8, { 6, 11 }, 0.6),
			})
			local s = BumpFx.Sound(BumpSounds.ShoveWhoosh, 0.5, root, 120)
			s.PlaybackSpeed = 1.2
			s:Play()
			Debris:AddItem(s, 2)
		end
	end

	local function provider(dt, base)
		if not running or running.serial ~= mine then
			return base
		end
		local t = elapsed()
		-- built at once, and again twice during the orbit: the others' bodies stream in to you
		-- only once you're placed on the arena (at the start often just one has arrived)
		local builds = path and path.builds or 0
		if not path or (builds < 2 and t > 0.5) or (builds < 3 and t > 1.0) then
			local done = path and path.pops or nil
			path = build()
			path.builds = builds + 1
			for _, old in done or {} do
				for _, new in path.pops do
					if old.done and new.item.model == old.item.model then
						new.done = true
					end
				end
			end
		end
		if t >= HERO_END and not fading then
			fading = true
			RoundClient.Set("IntroHero", false)
			running.layer:tweenWeight(0, TweenInfo.new(OUT_END - HERO_END, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut))
			task.delay(OUT_END - HERO_END + 0.05, function()
				if running and running.serial == mine then
					stop()
				end
			end)
		end
		if me and t >= OTHERS_END then
			-- your moment
			if not heroStarted then
				startHero(me)
				local gui = popName(me)
				if gui then
					table.insert(running.pops, gui)
				end
			end
			local u = math.clamp((t - OTHERS_END) / (HERO_END - OTHERS_END), 0, 1)
			local position, aim = heroShot(me, u)
			if not position then
				return base
			end
			local fov = FLY_FOV + (HERO_FOV - FLY_FOV) * smooth(u)
			aim = trail(aim, dt)
			return CameraState.new(CFrame.lookAt(position, aim), fov, CFrame.new(aim))
		end
		-- the flight
		for _, pop in path.pops do
			if not pop.done and t >= pop.t then
				pop.done = true
				local gui = popName(pop.item)
				if gui then
					table.insert(running.pops, gui)
				end
			end
		end
		local position, aim = along(path.cam, t), trail(along(path.look, t), dt)
		local fov = SWEEP_FOV + (FLY_FOV - SWEEP_FOV) * smooth((t - SWEEP_END) / (FLY_FIRST - SWEEP_END))
		return CameraState.new(CFrame.lookAt(position, aim), fov, CFrame.new(aim))
	end

	local ok, layer = pcall(function()
		return service:AddLayer(provider, LAYER_PRIORITY, { KeepBaseCamera = true })
	end)
	if not ok or not layer then
		running = nil
		return
	end
	running.layer = layer
	layer:setWeight(1)
	-- a safety net: whatever happens, it's gone after the intro
	task.delay(Rounds.Intro + 0.5, function()
		if running and running.serial == mine then
			stop()
		end
	end)
end

function RoundIntro.start()
	task.spawn(function()
		local round = ReplicatedStorage:WaitForChild(RoundInfo.Folder)
		CameraHandlerClient.PromiseReady(20):await()
		local function onPhase()
			if round:GetAttribute("Phase") == "Intro" then
				-- only from the start (a client joining mid-intro just gets the countdown)
				if elapsed() < 1 then
					begin()
				end
			else
				stop()
			end
		end
		round:GetAttributeChangedSignal("Phase"):Connect(onPhase)
		onPhase()
	end)
	player.CharacterAdded:Connect(function()
		stop()
	end)
end

return RoundIntro
