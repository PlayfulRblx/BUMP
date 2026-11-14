--!nonstrict
--[[
	The lobby's building blocks, shared by everything that dresses AR's neon city (Lobby,
	Stations): the neon palette, the sign font, and two makers.

	    Neon.Part(parent, size, cframe, color, material?, extra?)   an anchored, non-colliding part
	    Neon.Sign(on, text, color, background?, canvas?)            a SurfaceGui text on its front
]]

local Neon = {}

Neon.Colors = table.freeze({
	Cyan = Color3.fromRGB(60, 225, 255),
	Pink = Color3.fromRGB(255, 80, 200),
	Purple = Color3.fromRGB(150, 100, 255),
	Yellow = Color3.fromRGB(255, 220, 60),
	Green = Color3.fromRGB(90, 255, 140),
	Orange = Color3.fromRGB(255, 140, 50),
})
Neon.Cycle = table.freeze({
	Neon.Colors.Cyan,
	Neon.Colors.Pink,
	Neon.Colors.Purple,
	Neon.Colors.Yellow,
	Neon.Colors.Green,
	Neon.Colors.Orange,
})
Neon.Sparkle = "rbxassetid://128453777673840" -- VFX IKEA sparkle (BumpFx uses it too)
Neon.Font = Enum.Font.FredokaOne
Neon.Outline = Color3.fromRGB(20, 10, 40)

function Neon.Part(parent: Instance, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, extra): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.Neon
	for key, value in extra or {} do
		p[key] = value
	end
	p.Parent = parent
	return p
end

function Neon.Sign(on: BasePart, text: string, color: Color3, background: Color3?, canvas: Vector2?): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.Brightness = 2.5
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = canvas or Vector2.new(600, 360)
	gui.Parent = on
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = background or Color3.new()
	label.BackgroundTransparency = background and 0 or 1
	label.Font = Neon.Font
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = color
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 5
	stroke.Color = Neon.Outline
	stroke.Parent = label
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.06, 0)
	padding.PaddingRight = UDim.new(0.06, 0)
	padding.PaddingTop = UDim.new(0.08, 0)
	padding.PaddingBottom = UDim.new(0.08, 0)
	padding.Parent = label
	return label
end

return Neon
