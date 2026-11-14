--!nonstrict
--[[
	The game's systems. ServerMaster and ClientMaster build their load orders from this list.
	Paths are ImportPaths strings (@GameServer / @GameClient), resolved at runtime by the engine
	loaders; each module follows the engine's system shape (start(), and the optional
	init/playerAdded/characterAdded hooks).

	    Server = { "@GameServer/Systems/RoundServer" },   -- src/Server/Systems/RoundServer.lua
	    Client = { "@GameClient/Systems/Hud" },           -- src/Client/Systems/Hud.lua
]]

return {
	Server = {
		"@GameServer/Systems/Yard",
		"@GameServer/Systems/Lobby",
		"@GameServer/Systems/BumpServer",
		"@GameServer/Systems/Progress",
		"@GameServer/Systems/Stations",
		"@GameServer/Systems/RoundServer",
	},
	Client = {
		"@GameClient/Systems/Platformer",
		"@GameClient/Systems/Animator",
		"@GameClient/Systems/BumpFx",
		"@GameClient/Systems/BallSounds",
		"@GameClient/Systems/BallRider",
		"@GameClient/Systems/BumpMusic",
		"@GameClient/Systems/ArenaShow",
		"@GameClient/Systems/PowerUpClient",
		"@GameClient/Systems/PowerUpFx",
		"@GameClient/Systems/PopFx",
		"@GameClient/Systems/RoundIntro",
		"@GameClient/Systems/FallCam",
		"@GameClient/Systems/KnockoutCam",
		"@GameClient/Systems/MeltClient",
		"@GameClient/Systems/StationClient",
	},
	-- RoundClient is not here: ClientMaster preloads it, ahead of the UI host.
}
