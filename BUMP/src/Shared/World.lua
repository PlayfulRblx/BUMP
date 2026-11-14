--!nonstrict
--[[
	Where things are in BUMP's world (2026-11-13, the lobby built from the user's AR place).

	The lobby is AR's neon city hub (Workspace.Lobby, placed in Studio, not built by code) centred
	on the origin. Its middle was cleared down to the clouds: the round's arena floats there, in a
	pit PitRadius across, so everyone on the plaza can watch. The old grey test yard is now the
	practice ground, out of the way at YardOrigin.

	    World.ArenaOrigin     the arena's floor centre (HexArena's Origin: tile tops at its Y)
	    World.PitRadius       open air inside this, from the plaza's edge down to the clouds
	    World.WallRadius      the pit wall: invisible, from WallBottom up; keeps the plaza out and
	                          the players in (a contestant can't jump out onto the plaza)
	    World.YardOrigin      the practice yard's centre
	    World.LobbySpot()     a random spot on the plaza, facing the arena
	    World.SpawnCFrame     where a player first arrives
	    World.PlayDoor,       the PLAY, REWARDS and PRACTICE stores' doorways (AR's walk-in halls
	    World.RewardsDoor,    and the gacha room behind them were removed): { CFrame facing the
	    World.PracticeDoor    plaza, Size }
	    World.ShopSpot,       where you stand to use the SHOP, LOCKER and REWARDS stores
	    World.LockerSpot,     (Server/Systems/Stations): just outside each doorway (Y is a guess:
	                          Stations drops each onto the floor below it)
	    World.RewardsSpot
]]

local Workspace = game:GetService("Workspace")

local World = {}

World.Centre = Vector3.new(0, 0, 0)
World.ArenaOrigin = Vector3.new(0, -6, 0)
World.PitRadius = 100
World.WallRadius = 101
World.WallBottom = -5 -- below this the wall stops: thrown sideways, you still fall into the gap
World.WallTop = 120
World.PlazaY = 0.5
World.YardOrigin = Vector3.new(0, 0, 1600)
World.SpawnCFrame = CFrame.lookAt(Vector3.new(-132, 3.5, 0), Vector3.new(0, 3.5, 0))
World.PlayDoor = { CFrame = CFrame.lookAt(Vector3.new(182, 10.8, 1), Vector3.new(0, 10.8, 1)), Size = Vector2.new(46, 21) }
World.RewardsDoor = { CFrame = CFrame.lookAt(Vector3.new(0, 14, -314), Vector3.new(0, 14, 0)), Size = Vector2.new(57, 22) }
World.ShopSpot = Vector3.new(124, 0.5, 118) -- in front of AR's MERCHANT_SHOP gate
World.LockerSpot = Vector3.new(120, 0.5, -104.5) -- in front of AR's LAB doorway
World.RewardsSpot = Vector3.new(0, 0.5, -307) -- on the stage in front of the doorway
World.PracticeDoor = { CFrame = CFrame.lookAt(Vector3.new(-178, 12.36, 1.74), Vector3.new(0, 12.36, 1.74)), Size = Vector2.new(57, 24.7) }

local rng = Random.new()

-- A random spot on the plaza ring, on solid floor, facing the arena.
function World.LobbySpot(): CFrame
	local lobby = Workspace:FindFirstChild("Lobby")
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = lobby and { lobby } or {}
	for _ = 1, 12 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = rng:NextNumber(122, 142)
		local top = Vector3.new(math.cos(angle) * radius, 40, math.sin(angle) * radius)
		local hit = lobby and Workspace:Raycast(top, Vector3.new(0, -60, 0), params)
		if hit and hit.Instance.CanCollide and math.abs(hit.Position.Y - World.PlazaY) < 2 then
			local at = hit.Position + Vector3.new(0, 3, 0)
			return CFrame.lookAt(at, Vector3.new(World.Centre.X, at.Y, World.Centre.Z))
		end
	end
	return World.SpawnCFrame
end

return World
