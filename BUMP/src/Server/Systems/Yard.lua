--!nonstrict
--[[
	The grey-box test yard for tuning the controls: plainly a test ground, built in code so it is
	the same every run. Since the lobby moved in (2026-11-13) it's the practice ground, built
	round World.YardOrigin (positions below are relative to it); the lobby's Practice pad
	brings you here and the yard's return pad takes you back (Server/Systems/Lobby).

	- North: six ledges, 4 to 24 studs tall, each labelled, for reading jump heights.
	- East: a long-jump lane with a line every 5 studs and a number every 10.
	- West: a chimney of two tall walls to wall-jump up, and one lone wall to slide down.
	- South: a 20 stud tower, taller than any single jump.
	- South-east: steps up to a 28 stud drop: jump off it and you land in a roll, and the wall
	  past it is for rolling into (a bonk).
	- South-west: the practice dummies stand on a white ring (BumpServer makes them).
]]

local Workspace = game:GetService("Workspace")

local World = require("@Shared/World")

local Yard = {}

local LEDGE = Color3.fromRGB(226, 228, 232)
local WALL = Color3.fromRGB(96, 104, 120)
local MARK = Color3.fromRGB(240, 186, 64)
local RING = Color3.fromRGB(245, 245, 248)
local TOWER = Color3.fromRGB(120, 170, 230)

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- A box standing on the floor (top of the baseplate is y = 0).
local function box(parent: Instance, name: string, x: number, z: number, size: Vector3, color: Color3): BasePart
	return part(parent, name, size, CFrame.new(x, size.Y / 2, z), color)
end

local function label(on: BasePart, text: string, height: number?)
	local attachment = Instance.new("Attachment")
	attachment.Position = Vector3.new(0, on.Size.Y / 2 + (height or 2), 0)
	attachment.Parent = on
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(120, 36)
	gui.MaxDistance = 160
	gui.Adornee = attachment
	gui.Parent = attachment
	local text_ = Instance.new("TextLabel")
	text_.Size = UDim2.fromScale(1, 1)
	text_.BackgroundTransparency = 1
	text_.Font = Enum.Font.GothamBold
	text_.TextScaled = true
	text_.TextColor3 = Color3.new(1, 1, 1)
	text_.TextStrokeTransparency = 0.4
	text_.Text = text
	text_.Parent = gui
end

local function build(): Folder
	local yard = Instance.new("Folder")
	yard.Name = "Yard"

	-- North: ledges for jump heights
	for index, height in { 4, 8, 12, 16, 20, 24 } do
		local x = -50 + (index - 1) * 20
		local ledge = box(yard, "Ledge" .. height, x, -50, Vector3.new(12, height, 12), LEDGE)
		label(ledge, height .. " studs")
	end

	-- East: long-jump lane
	local laneStart, laneEnd, laneZ = 20, 140, 0
	part(yard, "Lane", Vector3.new(laneEnd - laneStart, 0.1, 8), CFrame.new((laneStart + laneEnd) / 2, 0.05, laneZ), Color3.fromRGB(70, 74, 82))
	for distance = 0, laneEnd - laneStart, 5 do
		local x = laneStart + distance
		local major = distance % 10 == 0
		local line = part(yard, "Mark" .. distance, Vector3.new(major and 0.6 or 0.3, 0.12, 8), CFrame.new(x, 0.06, laneZ), MARK)
		if major then
			label(line, tostring(distance), 1)
		end
	end

	-- West: wall-jump chimney and a lone wall
	box(yard, "ChimneyA", -70, -10, Vector3.new(2, 50, 30), WALL)
	box(yard, "ChimneyB", -84, -10, Vector3.new(2, 50, 30), WALL)
	local top = part(yard, "ChimneyTop", Vector3.new(16, 1, 10), CFrame.new(-77, 50.5, -30), LEDGE)
	label(top, "50 studs")
	box(yard, "LoneWall", -70, 30, Vector3.new(2, 30, 20), WALL)

	-- South: tower
	local tower = box(yard, "Tower", 20, 50, Vector3.new(10, 20, 10), TOWER)
	label(tower, "20 studs")

	-- South-east: steps up to a drop platform, open floor below it, and a wall to roll into
	for index = 1, 7 do
		local height = index * 4
		box(yard, "DropStep" .. index, 60, 20 + index * 6, Vector3.new(8, height, 6), LEDGE)
	end
	local drop = box(yard, "DropPlatform", 60, 68, Vector3.new(10, 28, 10), TOWER)
	label(drop, "28 stud drop")
	box(yard, "BonkWall", 60, 100, Vector3.new(24, 10, 2), WALL)

	-- South-west: dummy ring
	local ring = part(yard, "DummyRing", Vector3.new(0.2, 36, 36), CFrame.new(-30, 0.1, 38) * CFrame.Angles(0, 0, math.pi / 2), RING)
	ring.Shape = Enum.PartType.Cylinder

	return yard
end

function Yard.start()
	local old = Workspace:FindFirstChild("Yard")
	if old then
		old:Destroy()
	end
	local yard = build()
	-- built round the origin, then moved out to the practice ground
	local model = Instance.new("Model")
	model.Name = "Yard"
	for _, child in yard:GetChildren() do
		child.Parent = model
	end
	model.WorldPivot = CFrame.new()
	model:PivotTo(CFrame.new(World.YardOrigin))
	model.Parent = Workspace
	yard:Destroy()
end

return Yard
