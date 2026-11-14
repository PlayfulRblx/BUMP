--!nonstrict
--[[
	Every movement number, in one place. Read them through Tuning (Tuning.Of("Jump").Single),
	never from here directly, so they can be changed live in Studio.

	Heights are in studs above where you left the ground; speeds in studs per second; times in
	seconds. A Roblox character is about 5 studs tall, so a 5 stud jump clears your own head.
	Every number is a first guess until it has been played.

	The timed clips (JumpSingle, Backflip in animation/scripts/clips_bump.py) are stretched to fit
	the real time in the air (Platformer.AirTime), so these heights can change freely.
]]

return {
	Run = {
		Speed = 28, -- top running speed (stock Roblox walking is 16)
		Accel = 90, -- how fast you reach it
		Friction = 120, -- how fast you stop when you let go
		Skid = 220, -- how fast you stop when you push the other way at speed
		TurnRate = 14, -- how fast your body turns to face where you run (per second)
	},

	Crouch = {
		Speed = 8, -- crouch walking
		SlideFriction = 45, -- crouching at speed slides you to a stop this slowly
	},

	Air = {
		TurnRate = 4.6, -- radians a second your body and your arc turn toward where you push (about 265 degrees; was 3.4)
		FlipTurn = 0.6, -- share of that during a backflip
		LongJumpTurn = 0.45,
		DiveTurn = 0.35,
		SteerShare = 0.6, -- share of Accel on an ordinary jump: turning does most of the steering
		Accel = 100, -- speeding up and slowing down in the air toward where you push (was 60)
		Speed = 28, -- the speed air steering reaches on its own; faster jumps keep their speed
		Drag = 5, -- with nothing pushed, the air takes off this much speed a second: momentum carries
		-- The user (2026-11-13): jumps felt "floaty or slow", against Odyssey. Every jump keeps its
		-- height but rises and falls under heavier gravity: shares of Workspace.Gravity (196.2).
		RiseGravity = 1.35, -- rising (was 1: a single took 0.27 s to its top, now 0.23 s)
		FallGravity = 2, -- falling (was 1.45)
		MaxFall = 190,
		CutJump = 0.45, -- letting go of jump while rising keeps this share of the rise
	},

	Jump = {
		Single = 7, -- every ground jump; the second jump is the air jump (AirJump)
		Buffer = 0.14, -- a jump pressed this long before landing still counts
		Coyote = 0.1, -- and one pressed this long after running off an edge
	},

	Backflip = {
		Height = 15,
		BackSpeed = 24, -- carried the whole way: the arc goes well back
		Steer = 0.25, -- share of normal air steering during it
	},

	-- The user (2026-11-13): "Instead of the triple jump, I want a jump and then a floaty jump if I
	-- try to jump again whilst in the air". One per time in the air, back on landing or a wall.
	-- The ground chain (double and triple) is gone: every ground jump is a single.
	-- Then (same day): "like a running on air kind of float, the player runs on air as if they're
	-- trying to float up". Press jump in the air and hold: a small kick up, then you keep rising
	-- slowly while your legs run on the air, until you tire and the lift gives out. Let go and you
	-- drop out of it. One per time in the air.
	AirJump = {
		Kick = 22, -- upward speed the press gives at once
		RiseSpeed = 7, -- the upward speed the running pulls you toward while you hold
		Pull = 7, -- how quickly it pulls toward that (per second)
		Duration = 1.1, -- the longest it lasts
		Tire = 0.65, -- after this share of Duration the lift gives out, sinking toward TiredSpeed
		TiredSpeed = -10,
		MinTime = 0.18, -- a tap still runs this long
		Steer = 1.2, -- air steering share while running on air
		-- how fast the body turns to face where you push (or travel) while running on air (the
		-- user, 2026-11-13: "my character should face the direction I'm running a bit easier";
		-- it used to turn only at Air.TurnRate, so steering left it running sideways or backwards)
		FaceRate = 14,
	},

	LongJump = {
		Height = 4.5,
		Speed = 56, -- at least this fast; a faster run keeps its speed
		MinSpeed = 12, -- crouch-jump slower than this and it is a backflip instead
	},

	Pound = {
		Hang = 0.28, -- the spin in the air before the drop
		FallSpeed = 120,
		LandLock = 0.3, -- stuck after landing
		JumpWindow = 0.3, -- jump this soon after landing for the big jump
		JumpHeight = 17,
		ShockRadius = 9, -- a landing pound bumps anyone this close
		-- On the BUMP platform a pound sends a ripple through the tiles: every rider whose ball
		-- it reaches wobbles (or is knocked off if already wobbling)
		RippleRadius = 28,
		RippleSpeed = 70, -- studs a second the wave travels
		RippleHeight = 1.6, -- how high a tile bobs at the middle
	},

	Dive = {
		Speed = 50, -- at least this fast forward
		Up = 22, -- upward kick when you dive (studs per second, not a height)
		SlideFriction = 40, -- the belly slide after landing a dive
		SlideMin = 0.25, -- stuck in the slide at least this long
		RolloutHeight = 5, -- jump out of the slide
	},

	Roll = {
		Speed = 46,
		Time = 0.55,
		JumpHeight = 6,
	},

	-- Landing from a big drop rolls you forward instead of stopping you dead.
	BigFall = {
		Height = 18, -- falls from at least this high (from the top of the arc) roll
		Speed = 30, -- at least this fast along the ground
		Time = 0.5,
	},

	-- Rolling square into something solid (Sunshine Valley's bonk): a hop back off it, down on
	-- your backside, a sit seeing stars, then up. No control until it is over.
	Bonk = {
		Square = 0.55, -- how square on the hit must be (dot of the roll and the wall); glancing hits slide
		Reach = 2.8, -- how far ahead of your middle a wall counts
		BounceSpeed = 14,
		BounceUp = 18,
		FallTime = 0.37, -- the WallBonk clip's length
		DazeTime = 0.6,
		GetUpTime = 0.4, -- the DazeUp clip's length
	},

	Wall = {
		Reach = 2.6, -- how far ahead of your middle a wall counts
		GrabSpeed = 6, -- you must be moving into the wall at least this fast (or pushing at it)
		GrabRise = 12, -- rising faster than this, you go up past it instead of catching it
		Cling = 0.3, -- held still on the wall this long
		SlideMax = 22, -- then sliding down, speeding up to this
		SlideAccel = 26, -- this fast
		Hold = 1.6, -- after this long on the wall (cling and slide) you let go and fall
		LetGoPush = 6, -- the little push off the wall when you let go
		RegrabDelay = 0.45, -- the same wall can't be caught again this soon
		JumpHeight = 11,
		JumpOut = 26,
		LockTime = 0.22, -- after a wall jump, steering waits this long
	},

	-- The shove (polished 2026-11-13; the user: it "moves the character a bit too far forward",
	-- the animation was weak, it was hard to land and the victim's reaction dull): a beat of
	-- wind-up, a short burst that stops dead (about 3.7 studs, was about 8), a wider and longer hit cone, and a
	-- snap toward the nearest body in front as it starts. The one shoved staggers back (Shoved).
	Bump = {
		WindUp = 0.06, -- coiling back before the burst
		Lunge = 22, -- forward burst (was 40 for 0.18 s)
		Time = 0.12,
		Brake = 220, -- how hard the burst stops
		Cooldown = 0.45,
		Reach = 6.5, -- was 4.8
		BodyReach = 4.8, -- a dive's or a roll's reach into a body (unchanged)
		Cone = 0.1, -- how far round from straight ahead counts (dot product; was 0.35)
		Assist = 10, -- studs: the nearest body this close, in front, is turned toward
		AssistDot = 0.25, -- and this far round from where you face or push
		Push = 55, -- how hard a bump throws someone
		Lift = 16, -- (was 28: the shoved stagger back along the ground)
		ShoveTime = 0.62, -- no control while staggering from a shove
		ShoveSkid = 70, -- how fast the stagger's slide slows
		DivePush = 75, -- diving into someone
		DiveLift = 30,
		PoundPush = 45,
		PoundLift = 40,
		KnockTime = 0.55, -- no control after being bumped
	},

	-- ═══ rounds ════════════════════════════════════════════════════════════════════
	Rounds = {
		Seats = 8, -- contestants in every game: players first, bots fill the rest (the user,
		-- 2026-11-13: "Let's get 4 more AIs in"; was 4)
		Games = 6, -- games in a session's playlist (2026-11-14: 6 with MELTDOWN in, so each plays twice; was 5)
		Lobby = 12, -- seconds of count before a session (Studio: StudioLobby)
		StudioLobby = 5,
		-- A game's intro (the user, 2026-11-13: "a nice AAA ADHD nintendo level intro with title card
		-- and camera pan over along with some intro music into a 3 - 2 - 1 countdown"; about 7 s):
		-- a camera flyover and title card, then the last IntroCountdown seconds count down 3, 2, 1
		-- and Play starts on GO (Client/Systems/RoundIntro, HudIntro, HudCountdown, BumpMusic).
		Intro = 14, -- the cutscene's 11 s and the 3, 2, 1 (2026-11-14: "twice as long"; was 8.5, 7, 6)
		IntroCountdown = 3,
		Results = 6,
		Intermission = 15, -- seconds on the plaza between games, to breathe and shop (2026-11-14)
		Standings = 9,
		Gold1 = 12, -- gold by place
		Gold2 = 9,
		Gold3 = 7,
		Gold4 = 5,
		Gold5 = 4,
		Gold6 = 3,
		Gold7 = 2,
		Gold8 = 1,
	},

	-- ═══ BUMP: the ball game ═══════════════════════════════════════════════════════
	-- Faster and harder (2026-11-13; the user: the ball game "seems a little too slow ... when I
	-- charge my balls speed and ram into somebody, there's not really that feel good feeling
	-- behind the impact"). Old values in brackets.
	Ball = {
		Size = 8, -- diameter
		MaxSpeed = 44, -- rolling top speed by steering alone (34)
		Accel = 34, -- it takes a moment to get going, and to turn (22)
		Drag = 3, -- with nothing pushed: hard to slow down
		OverDrag = 14, -- above MaxSpeed (after a dash) speed bleeds off this fast (18)
		SkrrtDot = -0.5, -- pulling this far against your roll is a skrrt
		SkrrtMin = 10, -- only above this speed
		SkrrtDecel = 110, -- and it stops you this fast (85)
		ChargeTime = 0.55, -- holding click charges the dash to full in this long (0.8)
		ChargeDrag = 34, -- charging slows you down this fast (26)
		DashMin = 0.15, -- a charge under this is no dash
		DashBase = 46, -- the dash's speed at the smallest charge (34)
		DashBonus = 54, -- added at full charge: 100 at full (42: 76)
		DashCooldown = 0.5,
		WobbleSteer = 0.35, -- steering while wobbling is this share
		MountReach = 3.5, -- land within this of the top of a free ball and you're on it
	},

	BumpHits = {
		Min = 14, -- closing speed for a hit to count
		Push = 30, -- a hit throws the ball you hit this fast, plus: (22)
		PushShare = 0.8, -- this share of how fast you hit it (0.6)
		Hard = 75, -- closing speed of the biggest-feeling hit (the effects scale up to it)
		Follow = 0.55, -- the hitter's ball carries on through at this share of its speed, not bouncing back
		Pause = 0.05, -- the hit freezes the balls involved this long (on their riders' screens), plus:
		PauseHard = 0.07, -- this much more for the hardest hit
		Wobble = 1.6, -- seconds a hit rider wobbles; hit again before it's over and you're off
		Debounce = 0.4,
		FootMin = 12, -- a ball this fast knocks someone on foot
		-- The user: "Getting hit by a ball when on foot should knock the victim back quite a bit". The
		-- push was always 70, but going limp at the same moment let the loose limbs drag it to a stop
		-- (6.8 studs); thrown whole (Ragdoll.Fling) 90 slid a dummy 90 studs, more than the arena, so:
		FootPush = 75,
		FootLift = 40,
		Ragdoll = 1.4, -- seconds knocked flat
	},

	BumpArena = {
		Rings = 7, -- hex rings round the centre tile (169 tiles, about 180 studs across); the user
		-- wanted it "much larger" than the first 4 rings (2026-11-13)
		Tile = 7, -- a tile's corner radius
		Grace = 10, -- seconds before the first cell falls
		-- The platform crumbles one cell at a time (the user's idea, 2026-11-13): first random
		-- cells off the edge, then, once HolesAfter of it is gone, holes anywhere. The gap
		-- between cells shrinks from DropStart to DropEnd over DropRamp seconds.
		DropStart = 1.4,
		DropEnd = 0.25,
		DropRamp = 70,
		HolesAfter = 0.55,
		Warn = 2.5, -- a cell shakes and flashes this long before it drops
		KeepCells = 3, -- it stops dropping with this many left
		TimeLimit = 120,
		FallDepth = 20, -- this far below the platform and you're out (2026-11-14: was 30; falls felt late)
	},

	-- Knocked flat (Shared/Ragdoll, from The Scramble): each joint has a weak muscle pulling it
	-- towards a relaxed pose on top of its hard limits. Gravity still wins.
	Ragdoll = {
		Tension = 0.35, -- share of the weight hanging off each joint (0 turns it off)
		Responsiveness = 12, -- higher is snappier, lower is floppier
	},

	-- ═══ BOMBER BLOXIANS: pass the bomb ════════════════════════════════════════════
	-- The user's choices (2026-11-13): a hidden fuse whose ticking quickens; an explosion
	-- leaves a crater and throws anyone close; the holder runs faster; touch anyone to pass it.
	Bomber = {
		Rings = 6, -- 127 cells (was 5, 91 cells, for 4 contestants)
		Tile = 7,
		FuseMin = 15, -- a bomb's fuse is a random length in here, never shown
		FuseMax = 25,
		FirstBomb = 1.5, -- seconds after the start before the first bomb is handed out
		NextBomb = 3, -- seconds after a blast before the next
		HolderSpeed = 1.25, -- the holder runs this much faster
		PassReach = 4.5, -- touching distance, body to body
		PassImmunity = 1.5, -- whoever just got it can't pass it on for this long
		PassPush = 22, -- a pass shoves the receiver a little
		CraterRadius = 16, -- cells this close to the blast fall away
		CraterWarn = 0.35,
		EdgeBite = 8, -- and this many edge cells crumble after each blast
		KeepCells = 7, -- the edge stops crumbling with this many edge cells left
		BlastRadius = 20, -- anyone this close is thrown and knocked flat
		BlastPush = 75,
		BlastLift = 45,
		TickSlow = 1.0, -- seconds between ticks with the fuse fresh
		TickFast = 0.1, -- and at the very end
		FallDepth = 20, -- (was 30: falls felt late)
	},

	-- ═══ MELTDOWN: climb away from the lava ══════════════════════════════════════════
	-- The user (2026-11-14): "a third gamemode ... completely new, intense, and incredibly fun";
	-- they picked a climb up a tower of platforms with lava rising, last one standing, with
	-- crumbling and moving platforms, bounce pads, wall-jump chimneys, lava fireballs, surges and
	-- falling debris. Every number a first guess.
	Melt = {
		Tiers = 14, -- tiers of platforms; the summit is the last (was 21 at 5 apart)
		TierGap = 7.5, -- studs between tiers: over a single jump's 7, so each tier takes a float jump
		-- (the user, 2026-11-14: "Make the player utilise their float jump"; was 5)
		BaseInner = 52, -- the start ring of hex tiles round the tower, from here (tiles poke in this
		-- far at most; the hex tiles make the inner edge jagged, a few studs deep)
		BaseOuter = 82, -- to here (tile middles)
		StartRadius = 68, -- everyone starts on the base this far out (the intro's fly-by passes 16 inside)
		PitDrop = 10, -- the pit's floor under the tower is this far below the start ring: an early
		-- fall lands there and you climb back up, until the lava floods it
		LavaStart = -32, -- the lava's top at the start (the start ring is at -6, the pit floor -16)
		Grace = 5, -- seconds of play before it rises
		RiseStart = 0.7, -- studs a second, rising to
		RiseMax = 2.2,
		RiseRamp = 80, -- over this many seconds
		LavaStop = 7, -- it stops this far below the summit's top: the last fight is on the summit
		SummitCrumble = 26, -- once the lava is this close to the summit, the top tiers start to crumble
		SummitEvery = 1.4, -- a platform up there every this many seconds
		CrumbleWarn = 0.6, -- a crumbling platform shakes this long once landed on, then falls
		CrumbleBack = 6, -- and comes back after this, if the lava isn't there
		BounceHeight = 26, -- a bounce pad throws you this high: three tiers
		SurgeFirst = 16, -- seconds before the first surge
		SurgeMin = 12, -- then one every this to
		SurgeMax = 18,
		SurgeWarn = 1.5, -- the warning (rumble, shake, "SURGE!") before it lurches up
		SurgeRise = 8, -- studs it lurches up
		SurgeTime = 1.5, -- over this long
		FireballFirst = 8, -- seconds in before the first fireball
		FireballSlow = 4.5, -- seconds between fireballs at the start
		FireballFast = 1.4, -- and at the hottest
		FireballFlight = 1.1, -- seconds from the lava to landing (the ring warns all that time)
		FireballRadius = 6, -- anyone this close to where it lands is hit
		FireballPush = 55,
		FireballLift = 24,
		DebrisFirst = 30, -- seconds in before chunks start falling
		DebrisSlow = 7,
		DebrisFast = 2.5,
		DebrisWarn = 1.2, -- the shadow shows this long before it lands
		DebrisRadius = 5,
		DebrisPush = 40,
		DebrisLift = 30,
		ShakePush = 38, -- a ground pound staggers everyone else on that platform this hard
		ShakeLift = 18,
		TimeLimit = 180, -- hidden: survivors share 1st
	},
}
