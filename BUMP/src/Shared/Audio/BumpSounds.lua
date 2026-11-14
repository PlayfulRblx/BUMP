--!nonstrict
--[[
	BUMP's audio, by what it's for. All from Roblox's licensed libraries (free to use in any
	experience), checked to load in this place on 2026-11-13:
	    Silly Chase      APM Music, 145 s, the games
	    Comedy Clip (a)  APM Music, "quirky electronic slapstick", 143 s, the lobby and results
	    Referee whistle  Pro Sound Effects, single blast, 1.8 s, a round ending
	and for Bomber Bloxians, Roblox's own built-in sounds (always there):
	    clickfast.wav               the bomb's tick
	    impact_explosion_03.mp3     the blast
	    electronicpingshort.wav     the bomb changing hands
	Two other APM tracks ("Comic Chase A", "It's Party Time (C)") failed to load here.
	Power-ups (2026-11-13), Pro Sound Effects from the same library plus built-ins:
	    Whoosh By Fast Airy Swooshing   0.7 s, a Turbo
	    Slide Whistle 2                 1.6 s, a Second Chance bouncing you back
	    electronicpingshort.wav (high)  a Shield going up; impact_explosion_03.mp3 (low) a Shockwave
	    Balloon Pop 3                   0.4 s, a bomb holder popping
	Riding a ball (2026-11-14, the user: "we should have sound effects when rolling on the balls"),
	Pro Sound Effects, Client/Systems/BallSounds:
	    Skateboard Start Constant Rolling Cu Wheels 1   34.9 s, looped from 3 s: every ball's roll,
	                                                    louder and higher the faster it goes
	    Tire Swerve Multiple Variations 1               1.1 s, a skrrt
	    Air Whoosh High End Ascending Short 3           3.8 s, the dash charging (sped up as it fills)
	    Whoosh Back Zoom Swoosh Fast Camera             1.4 s, the dash launching
	    impact_explosion_03.mp3 (built-in, slowed)      a ball landing after a hop
	MELTDOWN (2026-11-14), Pro Sound Effects: bubbles, an earthquake rumble, fireball whooshes, a
	shale break, rocks moving, a slide whistle (see the entries).
]]

return table.freeze({
	GameMusic = "rbxassetid://1836675698",
	LobbyMusic = "rbxassetid://1842172309",
	RoundOver = "rbxassetid://9118113825",
	BombTick = "rbxasset://sounds/clickfast.wav",
	BombBoom = "rbxasset://sounds/impact_explosion_03.mp3",
	BombPass = "rbxasset://sounds/electronicpingshort.wav",
	-- a knock-out: the blast sped up for punch, with the ping slowed under it
	KOBoom = "rbxasset://sounds/impact_explosion_03.mp3",
	KOPing = "rbxasset://sounds/electronicpingshort.wav",
	PowerShield = "rbxasset://sounds/electronicpingshort.wav",
	PowerTurbo = "rbxassetid://9126229267",
	PowerShockwave = "rbxasset://sounds/impact_explosion_03.mp3",
	PowerRescue = "rbxassetid://9119197913",
	PowerVolume = 0.8,
	-- a bomb holder popping (Pro Sound Effects "Balloon Pop 3", cartoon, 0.4 s)
	Pop = "rbxassetid://9113263649",
	-- the shove: a whoosh as it goes (Pro Sound Effects "Whoosh By Fast Airy"), a soft thump when
	-- it lands (Pro Sound Effects "Pop Airy 16", pitched down)
	ShoveWhoosh = "rbxassetid://9126229267",
	ShoveHit = "rbxassetid://9117834439",
	PopVolume = 1,
	BallRoll = "rbxassetid://9125955680",
	BallRollLoopFrom = 3, -- seconds: the recording's start-up is skipped when it loops
	BallRollVolume = 0.55,
	BallSkid = "rbxassetid://9120079072",
	BallSkidVolume = 0.6,
	BallCharge = "rbxassetid://9113078189",
	BallChargeVolume = 0.5,
	BallLaunch = "rbxassetid://9126228457",
	BallLaunchVolume = 0.8,
	BallLand = "rbxasset://sounds/impact_explosion_03.mp3",
	BallLandVolume = 0.25,
	-- a game's intro (2026-11-13): APM "Shooting Stars" (4.9 s funky brass) over the flyover,
	-- rising pings on 3, 2, 1, and on GO the referee whistle pitched up over a low boom
	IntroSting = "rbxassetid://9043851046", -- APM "Quizmaster (Jingle)", Showbiz: 10.6 s, the whole cutscene (was "Shooting Stars", 4.9 s, before the intro doubled)
	IntroStingVolume = 0.6,
	CountdownBeep = "rbxasset://sounds/electronicpingshort.wav",
	CountdownVolume = 0.7,
	GoVolume = 0.9,
	-- the game music's tempo at full intensity (1 is as recorded)
	MaxSpeed = 1.32,
	GameVolume = 0.45,
	LobbyVolume = 0.28,
	WhistleVolume = 0.8,
	TickVolume = 0.7,
	BoomVolume = 1,
	PassVolume = 0.6,
	KOVolume = 0.9,
	-- Your own elimination (the user, 2026-11-14: polish it "massively", the card and the sound,
	-- punchy cartoon), timed to the knockout card and camera; all Pro Sound Effects or APM:
	KnockoutClang = "rbxassetid://9113860169", -- "Comic Metal 5": cartoon clangs, as you're out
	KnockoutWhistle = "rbxassetid://9119198150", -- "Slide Whistle 6": a classic cartoon riff, falling
	KnockoutThud = "rbxassetid://9120976778", -- "Wrestling Pad 6": a heavy body thud, the card slamming
	KnockoutWhoosh = "rbxassetid://9126046540", -- "Synth Air Whoosh, Cheesy Karate": the swing to them
	KnockoutPop = "rbxassetid://9113263444", -- "Balloon Pop 2": their name popping in
	KnockoutTag = "rbxassetid://1848271878", -- APM "Fairytown Waltz - Tag3", a comedy tag: the reveal
	KnockoutVolume = 0.55,
	-- MELTDOWN (2026-11-14), Pro Sound Effects (Client/Fx/MeltFx, Client/Systems/MeltClient):
	LavaBubble = "rbxassetid://9112752570", -- "Bubbles Dribble Small Bloops 1", 13.8 s: the lava's bubbling, looped and pitched down
	LavaRumble = "rbxassetid://9112775165", -- "Earthquake Rumble 1", 36 s loop: a surge coming
	Fireball = "rbxassetid://9114428748", -- "Fireball Burning Whoosh By 2", 5.4 s: a fireball's flight
	DebrisFall = "rbxassetid://9114428742", -- "Fireball Burning Whoosh By 1", slowed: a chunk falling
	DebrisCrash = "rbxassetid://9119037874", -- "Shale Break 15", 0.8 s: a chunk landing
	Crumble = "rbxassetid://9118691819", -- "Rocks Movement 1", 1.2 s: a platform breaking up
	Bounce = "rbxassetid://9119197913", -- "Slide Whistle 2", sped up: a bounce pad
})
