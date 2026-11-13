--!nonstrict
--[[
	BUMP's UI theme.

	The engine's FusionTheme hands over to this module when it exists
	(ArcEngine/src/Client/UIFusion/EngineSystems/Core/FusionTheme.lua), so every game
	must provide one. This started as a copy of the engine's default light/dark theme:
	restyle it freely, but keep the group and key names, which engine components read.
]]

local Maid = require("@Lib/Maid")
local SettingsHandler = require("@Engine/Shared/Handlers/SettingsHandler/SettingsHandler")
local CashShopPalettes = require("@Engine/Client/UIFusion/EngineSystems/Core/FusionThemeCashShopPalettes")

-- Types for intellisense
export type ThemeName = "DefaultLight" | "DefaultDark"

-- If you have a concrete type (e.g. Fusion.StateObject<T>), use that here instead of any
export type State<T> = any

export type TextGroup = {
	Title: State<Color3>,
	Main: State<Color3>,
	Muted: State<Color3>,
	Inverse: State<Color3>,
	Subtle: State<Color3>,

	White: State<Color3>,
	Black: State<Color3>,
}

export type SurfaceGroup = {
	Base: State<Color3>,
	Light: State<Color3>,
	Dark: State<Color3>,
	Primary: State<Color3>,
	Secondary: State<Color3>,
	Muted: State<Color3>,
	Unavailable: State<Color3>,
	Title: State<Color3>,
	ShadowLow: State<Color3>,
	ShadowHigh: State<Color3>,
	TopBarLeft: State<Color3>,
	TopBarRight: State<Color3>,
	Accent: State<Color3>,

	Black: State<Color3>,
	White: State<Color3>,

	Red: State<Color3>,
}

export type AccentGroup = {
	Primary: State<Color3>,
	Secondary: State<Color3>,
	Highlight: State<Color3>,
}

export type CurrencyGroup = {
	Soft: State<Color3>,
	Hard: State<Color3>,

	Robux: State<Color3>,
}

export type FeedbackGroup = {
	Success: State<Color3>,
	Error: State<Color3>,
	Warning: State<Color3>,
	Timer: State<Color3>,
}

export type ButtonGroup = {
	Primary: State<Color3>,
	Secondary: State<Color3>,
	Warning: State<Color3>,
	Neutral: State<Color3>,
	Inactive: State<Color3>,
	Unavailable: State<Color3>,
	Highlight: State<Color3>,
}

export type StateGroup = {
	Selected: State<Color3>,
	Special: State<Color3>,
	Disabled: State<Color3>,
}

export type AbsoluteColors = {
	White: State<Color3>,
	Black: State<Color3>,
	Robux: State<Color3>,
	Error: State<Color3>,
	Success: State<Color3>,
}

export type TransparencyGroup = {
	None: State<number>,
	Low: State<number>,
	Partial: State<number>,
	Half: State<number>,
	High: State<number>,
	Full: State<number>,
}

export type CashShopPalette = {
	Top: State<Color3>,
	Bottom: State<Color3>,
	Accent: State<Color3>,
	CardTop: State<Color3>,
	CardMid: State<Color3>,
	CardBottom: State<Color3>,
}

export type CashShopGroup = {
	Palettes: { [string]: CashShopPalette },
}

export type Theme = {
	Text: TextGroup,
	Surface: SurfaceGroup,
	Accent: AccentGroup,
	Currency: CurrencyGroup,
	Feedback: FeedbackGroup,
	Button: ButtonGroup,
	State: StateGroup,
	AbsoluteColors: AbsoluteColors,
	Fonts: {
		Default: Enum.Font,
		Web: Enum.Font,
	},
	SetTheme: (themeName: ThemeName) -> (),
	CurrentTheme: State<ThemeName>,
	Transparency: TransparencyGroup,
	CashShop: CashShopGroup,
}

local THEMES = {
	DefaultLight = {
		Text = {
			Title = Color3.fromRGB(30, 30, 35),
			Main = Color3.fromRGB(45, 45, 55),
			Muted = Color3.fromRGB(90, 90, 105),
			Inverse = Color3.fromRGB(255, 255, 255),
			Subtle = Color3.fromRGB(220, 220, 220),
			Outline = Color3.fromRGB(40, 40, 50),

			White = Color3.fromRGB(235, 235, 245),
			Black = Color3.fromRGB(45, 45, 55),

			Brown = Color3.fromRGB(85, 65, 40),

			Coloured = Color3.fromRGB(85, 65, 40),
		},

		Surface = {
			Base = Color3.fromRGB(255, 255, 255),
			Light = Color3.fromRGB(250, 250, 255),
			Dark = Color3.fromRGB(240, 245, 255),
			Primary = Color3.fromRGB(255, 255, 255),
			Secondary = Color3.fromRGB(250, 250, 255),
			Muted = Color3.fromRGB(235, 238, 248),
			Unavailable = Color3.fromRGB(160, 160, 170),
			Title = Color3.fromRGB(85, 170, 127),
			ShadowLow = Color3.fromRGB(200, 200, 210),
			ShadowHigh = Color3.fromRGB(160, 160, 170),
			TopBarLeft = Color3.fromRGB(0, 220, 255),
			TopBarRight = Color3.fromRGB(255, 80, 200),

			Outline = Color3.fromRGB(253, 170, 16),
			Accent = Color3.fromRGB(85, 170, 127),

			Black = Color3.fromRGB(25, 25, 35),
			White = Color3.fromRGB(235, 235, 245),

			Red = Color3.fromRGB(255, 85, 100),

			Gold = Color3.fromRGB(239, 187, 98),
		},

		Accent = {
			Primary = Color3.fromRGB(0, 180, 255), -- Cyan-blue highlight
			Secondary = Color3.fromRGB(255, 100, 220), -- Magenta glow
			Highlight = Color3.fromRGB(255, 225, 85), -- Gold highlight

			TopAccent = Color3.fromRGB(255, 187, 0),
			BottomAccent = Color3.fromRGB(255, 145, 0),
		},

		Currency = {
			Soft = Color3.fromRGB(90, 255, 150), -- Mint
			Hard = Color3.fromRGB(255, 130, 250), -- Premium pink

			Robux = Color3.fromRGB(102, 255, 0),
		},

		Feedback = {
			Success = Color3.fromRGB(60, 220, 120),
			Error = Color3.fromRGB(255, 60, 85),
			Warning = Color3.fromRGB(255, 200, 60),
			Timer = Color3.fromRGB(52, 152, 219),
		},

		Button = {
			Primary = Color3.fromRGB(0, 230, 100), -- Confirm
			Secondary = Color3.fromRGB(255, 80, 80), -- Cancel
			Warning = Color3.fromRGB(255, 200, 60), -- Back/DataButton
			Neutral = Color3.fromRGB(235, 235, 245),
			Inactive = Color3.fromRGB(160, 160, 170),
			Unavailable = Color3.fromRGB(160, 160, 170),
			Highlight = Color3.fromRGB(255, 80, 200), -- Active glow/pulse
			Back = Color3.fromRGB(253, 170, 16),
			Close = Color3.fromRGB(255, 60, 85),
		},

		State = {
			Selected = Color3.fromRGB(0, 180, 255),
			Special = Color3.fromRGB(255, 225, 85),
			Disabled = Color3.fromRGB(210, 210, 220),
		},

		Transparency = {
			None = 0,
			Low = 0.1,
			Partial = 0.2,
			Half = 0.5,
			High = 0.7,
			Full = 1,
		},
	},

	DefaultDark = {
		Text = {
			Title = Color3.fromRGB(255, 255, 255),
			Main = Color3.fromRGB(235, 235, 245),
			Muted = Color3.fromRGB(180, 180, 190),
			Inverse = Color3.fromRGB(40, 40, 50),
			Subtle = Color3.fromRGB(120, 120, 130),
			Outline = Color3.fromRGB(220, 220, 220),

			White = Color3.fromRGB(235, 235, 245),
			Black = Color3.fromRGB(45, 45, 55),

			Brown = Color3.fromRGB(85, 65, 40),

			Coloured = Color3.fromRGB(186, 162, 112),
		},

		Surface = {
			Base = Color3.fromRGB(25, 25, 35),
			Light = Color3.fromRGB(35, 35, 45),
			Dark = Color3.fromRGB(15, 15, 25),
			Primary = Color3.fromRGB(25, 25, 35),
			Secondary = Color3.fromRGB(35, 35, 45),
			Muted = Color3.fromRGB(32, 32, 42),
			Unavailable = Color3.fromRGB(90, 90, 100),
			Title = Color3.fromRGB(85, 170, 127),
			ShadowLow = Color3.fromRGB(60, 60, 70),
			ShadowHigh = Color3.fromRGB(90, 90, 100),
			TopBarLeft = Color3.fromRGB(0, 180, 255),
			TopBarRight = Color3.fromRGB(255, 100, 200),

			Outline = Color3.fromRGB(253, 170, 16),
			Accent = Color3.fromRGB(85, 170, 127),

			Black = Color3.fromRGB(25, 25, 35),
			White = Color3.fromRGB(235, 235, 245),

			Red = Color3.fromRGB(255, 85, 100),

			Gold = Color3.fromRGB(239, 187, 98),
		},

		Accent = {
			Primary = Color3.fromRGB(0, 180, 255),
			Secondary = Color3.fromRGB(255, 100, 200),
			Highlight = Color3.fromRGB(255, 225, 85),

			TopAccent = Color3.fromRGB(255, 187, 0),
			BottomAccent = Color3.fromRGB(255, 145, 0),
		},

		Currency = {
			Soft = Color3.fromRGB(90, 255, 150),
			Hard = Color3.fromRGB(255, 130, 250),

			Robux = Color3.fromRGB(102, 255, 0),
		},

		Feedback = {
			Success = Color3.fromRGB(80, 255, 150),
			Error = Color3.fromRGB(255, 85, 100),
			Warning = Color3.fromRGB(255, 200, 60),
			Timer = Color3.fromRGB(0, 180, 255),
		},

		Button = {
			Primary = Color3.fromRGB(0, 230, 100),
			Secondary = Color3.fromRGB(255, 80, 80),
			Warning = Color3.fromRGB(255, 200, 60),
			Neutral = Color3.fromRGB(60, 60, 70),
			Inactive = Color3.fromRGB(90, 90, 100),
			Unavailable = Color3.fromRGB(90, 90, 100),
			Highlight = Color3.fromRGB(255, 80, 200),
			Back = Color3.fromRGB(253, 170, 16),
			Close = Color3.fromRGB(255, 60, 85),
		},

		State = {
			Selected = Color3.fromRGB(0, 180, 255),
			Special = Color3.fromRGB(255, 225, 85),
			Disabled = Color3.fromRGB(90, 90, 100),
		},

		Transparency = {
			None = 0,
			Low = 0.1,
			Partial = 0.2,
			Half = 0.5,
			High = 0.7,
			Full = 1,
		},
	},
}

local themeMethod = function(scope): Theme
	local maid = Maid.new()
	local isAlive = true
	table.insert(scope, function()
		isAlive = false
		maid:Destroy()
	end)
	-- CoreProfileData defaults _darkThemeEnabled to false, so startup begins in the light theme.
	local themeValue = scope:Value("DefaultLight") :: State<ThemeName>

	local function makeColorSprings(categoryName)
		local springs = {}
		for colorName, _ in pairs(THEMES.DefaultLight[categoryName]) do
			local targetColor = scope:Computed(function(use)
				local themeName = scope.peek(use(themeValue))
				return THEMES[themeName][categoryName][colorName]
			end)
			springs[colorName] = scope:Spring(targetColor, 35, 1)
		end
		return springs
	end

	local function makeTransparencyStates()
		local states = {}
		for transparencyName in pairs(THEMES.DefaultLight.Transparency) do
			states[transparencyName] = scope:Computed(function(use)
				local themeName = scope.peek(use(themeValue))
				return THEMES[themeName].Transparency[transparencyName]
			end)
		end
		return states
	end

	local theme = {
		Text = makeColorSprings("Text") :: TextGroup,
		Surface = makeColorSprings("Surface") :: SurfaceGroup,
		Accent = makeColorSprings("Accent") :: AccentGroup,
		Currency = makeColorSprings("Currency") :: CurrencyGroup,
		Feedback = makeColorSprings("Feedback") :: FeedbackGroup,
		Button = makeColorSprings("Button") :: ButtonGroup,
		State = makeColorSprings("State") :: StateGroup,

		AbsoluteColors = ({
			White = scope:Value(Color3.fromRGB(255, 255, 255)),
			Black = scope:Value(Color3.fromRGB(36, 35, 31)),
			Robux = scope:Value(Color3.fromRGB(255, 215, 0)),
			Error = scope:Value(Color3.fromRGB(255, 50, 50)),
			Success = scope:Value(Color3.fromRGB(74, 198, 85)),
		} :: any) :: AbsoluteColors,

		Fonts = {
			Default = Enum.Font.FredokaOne,
			Web = Enum.Font.TitilliumWeb,
		},

		SetTheme = function(themeName: ThemeName)
			assert(THEMES[themeName], `"${themeName}" is not a valid theme.`)
			themeValue:set(themeName)
		end,

		CurrentTheme = themeValue,
		Transparency = makeTransparencyStates() :: TransparencyGroup,
		CashShop = {
			Palettes = CashShopPalettes.ToThemeStates(scope),
		} :: CashShopGroup,
	} :: Theme

	task.defer(function()
		if not isAlive then
			return
		end

		local ok, subscription = pcall(
			SettingsHandler.SubscribeToPlayerSetting,
			game.Players.LocalPlayer,
			"_darkThemeEnabled",
			function(value)
				if isAlive then
					theme.SetTheme(value and "DefaultDark" or "DefaultLight")
				end
			end
		)

		if not ok or subscription == nil then
			return
		end

		if isAlive then
			maid:GiveTask(subscription)
		elseif type(subscription.Destroy) == "function" then
			subscription:Destroy()
		end
	end)

	return theme
end

return themeMethod
