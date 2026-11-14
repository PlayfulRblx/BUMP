--!nonstrict
--[[
	What every story on the style board shares: the kit's pieces on the story's scope, the
	backdrop control, and a stage to put things on.

	    local StoryKit = require("@Client/UIFusion/Stories/StoryKit")
	    controls = StoryKit.Controls({ Device = UILabs.Choose(StoryKit.DeviceNames, 1) })
	    story = function(props)
	        StoryKit.Stage(props, function(scope, stage) return scope:UiText({ ... }) end)
	    end

	The stage's backdrop is there to judge the plates and their text against bright and dark
	scenes: the HUD draws over the live world.
]]

local StoryDeps = require("@Client/UIFusion/Stories/StoryDeps")
local Tokens = require("@UIFusion/Kit/Tokens")

local Fusion = StoryDeps.Fusion
local UILabs = StoryDeps.UILabs

local Children = Fusion.Children

local StoryKit = {}

StoryKit.BackdropNames = { "Sky", "Grass", "Night", "White" }
StoryKit.DeviceNames = { "Desktop", "Phone" }

-- The screens the HUD is judged at, in pixels.
StoryKit.Devices = {
	Desktop = Vector2.new(1280, 720),
	Phone = Vector2.new(844, 390),
}

local BACKDROPS = {
	Sky = { Color3.fromRGB(146, 194, 232), Color3.fromRGB(226, 210, 172) },
	Grass = { Color3.fromRGB(78, 150, 84), Color3.fromRGB(32, 70, 40) },
	Night = { Color3.fromRGB(18, 22, 38), Color3.fromRGB(4, 5, 9) },
	White = { Color3.fromRGB(248, 248, 248), Color3.fromRGB(236, 236, 236) },
}

-- The controls every story has, plus the story's own.
function StoryKit.Controls(extra)
	local controls = {
		Backdrop = UILabs.Choose(StoryKit.BackdropNames, 2),
	}
	for name, control in pairs(extra or {}) do
		controls[name] = control
	end
	return controls
end

local function skip(moduleScript: ModuleScript): boolean
	local name = moduleScript.Name
	return name == "init" or name:match("%.spec$") ~= nil or name:match("%.story$") ~= nil
end

-- A scope with every game component on it, as FusionApp builds for the game's own UI. The
-- components have to be part of the scope's methods, not fields added to UI Labs' scope:
-- pieces build their insides on inner scopes, which only inherit methods. It is cleaned up
-- with `parent`.
function StoryKit.Scope(parent)
	local components = {}
	local folder = script.Parent.Parent:WaitForChild("Components")
	for _, moduleScript in ipairs(folder:GetDescendants()) do
		if moduleScript:IsA("ModuleScript") and not skip(moduleScript) then
			components[moduleScript.Name] = require(moduleScript)
		end
	end
	local scope = Fusion.scoped(Fusion, components)
	table.insert(parent, scope)
	return scope
end

--[[
	Fills the story's target with a backdrop and builds the story on it.

	build(scope, stage) returns what goes on the stage. `stage` is { Device = name or nil,
	Viewport = Vector2, Root = the stage's frame }. With a Device control the stage is a frame
	of that device's size, scaled to fit the target; without one it is the whole target.
	Returns the outer frame.
]]
function StoryKit.Stage(props, build)
	local scope = StoryKit.Scope(props.scope)
	local controls = props.controls

	local size = scope:Value(Vector2.new(1280, 720))
	local outer = scope:New("Frame")({
		Name = "Stage",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = props.target,
		[Children] = {
			scope:New("UIGradient")({
				Rotation = 90,
				Color = scope:Computed(function(use)
					local pair = BACKDROPS[use(controls.Backdrop)] or BACKDROPS.Grass
					return ColorSequence.new(pair[1], pair[2])
				end),
			}),
			scope:Computed(function(use, inner)
				local device = controls.Device and use(controls.Device) or nil
				Tokens.SetShadows(device ~= "Phone")
				if not device then
					return build(inner, { Viewport = use(size) })
				end
				local viewport = StoryKit.Devices[device] or StoryKit.Devices.Desktop
				return inner:New("Frame")({
					Name = device,
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromOffset(viewport.X, viewport.Y),
					BackgroundTransparency = 1,
					ClipsDescendants = true,
					[Children] = {
						inner:New("UIScale")({
							Scale = inner:Computed(function(useInner)
								local room = useInner(size)
								return math.max(math.min((room.X - 24) / viewport.X, (room.Y - 24) / viewport.Y), 0.1)
							end),
						}),
						-- The edge of the device's screen.
						inner:New("UIStroke")({
							Thickness = 1,
							Color = Color3.new(1, 1, 1),
							Transparency = 0.7,
							ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
						}),
						build(inner, { Device = device, Viewport = viewport }),
					},
				})
			end),
		},
	})
	local function measure()
		local absolute = outer.AbsoluteSize
		if absolute.X > 0 and absolute.Y > 0 then
			size:set(absolute)
		end
	end
	local connection = outer:GetPropertyChangedSignal("AbsoluteSize"):Connect(measure)
	table.insert(scope, function()
		connection:Disconnect()
	end)
	measure()
	return outer
end

-- A scrolling page of sections, for stories that are a catalogue rather than a screen.
function StoryKit.Page(scope, sections)
	return scope:New("ScrollingFrame")({
		Name = "Page",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Color3.new(1, 1, 1),
		ScrollBarImageTransparency = 0.5,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		[Children] = {
			scope:New("UIPadding")({
				PaddingTop = UDim.new(0, 28),
				PaddingBottom = UDim.new(0, 40),
				PaddingLeft = UDim.new(0, 32),
				PaddingRight = UDim.new(0, 32),
			}),
			scope:New("UIListLayout")({
				FillDirection = Enum.FillDirection.Vertical,
				Padding = UDim.new(0, 30),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			sections,
		},
	})
end

-- A titled row of specimens that wraps.
function StoryKit.Section(scope, order: number, title: string, note: string?, specimens)
	return scope:New("Frame")({
		Name = title,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = order,
		[Children] = {
			scope:New("UIListLayout")({
				FillDirection = Enum.FillDirection.Vertical,
				Padding = UDim.new(0, 10),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			scope:UiText({ Text = title, Type = "Title", Role = "Primary", Align = "Left", LayoutOrder = 1 }),
			note and scope:UiText({ Text = note, Type = "Small", Role = "Soft", Align = "Left", LayoutOrder = 2 }) or nil,
			scope:UiLine({ Tone = "White", Transparency = 0.6, LayoutOrder = 3 }),
			scope:New("Frame")({
				Name = "Specimens",
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				LayoutOrder = 4,
				[Children] = {
					scope:New("UIListLayout")({
						FillDirection = Enum.FillDirection.Horizontal,
						Wraps = true,
						Padding = UDim.new(0, 22),
						VerticalAlignment = Enum.VerticalAlignment.Top,
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
					specimens,
				},
			}),
		},
	})
end

-- One specimen: a fixed box with the piece in it and a caption under it.
function StoryKit.Specimen(scope, order: number, caption: string, size: Vector2, piece)
	return scope:New("Frame")({
		Name = caption,
		Size = UDim2.fromOffset(size.X, size.Y + 22),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		[Children] = {
			scope:New("Frame")({
				Name = "Box",
				Size = UDim2.fromOffset(size.X, size.Y),
				BackgroundTransparency = 1,
				[Children] = { piece },
			}),
			scope:UiText({
				Text = caption,
				Type = "Micro",
				Role = "Muted",
				Align = "Left",
				Position = UDim2.fromOffset(0, size.Y + 8),
				Size = UDim2.new(1, 0, 0, 12),
			}),
		},
	})
end

return StoryKit
