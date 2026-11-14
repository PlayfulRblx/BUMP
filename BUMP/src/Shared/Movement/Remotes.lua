--!nonstrict
--[[
	Movement remotes, through the engine's Network library under one "Bump:" prefix.

	Server -> client:
	- You: (name, data) only for you: "Knock" (you were bumped: data.Velocity).
	- Fx: (name, data) everyone sees: "Bump" (data.Position).
	Client -> server:
	- Act: (action, ...) "Move" (the move you are in, for everyone's poses) and "Bump" (you hit
	  someone: target model, kind). One rate-limited stream; each action validates itself.
]]

local Network = require("@Lib/Network")

local PREFIX = "Bump:"
local ACTIONS_PER_SECOND = 60

local Remotes = {}

-- Server only: create every remote before any system hooks or fires one.
function Remotes.Declare()
	Network.ensureEvent(PREFIX .. "You")
	Network.ensureEvent(PREFIX .. "Fx")
	Network.createEvent(PREFIX .. "Act", false, ACTIONS_PER_SECOND)
end

function Remotes.HookAct(callback)
	return Network.hookEvent(PREFIX .. "Act", callback, ACTIONS_PER_SECOND)
end

function Remotes.HookYou(callback)
	return Network.hookEvent(PREFIX .. "You", callback)
end

function Remotes.HookFx(callback)
	return Network.hookEvent(PREFIX .. "Fx", callback)
end

function Remotes.You(player: Player, name: string, data)
	Network.fireClient(PREFIX .. "You", player, name, data)
end

function Remotes.Fx(name: string, data)
	Network.fireAllClients(PREFIX .. "Fx", name, data)
end

function Remotes.Act(action: string, ...)
	Network.fireServer(PREFIX .. "Act", action, ...)
end

-- The tag on every body that can be bumped (players' characters and the dummies).
Remotes.BodyTag = "BumpBody"
-- The character attribute other clients read to pose a body.
Remotes.MoveAttr = "BumpMove"

return Remotes
