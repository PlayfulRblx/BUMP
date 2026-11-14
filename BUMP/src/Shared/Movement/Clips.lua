--!nonstrict
--[[
	Animations, ready to play. The data is generated (see animation/README.md): authored in Blender,
	or imported from Roblox (Imported.lua is Playful's Run, Dash and dodges, by way of Fight in a
	Supermarket), and an imported clip replaces the Blender one of the same name. This
	turns it into CFrames the first time a clip is used and samples it.

	A clip has Seconds, Loop, Markers (name to seconds) and a Track per joint. Sample fills a table
	of joint name to CFrame, naming only the joints the clip moves, which is how an upper-body
	swing leaves the legs running. Keys are thinned per joint, so each track keeps its own times.

	Sampling keeps no state: a built clip is shared by every fighter playing it, each at its own
	time, so a remembered position would be wrong for all but one of them.
]]

local Core = require(script.Parent.AnimationData.Core)
local Imported = require(script.Parent.AnimationData.Imported)

local Clips = {}

local built = {}

local function buildTrack(source)
	local times, rotations, positions = source.T, source.Q, source.P
	local frames = table.create(#times)
	for index = 1, #times do
		local q = (index - 1) * 4
		local p = (index - 1) * 3
		frames[index] = CFrame.new(
			positions and positions[p + 1] or 0,
			positions and positions[p + 2] or 0,
			positions and positions[p + 3] or 0,
			rotations[q + 1],
			rotations[q + 2],
			rotations[q + 3],
			rotations[q + 4]
		)
	end
	return { Times = times, Frames = frames, Count = #times }
end

local function buildClip(source)
	local tracks = {}
	for joint, track in pairs(source.Joints) do
		tracks[joint] = buildTrack(track)
	end
	return { Seconds = source.Seconds, Loop = source.Loop, Markers = source.Markers, Tracks = tracks }
end

function Clips.Get(name: string)
	local clip = built[name]
	local source = Imported[name] or Core[name]
	if not clip and source then
		clip = buildClip(source)
		built[name] = clip
	end
	return clip
end

-- Finds the keys either side of `t` by halving: the last key at or before it, and how far
-- toward the next one `t` is.
local function locate(track, t: number): (number, number)
	local times = track.Times
	local count = track.Count
	if count <= 1 or t <= times[1] then
		return 1, 0
	end
	if t >= times[count] then
		return count, 0
	end
	local low, high = 1, count
	while high - low > 1 do
		local middle = (low + high) // 2
		if times[middle] <= t then
			low = middle
		else
			high = middle
		end
	end
	local from = times[low]
	return low, (t - from) / (times[high] - from)
end

function Clips.SampleTrack(track, t: number): CFrame
	local index, alpha = locate(track, t)
	if alpha <= 0 then
		return track.Frames[index]
	end
	return track.Frames[index]:Lerp(track.Frames[index + 1], alpha)
end

function Clips.Sample(clip, t: number, out)
	if clip.Loop and clip.Seconds > 0 then
		t %= clip.Seconds
	end
	for joint, track in pairs(clip.Tracks) do
		out[joint] = Clips.SampleTrack(track, t)
	end
	return out
end

return Clips
