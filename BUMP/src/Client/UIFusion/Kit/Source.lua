--!nonstrict
--[[
	How the HUD reads the match. A source is anything with three functions:

	    source.Get(key)                         -- the value now
	    source.Subscribe(function(key, value))  -- every change; returns an unsubscribe
	    source.On(event, function(data))        -- things that happen; returns an unsubscribe
	    source.Do(action, id?)                  -- what the HUD asks for (the shop): "ShopBuy",
	                                            -- "ShopEquip", "ShopToggle", "ShopClose",
	                                            -- "PowerUse"

	The HUD never knows whether it is watching a real round or the fake one the style board
	plays (Kit/FakeRound), which is what lets the board show the real HUD.

	Values the HUD reads:
	    Phase        "Practice" (the test yard, no round) | "Lobby" | "Intermission" | "Intro" | "Play"
	                 | "Results" | "Standings"
	    NextMinigame the coming game's card (as Minigame), during the Intermission
	    Countdown    seconds left in Lobby, Intermission or Intro
	    GameIndex, GameCount   which game of the playlist this is (2 of 5)
	    Minigame     { Id, Title, Blurb, Controls = { { Key, Label }, ... } }
	    TimeLeft     seconds left in the game being played
	    Note         a line in place of the clock ("Zippy has the bomb!"), "" for none
	    Alive, Total how many are still in this game, and how many started it
	    Players      the seats, in seat order: { Id, Name, UserId?, Seat (1 to 4), Gold (this
	                 session), Out (knocked out of this game), You, Bot }
	    Results      the game just played, best first: { Name, UserId?, Seat, Place, Gold (earned),
	                 You }
	    Standings    the whole session, best first: { Name, UserId?, Seat, Rank, Gold, Wins, You }
	    MyGold       your saved gold
	    Charge       0 to 1 while a dash is charging (BUMP), else 0
	    MyXp, MyLevel, MyXpInto, MyXpNeed   your saved XP, the level it makes, and how far
	                 into that level you are of how much it needs (Shared/PowerUps/PowerUpInfo)
	    PowerUps     the power-ups you own: { [id] = level }
	    Equipped     the one you bring into games, "" for none
	    Power        the one you hold in this game: { Id, Level, Used }, or false
	    ShopOpen     whether the shop is showing (source.Do "ShopToggle" / "ShopClose")
	    IntroHero    true while a game's intro camera is on you (Client/Systems/RoundIntro): your
	                 name card (HudHero)
	    Catalogue    the shop's power-ups in order: { Id, Name, Glyph, Blurb, Automatic, Prices
	                 (gold per level), Gates (player level per level), Describe (per level) }
	Results entries also carry Xp (earned, players only).
	Events:
	    KnockedOut   { Place, Total, Gold, Reason, By?, BySeat?, ById? }: you are out of this game
	                 (By: who knocked you off or passed you the bomb)
	    Eliminated   { Name, Seat, Reason, By?, BySeat? }: someone else is out (HudFeed)
	    GoldEarned   { Amount }: gold you just earned
	    XpEarned     { Amount, Level, LeveledUp }: XP you just earned
	    ShopReply    { Ok, Message, Id }: the server's answer to a buy or equip
]]

local Source = {}

-- A Fusion value that follows one key of a source for as long as `scope` lives.
function Source.Value(scope, source, key: string, default)
	local current = source.Get(key)
	if current == nil then
		current = default
	end
	local value = scope:Value(current)
	table.insert(scope, source.Subscribe(function(changed, new)
		if changed == key then
			if new == nil then
				new = default
			end
			value:set(new)
		end
	end))
	return value
end

-- Calls back on an event for as long as `scope` lives.
function Source.On(scope, source, event: string, callback)
	table.insert(scope, source.On(event, callback))
end

return Source
