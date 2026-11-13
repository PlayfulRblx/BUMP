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
	Server = {},
	Client = {},
}
