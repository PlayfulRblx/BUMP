--!nonstrict
--[[
	The UI kit's design tokens: every colour, size, shape and timing the game's screens use, by
	what it is for. Components ask for a role ("Accent", "Alert", "Title"), never a Color3 or a
	font, so changing how the game looks happens here and nowhere else.

	The look is ArcEngine's own: the language of its context input chips, carried across a whole
	HUD. Soft dark plates over the world: a warm near-black fill that is lit from the top, fully
	rounded ends, a drop shadow instead of an outline. Warm white Gotham for words, with a dark
	outline so it survives a bright sky. Colour is spent on meaning, as a small bar at a plate's
	edge and a faint tint in its fill: amber for what is yours or matters now, coral for being
	knocked out, gold for what you earn, and a colour per seat so four players tell apart. Things arrive with a small pop.

	The colours and the plate's lighting are read from the engine's chip tokens rather than
	copied, so the HUD stays in step with the chips beside it.

	Sizes are in layout units: the HUD root scales the whole layout to the screen from the base
	height in Tokens.Layout, which differs for a phone, so 14 here is not 14 pixels.

	Growing the kit means adding a line here: a new kind of text is one entry in Type, a new
	plate is one entry in Plates. Lives outside Components because FusionApp loads everything
	in there as a component.
]]

local ChipTokens = require("@Engine/Client/UIFusion/EngineComponents/Inputs/InputChipTokens")
local ContextTokens = require("@Engine/Client/UIFusion/EngineSystems/ContextInputActions/ContextInputTokens")

local Tokens = {}

local function gotham(weight: Enum.FontWeight): Font
	return Font.new("rbxasset://fonts/families/GothamSSm.json", weight)
end

-- ═══ colour ═══════════════════════════════════════════════════════════════════════

local tones = ContextTokens.ToneColors
local plate = ContextTokens.Scrim
local label = ContextTokens.Label

Tokens.Colors = table.freeze({
	-- Plates and what sits behind text.
	Plate = plate,
	PlateLift = plate:Lerp(label, 0.14),
	Ink = ContextTokens.LabelStroke,
	-- Words, and their quieter steps.
	White = label,
	Soft = label:Lerp(plate, 0.2),
	Muted = tones.Neutral,
	Faint = tones.Neutral:Lerp(plate, 0.45),
	-- Meaning. Accent is what is yours or matters now; Alert is death and danger.
	Accent = ContextTokens.EmphasisColor,
	Alert = tones.Danger,
	Positive = tones.Positive,
	Warning = tones.Warning,
	Info = tones.Info,
	Neutral = tones.Neutral,
	-- BUMP's own. Gold is the coin and everything earned; Silver and Bronze the other medals.
	Gold = Color3.fromRGB(255, 200, 64),
	GoldDeep = Color3.fromRGB(196, 132, 28),
	Silver = Color3.fromRGB(206, 214, 226),
	Bronze = Color3.fromRGB(214, 142, 92),
	-- The four seats, party-game style: each player's colour on their portrait ring, name tag
	-- and ball. Bright enough to tell apart at a glance, kept warm to sit with the chips.
	Seat1 = Color3.fromRGB(255, 92, 92),
	Seat2 = Color3.fromRGB(80, 156, 255),
	Seat3 = Color3.fromRGB(255, 206, 62),
	Seat4 = Color3.fromRGB(96, 214, 120),
	Seat5 = Color3.fromRGB(255, 150, 50),
	Seat6 = Color3.fromRGB(176, 110, 255),
	Seat7 = Color3.fromRGB(255, 120, 200),
	Seat8 = Color3.fromRGB(60, 214, 214),
	-- The power-ups (Shared/PowerUps/PowerUpInfo), on their icons and in the shop. The world's
	-- effects use the same colours (PowerUpInfo.Items[id].Color).
	PowerShield = Color3.fromRGB(90, 200, 255),
	PowerTurbo = Color3.fromRGB(255, 150, 50),
	PowerShockwave = Color3.fromRGB(190, 110, 255),
	PowerSecondChance = Color3.fromRGB(110, 230, 140),
	-- Each minigame's own colour (from its arena's edges), on its intro's title.
	GameBump = Color3.fromRGB(60, 226, 255),
	GameBomber = Color3.fromRGB(255, 170, 60),
	GameMeltdown = Color3.fromRGB(255, 78, 52),
})

-- A minigame's colour name ("GameBump"...); anything else is the accent.
function Tokens.GameColor(id: string?): string
	if type(id) == "string" and Tokens.Colors["Game" .. id] then
		return "Game" .. id
	end
	return "Accent"
end

-- A power-up's colour name ("PowerShield"...); anything else is the neutral ring.
function Tokens.PowerColor(id: string?): string
	if type(id) == "string" and Tokens.Colors["Power" .. id] then
		return "Power" .. id
	end
	return "Neutral"
end

-- How many contestants a game has (MoveConfig Rounds.Seats): lists are sized for this many.
Tokens.SeatCount = 8

-- A seat's colour name ("Seat1" to "Seat8"); anything else is the neutral ring.
function Tokens.SeatColor(seat: number?): string
	if type(seat) == "number" and Tokens.Colors["Seat" .. seat] then
		return "Seat" .. seat
	end
	return "Neutral"
end

-- A place's medal colour: gold, silver, bronze, then plain.
function Tokens.PlaceColor(place: number?): string
	return ({ "Gold", "Silver", "Bronze" })[place or 0] or "Muted"
end

-- 1 -> "1st", 2 -> "2nd"...
function Tokens.Ordinal(place: number): string
	local suffix = "th"
	local tens = place % 100
	if tens < 11 or tens > 13 then
		suffix = ({ "st", "nd", "rd" })[place % 10] or "th"
	end
	return tostring(place) .. suffix
end

function Tokens.Color(name: string): Color3
	local color = Tokens.Colors[name]
	assert(color, "Tokens.Color: no colour called " .. tostring(name))
	return color
end

-- ═══ type ═════════════════════════════════════════════════════════════════════════

-- The engine's chips are Gotham Medium with Gotham Bold capitals for headings; so is this.
Tokens.Fonts = table.freeze({
	Body = gotham(Enum.FontWeight.Medium),
	Strong = gotham(Enum.FontWeight.Bold),
	Display = gotham(Enum.FontWeight.Heavy),
	-- the knockout card's broadcast shout (HudKnockout)
	DisplayItalic = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy, Enum.FontStyle.Italic),
})

-- Font is a role in Tokens.Fonts. Caps sets the text in capitals.
Tokens.Type = table.freeze({
	Micro = table.freeze({ Size = 10, Font = "Strong", Caps = true }),
	Caption = table.freeze({ Size = 12, Font = "Strong", Caps = true }),
	Small = table.freeze({ Size = 12, Font = "Body" }),
	Body = table.freeze({ Size = 14, Font = "Body" }),
	Label = table.freeze({ Size = 14, Font = "Strong" }),
	Title = table.freeze({ Size = 18, Font = "Strong" }),
	Heading = table.freeze({ Size = 28, Font = "Display", Caps = true }),
	Hero = table.freeze({ Size = 50, Font = "Display", Caps = true }),
	-- A minigame's name on its intro card.
	Mega = table.freeze({ Size = 76, Font = "Display", Caps = true }),
	-- The intro's 3, 2, 1, GO!
	Giant = table.freeze({ Size = 150, Font = "Display", Caps = true }),
	DataSmall = table.freeze({ Size = 12, Font = "Strong" }),
	Data = table.freeze({ Size = 16, Font = "Strong" }),
	DataLarge = table.freeze({ Size = 26, Font = "Strong" }),
	DataHero = table.freeze({ Size = 44, Font = "Display" }),
})

-- What a piece of text is for. Each is a colour name for Tokens.Color.
Tokens.Text = table.freeze({
	Primary = "White",
	Soft = "Soft",
	Muted = "Muted",
	Faint = "Faint",
	Accent = "Accent",
	Alert = "Alert",
	Positive = "Positive",
	OnLight = "Ink",
})

-- The outline that lets pale text survive a bright scene: the chips' own, scaled to the text.
Tokens.TextStroke = table.freeze({
	Color = "Ink",
	Thickness = ContextTokens.LabelStrokeThickness,
	Transparency = ContextTokens.LabelStrokeTransparency,
	-- The size of text the full thickness is meant for; smaller text gets a thinner one.
	FullAtSize = 20,
	Thinnest = 0.9,
})

function Tokens.Font(role: string): Font
	local font = Tokens.Fonts[role]
	assert(typeof(font) == "Font", "Tokens.Font: no font role called " .. tostring(role))
	return font
end

-- Text as a Type kind sets it: in capitals, if the kind says so.
function Tokens.Set(text, kindName: string): string
	local kind = Tokens.Type[kindName]
	assert(kind, "Tokens.Set: no type called " .. tostring(kindName))
	text = tostring(text)
	if kind.Caps then
		text = string.upper(text)
	end
	return text
end

-- ═══ shape ════════════════════════════════════════════════════════════════════════

Tokens.Space = table.freeze({ XS = 4, S = 8, M = 12, L = 16, XL = 24, XXL = 40 })

-- Ends are fully round where a thing is a chip; panels and slots are soft.
Tokens.Radius = table.freeze({
	Pill = UDim.new(1, 0),
	Panel = UDim.new(0, 14),
	Slot = UDim.new(0, 12),
	Small = UDim.new(0, 6),
})

-- The tone bar at a plate's edge, and rules.
Tokens.Line = table.freeze({ Rule = 2, Bar = 4 })

--[[
	Plates. Tone is a colour name mixed into the fill by Tint; Transparency is the fill's.
	Stroke outlines the plate in its tone, which the chips keep for emphasis only.
]]
Tokens.Plates = table.freeze({
	Plate = table.freeze({ Tint = 0, Transparency = ContextTokens.FillTransparency.Rest }),
	Lifted = table.freeze({ Tone = "White", Tint = 0.14, Transparency = 0.1 }),
	Accent = table.freeze({
		Tone = "Accent",
		Tint = ContextTokens.FillTint.Emphasis,
		Transparency = ContextTokens.FillTransparency.Emphasis,
		Stroke = true,
	}),
	Alert = table.freeze({
		Tone = "Alert",
		Tint = ContextTokens.FillTint.Emphasis,
		Transparency = ContextTokens.FillTransparency.Emphasis,
		Stroke = true,
	}),
	-- An empty place something goes: there, but out of the way.
	Hollow = table.freeze({ Tint = 0, Transparency = 0.62 }),
	Clear = table.freeze({ Tint = 0, Transparency = 1 }),
})

-- The top-lit gradient every plate wears, straight from the chips.
Tokens.PlateLight = table.freeze({
	Color = ColorSequence.new(ChipTokens.FillGradient.TopColor, ChipTokens.FillGradient.BottomColor),
	Transparency = NumberSequence.new(ChipTokens.FillGradient.TopTransparency, ChipTokens.FillGradient.BottomTransparency),
})

Tokens.StrokeTransparency = ContextTokens.StrokeTransparency.Emphasis

-- Depth. The chips skip it on phones, where fill rate matters more; the HUD root turns it off
-- there with Tokens.SetShadows before it builds.
Tokens.Shadow = table.freeze({
	Blur = ChipTokens.Shadow.BlurRadius,
	OffsetY = ChipTokens.Shadow.OffsetY,
	Transparency = ChipTokens.Shadow.Transparency,
})

local shadows = true

function Tokens.SetShadows(on: boolean)
	shadows = on == true
end

function Tokens.Shadows(): boolean
	return shadows
end

-- ═══ time ═════════════════════════════════════════════════════════════════════════

Tokens.Timing = table.freeze({

	-- A banner (zone warning, elimination) holds this long.
	BannerSeconds = 3.4,
	-- Your knockout card (HudKnockout): ELIMINATED! at once, who did it this many seconds in
	-- (when the knockout camera swings to them: KnockoutCam's SELF_SECONDS 1.4 plus a beat), and
	-- the card gone after KnockoutSeconds.
	KnockoutReveal = 1.5,
	KnockoutSeconds = 3.7,
	-- How long a lost amount lingers as a ghost before it drains (meters).
	DamageTrailSeconds = 0.45,
	-- Seconds left in a game at which the timer starts to warn.
	UrgentSeconds = 10,
	-- How far a number or a slot swells when it changes (0.1 is a tenth bigger).
	Pop = 0.1,
	-- The intro's countdown: its last this-many seconds count 3, 2, 1 (MoveConfig
	-- Rounds.IntroCountdown); before that, the title card and the letterbox.
	CountdownFrom = 3,
	-- The title card is up while more than this many seconds of the intro are left (the camera's
	-- sweep); the lineup of contestants after it has the screen to itself.
	TitleUntil = 9.5, -- (was 6, before the intro doubled to 14 s)
	-- How long GO! stays up once play starts.
	GoSeconds = 0.9,
})

-- ═══ layout ═══════════════════════════════════════════════════════════════════════

-- Where the HUD's blocks sit, by device. Base is the layout's height in units: the HUD root
-- scales so the screen is exactly that tall, so a smaller Base makes everything bigger. A
-- phone gets its own table because a desktop layout shrunk to a phone is unreadable, and
-- because its bottom corners belong to the thumbstick and the touch buttons.
Tokens.Layout = table.freeze({
	Desktop = table.freeze({
		Base = 720,
		Margin = 24,
		Shadows = true,
		-- Top centre: which game, the time left and who is still in.
		Status = table.freeze({ Anchor = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 16), Width = 420 }),
		-- Under it: a game's line of the moment (who has the bomb).
		Note = table.freeze({ Anchor = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 88), Width = 320 }),
		-- Top right: your saved gold, and under it the four seats.
		Gold = table.freeze({ Anchor = Vector2.new(1, 0), Position = UDim2.new(1, -24, 0, 18) }),
		Players = table.freeze({ Anchor = Vector2.new(1, 0), Position = UDim2.new(1, -24, 0, 104), Width = 220, Row = 34 }),
		-- The middle: intro card, results, standings, the lobby's count.
		Card = table.freeze({ Position = UDim2.new(0.5, 0, 0.47, 0), Width = 620 }),
		Banner = table.freeze({ Position = UDim2.new(0.5, 0, 0.4, 0), Width = 560 }),
		-- ELIMINATED BY X: cartoon broadcast bars sweeping in from the left edge, clear of the
		-- knockout camera's shot in the middle (HudKnockout); Position is the card's bottom left
		Knockout = table.freeze({ Position = UDim2.new(0, 0, 1, -128), Scale = 1 }),
		-- everyone else's eliminations, top left (HudFeed)
		Feed = table.freeze({ Anchor = Vector2.new(0, 0), Position = UDim2.new(0, 24, 0, 104), Width = 300 }),
		-- Bottom centre, above nothing: the bottom left is the engine's tray of input chips.
		Charge = table.freeze({ Anchor = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -110), Width = 240 }),
		-- Under the gold: your level and how far into it you are. The seats sit under that.
		Level = table.freeze({ Anchor = Vector2.new(1, 0), Position = UDim2.new(1, -24, 0, 62), Width = 150 }),
		-- Bottom right: the shop button between games, the power-up you hold during one.
		ShopButton = table.freeze({ Anchor = Vector2.new(1, 1), Position = UDim2.new(1, -24, 1, -24), Width = 130, Key = "B" }),
		PowerUp = table.freeze({ Anchor = Vector2.new(1, 1), Position = UDim2.new(1, -24, 1, -24), Width = 210, Key = "Q" }),
		-- The shop, over the middle.
		Shop = table.freeze({ Position = UDim2.new(0.5, 0, 0.5, 0), Width = 640, Row = 72 }),
		-- A game's intro: the title card high in the middle, the countdown at the centre, cinema
		-- bars top and bottom during the flyover, the game's controls along the bottom.
		Title = table.freeze({ Position = UDim2.new(0.5, 0, 0.3, 0), Width = 900 }),
		Countdown = table.freeze({ Position = UDim2.new(0.5, 0, 0.27, 0) }), -- above your head (the gameplay camera puts it about 0.45)
		Letterbox = table.freeze({ Height = 64 }),
		Controls = table.freeze({ Position = UDim2.new(0.5, 0, 1, -96) }),
		-- your name card in your moment of the intro (HudHero): low on the left, clear of you
		Hero = table.freeze({ Position = UDim2.new(0, 70, 0.7, 0), Width = 760 }),
	}),
	Phone = table.freeze({
		Base = 400,
		Margin = 12,
		Shadows = false,
		Status = table.freeze({ Anchor = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6), Width = 300, Compact = true }),
		Note = table.freeze({ Anchor = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 62), Width = 240, Compact = true }),
		Gold = table.freeze({ Anchor = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 8) }),
		-- Under Roblox's own menu buttons on the left: the right is busy with the gold and the
		-- touch buttons further down.
		Players = table.freeze({ Anchor = Vector2.new(0, 0), Position = UDim2.new(0, 12, 0, 52), Width = 140, Row = 24, Compact = true }),
		Card = table.freeze({ Position = UDim2.new(0.5, 0, 0.5, 0), Width = 430 }),
		Banner = table.freeze({ Position = UDim2.new(0.5, 0, 0.44, 0), Width = 420 }),
		Knockout = table.freeze({ Position = UDim2.new(0, 0, 1, -96), Scale = 0.62, Compact = true }),
		Feed = table.freeze({ Anchor = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 52), Width = 220, Compact = true }),
		Charge = table.freeze({ Anchor = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Width = 180 }),
		Level = table.freeze({ Anchor = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 40), Width = 120, Compact = true }),
		-- Top right under the level: the bottom right belongs to the touch buttons.
		ShopButton = table.freeze({ Anchor = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 70), Width = 100 }),
		PowerUp = table.freeze({ Anchor = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 70), Width = 150, Compact = true }),
		Shop = table.freeze({ Position = UDim2.new(0.5, 0, 0.5, 0), Width = 440, Row = 60, Compact = true }),
		Title = table.freeze({ Position = UDim2.new(0.5, 0, 0.32, 0), Width = 600, Compact = true }),
		Countdown = table.freeze({ Position = UDim2.new(0.5, 0, 0.28, 0), Compact = true }),
		Letterbox = table.freeze({ Height = 36 }),
		Controls = table.freeze({ Position = UDim2.new(0.5, 0, 1, -60), Compact = true }),
		Hero = table.freeze({ Position = UDim2.new(0, 30, 0.7, 0), Width = 440, Compact = true }),
	}),
})

return Tokens
