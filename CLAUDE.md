# BUMP: instructions for Claude sessions

A Roblox game on ArcEngine: a party game in the spirit of Mario Party, where players move with
Super Mario Odyssey style platformer controls and play a series of minigames; winning a minigame
earns gold. Settled with the user (2026-11-13): 4 players (since raised to 8 seats, bots filling:
see "Eight seats and the bots' minds"); minigames back to back with no board (they
turned down a board); the first controls stage has the core jumps (single/double/triple, long
jump, backflip, ground pound, wall jump), dive and roll, and a Bump shove. They did not pick a
thrown hat. Gold buys power-ups and their upgrades (settled 2026-11-13). Ask rather than guess.

**Where the build is:** controls, rounds with bots, three minigames (BUMP, Bomber Bloxians, MELTDOWN), the
UI kit, power-ups and progression bought with gold (see "Power-ups and progression"), and the lobby: AR's neon city hub with the arena in its middle (see "The lobby"). Every number is
a first guess until the user has played it: build a stage, measure it in Play, stop and say what
to try.

## Movement

| File | What it does |
| --- | --- |
| `Shared/Movement/MoveConfig.lua` | Every movement number |
| `Shared/Movement/Tuning.lua` | `Tuning.Of("Jump").Single` reads live. In Studio every number is an attribute on `ReplicatedStorage.BumpTuning`, editable in Properties (Server view) while playing |
| `Shared/Movement/Remotes.lua` | `Bump:Act` (client: "Move", "Bump"), `Bump:You` ("Knock"), `Bump:Fx` ("Bump") |
| `Client/Systems/Platformer.lua` | The controller: a move state machine on your own character. A planar LinearVelocity owns horizontal speed, an AlignOrientation owns facing, jumps write vertical speed; the stock jump and AutoRotate are off |
| `Shared/Movement/Moves.lua` | Which moves are on the ground, locked, or can float-jump, and what each button would do from a move (the input chips' labels): pure functions of a view of the controller's state (`Platformer`'s `view()`), with a spec |
| `Client/Systems/Animator.lua` | Plays a clip on every body (players and dummies) on every client: your own move from Platformer, others' from `BumpMove`. Pulls `Transform` on each joint (Motor6D or the newer AnimationConstraint) over Roblox's Animate. Move to clip table at its top |
| `Shared/Movement/Clips.lua`, `AnimationData/` | Clips as data. `Core.lua` is generated from `animation/` (see `animation/README.md`); `Imported.lua` is Playful's Run, copied from The Scramble |
| `Client/Systems/BumpFx.lua` | The effects of moves (OnMove, from the Animator) and the wiring of the server's Fx events to `Client/Fx`: `FxKit` (emitters, bursts, glow parts, streaks, comic words, sounds, camera shake; re-exported by BumpFx for PowerUpFx and RoundIntro), `HitFx` (bumps, ball hits, ripples), `BombFx` (the carried bomb, the blast, passes), `KnockoutFx` (the KO blast), `ChargeFx` (the ball dash). Split out of one 1,044-line file, 2026-11-14 |
| `Server/Systems/BumpServer.lua` | Tags bodies (`BumpBody`), copies moves onto characters, checks claimed bumps and throws the target (a player's own client applies its knock), spawns the dummies |
| `Server/Systems/Yard.lua` | The practice yard (was the test yard): height ledges, long-jump lane, wall-jump chimney, tower, dummy ring, built round `World.YardOrigin` (0, 0, 1600) |

**Animation** (2026-11-13, asked for "so we can get the feel right"): authored by script in headless
Blender, nothing uploaded. `animation/BUMP_Animations.blend` came from The Scramble with its whole
library; BUMP's own clips are in `animation/scripts/clips_bump.py` and it reuses Idle, Jump, Fall,
Roll, Flip (rollout), Land, LandSoft and Smash Arena's WallBonk, Dazed and DazeUp; Run is Playful's.
The Backflip and TripleFlip clips carry a `Land` marker; for your own body the Animator stretches
them so it meets the real landing (`Platformer.AirTime`, predicted at launch). Other players' flips
play at authored speed.

**Jump, then running on air** (2026-11-13). The user: "Instead of the triple jump, I want a jump
and then a floaty jump if I try to jump again whilst in the air. Something that feels close to
Super Blox 64"; then, on a first float with a spin and a glide: "No I want it to be like a running
on air kind of float, the player runs on air as if they're trying to float up". As built:
- The ground chain is gone: every ground jump is a single (`startJump`).
- Pressing jump in the air (from Jump, Fall, Backflip, LongJump, WallJump, Rollout, PoundJump)
  starts `AirJump`, once per flight (`airJumped`, reset on landing or grabbing a wall): a kick of
  `AirJump.Kick` 22 up, then while jump is held the vertical speed is pulled toward `RiseSpeed` 7
  (`Pull` 7 a second, gravity cancelled), and after `Tire` 0.65 of `Duration` 1.1 s toward
  `TiredSpeed` -10; let go (after `MinTime` 0.18) or run out and it's an ordinary Fall. `Steer` 1.2
  air steering. Touch has no release event, so held is `touchHeldUntil` (JumpRequest repeats).
- It plays `AirRun` on loop (`air_run` in `clips_bump.py`, preview `design/animation/air_run.png`):
  an eight-frame cartoon run in mid-air, leaning back, head up, knees driven high, arms pumping.
  A puff, ring and sparkles leave your feet as it starts; the chip says "Float Jump" while it's
  available.
- Measured in Play: jump, then hold at the top: up from 6 to 11.4 studs over 1.1 s, then a fall
  to the ground 0.2 s later. Facing (the user, from a recording: "my character should face the
  direction I'm running a bit easier because this just looks wrong"): while running on air the
  body turns toward where you push, or travel if you let go, at `AirJump.FaceRate` 14 (it used to
  turn only at `Air.TurnRate`, so steering left it running sideways or backwards); measured
  within 5 degrees of the travel, settling to 0 in about 0.25 s, steering hard sideways.
  The `JumpDouble*` and `TripleFlip` clips and `Jump.*` chain numbers are
  unused now (kept). **Not judged yet:** how it feels to the user.

**The jump chain** (rebuilt from scratch 2026-11-13; the user on the first set: "the jump and
triple jump animations looks terrible ... restart them from scratch", for awkward poses, jerky
transitions and the flip itself). In `clips_bump.py`, previewed as sheets in `design/animation/`
and approved before going in:
- Each jump is one continuous clip, take-off to ready-to-land, with a `Land` marker; the Animator
  stretches `JumpSingleR/L`, `JumpDoubleR/L`, `TripleFlip` and `Backflip` so the marker meets the
  real landing (`TIMED_FLIPS`, from `Platformer.AirTime`, your own body; others play as authored).
  Releasing jump early re-times it (`onJumpReleased` recomputes `airTime` from the height and the
  cut speed). Nothing switches clips mid-air.
- Single: a push-off, one arm reaching up and out, the other back, the opposite knee lifting;
  easing open at the top; arms out for balance on the way down (`FALL_OPEN`); knees forward to
  land (`LAND_READY`). Double: the same, bigger, both arms sweeping up. A chain alternates sides
  (`entry.Side`).
- Triple: a stretch with both arms up, one front somersault in a tuck, then straight into the
  balanced fall; no star. The turn is about the middle of the tucked body (`flip_pivot`, half a
  stud above the hips; measured in Blender the centre drifts 0.25 studs, where turning about the
  hips swung it round a 1.5 stud circle). Landing into `LandBig`.
- History, the same day: a fist-pump and split-kick set with a wide star after the flip (the
  star "sticks ... a bit too long"), a double somersault tried and dropped ("let's go back to the
  old somersault ... get rid of the star pose afterwards"). The Playful exports on disk hold only
  Run, Dash and the dodges, and AR has no flip.
- Measured in Play (yard, held jumps): single 0.38 s, double 0.47 s, triple 0.72 s in the air,
  no errors. **Not judged yet:** how they look to the user in motion.

**Polish pass** (2026-11-13), from the user's notes: "make the crouch and jump do a backflip that
arcs the player further back in a nicer motion", "Wall jumping needs to be improved massively.
There should be a gradual slide down after a slight pause whilst clinging onto a wall until the
player eventually falls", "Large falls should put the player into a roll followed by a bump if they
roll into an object, much like how it does in Sunshine Valley", "The triple jump feels awful", and
"Use VFX IKEA to get or create particles". What changed:
- Air steering keeps momentum: with nothing pushed only `Air.Drag` slows you (it used to brake
  you to a stop, which is why the backflip went nowhere back).
- Jump buffer and coyote time (`Jump.Buffer`, `Jump.Coyote`): an early press used to do nothing,
  which made the triple hard to hit.
- Wall: catch it in the air moving or pushing into it, `WallCling` holds still `Wall.Cling`, then
  `WallSlide` speeds up to `Wall.SlideMax`, and after `Wall.Hold` you let go (crouch or pushing
  away also drops you). Wall jumps chain up the chimney. The character's parts have zero friction
  (set in `attach`): a limb pressed into a wall used to pin the body dead.
- Big falls (`BigFall.Height` from the top of the arc) land in `LandRoll`; any roll that meets a
  wall square on (`Bonk.Square`) bonks as Sunshine Valley's does: hop back, WallBonk, Dazed with
  stars, DazeUp, no control for 1.37 s. A roll through a body bumps it.
- `BumpFx` plays particles on every body's move changes (Animator hands them over), made from the
  VFX IKEA sprites Sunshine Valley uses (Teleport.Wind cloud, circleboom2 ring, stars, sparkles);
  all five load in this place. Small camera shakes for pound landings, big-fall rolls, bonks and
  nearby bump hits (Humanoid.CameraOffset).
- The yard has steps to a 28 stud drop platform with a wall past the landing, for the roll and bonk.

Measured in Play with one player and scripted input: single/double/triple 6.7, 10.2, 15.1 studs
with buffered presses, the triple carrying 30 forward and its flip done 0.5 s into 0.67 s of air;
the backflip 14.8 up and 18.2 back, upright by 0.6 s of 0.73 s; a cling held still 0.3 s then a slide
speeding to 24; chimney wall jumps gaining about 10 studs each; a 28 stud drop rolling at 30 into
the wall, bonked back and up again 1.37 s later; a shove throwing a dummy about 38 studs. Not seen:
how any of it looks on screen (the particles were only counted), and nothing with two players.

Keys: Space jump, C crouch (Shift was dropped at the user's word, 2026-11-13), left click or E
attack. Gamepad A / L2,R2 / X,B. Touch: Roblox's jump button, Crouch and Bump in the engine's ring
(`primary2`, `primary1`; the ring's art is still another game's).

**Air turning** (2026-11-13: "we should be able to loosely control our rotation whilst jumping.
Proper nintendo style"): `airTurn` in Platformer. Pushing a direction in the air turns your body
and your direction of travel toward it at `Air.TurnRate` (3.4 rad/s), keeping your speed, so the
arc bends instead of sliding sideways; pulling straight back brakes instead. Shares: triple and
backflip `Air.FlipTurn` 0.6, long jump 0.45, dive 0.35; ordinary jumps also keep 0.6 of the old
sideways steering (`Air.SteerShare`). A backflip's backward arc swings the way you push. Measured
in Play: running along +X, jumping and pushing toward +Z turned the travel about 84 degrees in
0.35 s of air at speed 26 to 28; the body's turn lags the travel by up to about 25 degrees
(AlignOrientation Responsiveness 60).

**Snappier jumps and springier bodies** (2026-11-13). The user: "I still don't like the movement
or platformer mechanics. They're not polished enough"; asked, they pointed at jumps and air
control ("floaty or slow") and animation ("stiff or robotic"), against Mario Odyssey.
- Every arc rises under `Air.RiseGravity` 1.35 and falls under `Air.FallGravity` 2 (was 1 and
  1.45) times `Workspace.Gravity`; `riseFor` launches for the same heights, so jumps are as
  high but quicker. The triple's hang is `TripleFloat` 0.7 within `TripleFloatBand` 16 (was 0.45
  and 22). Air steering: `Air.Accel` 100, `TurnRate` 4.6, `Drag` 5 (were 60, 3.4, 3). Moves that
  launch with a raw upward speed (the dive) now land sooner.
- Measured in Play: a held single peaks at 6.9 studs 0.25 s in and lands at 0.48 s; a tapped one
  (the jump cut) is a 3.8 stud hop of 0.3 s.
- Animator: Jump and Double open into the Fall pose past the peak (they used to hold one pose
  all the way down). `flair` puts springy secondary motion on every body after its clip: lean
  forward speeding up and back braking, bank into turns (ground and air), a dip and rebound on
  landing, scaled by the fall; mostly into the Waist when the clip drives it, else the hips;
  off for flips, rolls, rides, walls, pounds, knocks. Measured: about -0.2 rad lean setting
  off, the torso banking 8 to 25 degrees into a fast turn, a small landing dipping the hips
  0.25 studs and back in 0.15 s. Trap: an AnimationConstraint's `Transform` reads back stale; check
  the part's world CFrame instead.
- The run cycle plays as authored at 21 studs a second (`RUN_STRIDE_SPEED`, was 14.4) and at
  most 1.8 times (was 2.2): at top speed it was twice as fast, and the user found the sprint "too
  fast for the speed the player's running at".
- **Not judged yet:** whether it now feels like Odyssey to the user; the numbers are all first
  guesses on the live `BumpTuning` attributes.

**The shove, polished** (2026-11-13). The user: "the shove needs a lot of polish"; asked, it moved
the character too far forward, the animation was weak, it was hard to land and the victim's
reaction was dull (they kept it one tap, no charge). As built:
- A 0.06 s wind-up, then a burst of `Bump.Lunge` 22 for 0.12 s that stops dead (`Brake` 220):
  3.5 studs measured, was about 8. The hit cone is wider and longer (`Reach` 6.5, `Cone` 0.1, were
  4.8 and 0.35; dives and rolls keep 4.8 as `BodyReach`), and the hit still counts 0.05 s after the
  burst. As it starts it snaps to face the nearest body within `Assist` 10 studs roughly in front
  of you or the way you push (`AssistDot` 0.25).
- New clips (`clips_bump.py`, previewed and approved): `Shove`, coiled back with hands at the
  chest, then the whole body thrown in, front knee bent, back leg driving, arms locked out;
  `Stagger`, the victim's chest caved in and head whipped back, arms windmilling as they stumble
  backwards, then catching their balance.
- The one shoved staggers instead of being knocked about: move `Shoved` (Animator plays
  Stagger), no control for `ShoveTime` 0.62 s, sliding back from `Push` 55 slowing at `ShoveSkid`
  70, with `Lift` 16 (was 28). A player is told `You "Knock"` with `Kind = "Bump"`; a bot or dummy
  is slid by `BumpServer.Shove` (a LinearVelocity). In BUMP's arena a shove no longer ragdolls
  someone on foot (dives and pounds still do); in Bomber a non-holder's shove staggers.
- Effects (BumpFx): a whoosh and dust as you shove; on a hit (`Fx "Bump"` now carries `Kind`) a
  bigger burst, a comic yellow "BUMP!" popping up tilted and fading, and a thump (Pro Sound
  Effects pop pitched down); the victim gets stars round the head and dust skidding off their feet.
- Measured in Play: from 7.5 studs away, a step toward the yard dummy and a shove landed; the dummy
  staggered 21 studs back and was standing again 0.62 s later. **Not seen:** a player being
  shoved (needs two players), and the BUMP! pop and stagger in motion.

**Input chips** (2026-11-13, "let's add the context input hints"): the three buttons are bound
through the engine's `InputHandler` (not ContextActionService), each with the engine's input chip
in the tray at the bottom left, group "Moves". A second `RegisterInputHint` with the same Id
gives a handle whose label follows what the button would do right now (`jumpHint`, `crouchHint`,
`attackHint` in Platformer, refreshed every Heartbeat, written only on change): Double Jump,
Triple Jump, Backflip, Long Jump, High Jump, Hop Out, Wall Jump; Crouch, Ground Pound, Let Go;
Bump, Roll, Dive. One that would do nothing is dimmed (Enabled false). **No chip for a plain
jump** (the user: "we don't need a hint for Jump"): the jump chip only shows for the special
ones. Trap: the binding's own hint and the handle AND their `Visible`, so never pass `Visible` in
`BindInput`'s inline hint or the handle can never show it again. Seen in Play: standing shows
Crouch | Bump; holding C adds Backflip (Long Jump when moving) and Bump turns to Roll; in the air
Ground Pound | Dive; a landing shows Double Jump for the chain window; on a wall Wall Jump | Let Go.
Not seen: a gamepad or a phone.

Fusion is 0.3. `processed-src/` and `processed-resources/` are generated: never read or write them,
edit `src/`.

## Layout

| Folder | What it holds |
| --- | --- |
| `BUMP/` | The game project: `src/Client`, `src/Server`, `src/Shared`, tools, Rojo/darklua config |
| `BUMPResources/` | The ResourceManager stub the engine requires (empty getters) |
| `../../ArcEngine` (from here) | The shared engine. Do not change it without saying so |

This folder is one git repo holding both projects, checked out as `Games/BUMP`. Scaffolding
(tools, project files, engine glue) was copied from The Scramble's blank project (itself from
Silly Billies's, Steal The Sky's and Tech Demos before that) and renamed. Paths assume each
project sits two levels under `Games/` (`../../../ArcEngine` from inside `BUMP/`).

## UI kit (2026-11-13: "let's get a UI kit together in UI labs")

Ported from The Scramble's kit (itself in the engine's input chip language: dark top-lit plates,
round ends, Gotham, colours read from the engine's chip tokens), pruned of its combat pieces
(zone clock, kill feed, hotbar slots) and grown with BUMP's own.

| File | What it holds |
| --- | --- |
| `UIFusion/Kit/Tokens.lua` | Colours (plus Gold, Silver, Bronze, Seat1 to Seat4), type (plus Mega), plates, shapes, timing, and the per-device layout of BUMP's HUD (`Layout.Desktop` / `.Phone`) |
| `UIFusion/Kit/Motion.lua`, `Source.lua` | Springs and reduced motion; the contract the HUD reads a round through, with every key and event listed |
| `UIFusion/Kit/FakeRound.lua` | A source that plays scenarios (Lobby, Intro, Playing, Knocked out, Results, Standings) for the board |
| `UIFusion/Components/Kit/Ui*.lua` | Shared: `UiText`, `UiPlate`, `UiLine`, `UiMeter`, `UiPips`, `UiPortrait` (seat-coloured ring, Out), `UiTag`, `UiCounter`, `UiKeyHint`, `UiBanner`, `UiButton`, `UiReveal`, `UiScrim`. BUMP's: `UiCoin`, `UiGold`, `UiPlace`, `UiSeat`, `UiCard` |
| `UIFusion/Components/Hud/*.lua` | `BumpHud` (root, by phase and device), `HudStatus`, `HudNote` (a game's line under the status bar), `HudGold`, `HudPlayers`, `HudCharge`, `HudLobby`, `HudIntro`, `HudResults`, `HudStandings`, `HudKnockout` |
| `UIFusion/Stories/*.story.lua`, `Storybooks/BUMP.storybook.lua` | The UI Labs board: Tokens, Kit, HUD (Scenario, Play, Device, Backdrop controls) |

- **Rules** (as The Scramble's): a screen never holds a Color3, font or size, a missing look is a
  new token; sizes are layout units, the root scales the layout to `Layout.Base` units tall.
- **Not mounted in the game yet**: `FusionApp` still has an empty root; the HUD goes in with the
  round system, fed by a real source.
- **Checking a story from Studio tools:** clone `StarterPlayerScripts.BACKEND` into a ScreenGui in
  CoreGui (the built modules reach the engine by relative path from `BACKEND`), require the story
  from the clone, call `story.story({ target, controls = { Name = scope:Value(...) }, scope })`.
  `screen_capture` only draws the 3D scene, so put the target on a SurfaceGui on a part (canvas
  1280x720, stood on its side because the Studio viewport is portrait; rotate the image back
  with `sips -r -90`). **Traps:** a CanvasGroup (every `UiReveal`, so every card) on a SurfaceGui
  doesn't redraw children added after it first drew, so cards look empty in captures while their
  rows are really there (lift the children out of the CanvasGroup to see them); small text is lost
  at a distance (zoom in); the phone stage drew nothing on the panel though it builds. Clean up
  the panel and the CoreGui copy after.
- **Seen (2026-11-13), desktop:** Playing (status bar, gold, seats with one struck through, dash
  meter), Intro (title, blurb, key caps, "Starting in 3"), Results (medals, seat rings, +gold) and
  Standings. **Not seen:** the phone layout, the Lobby and Knocked-out screens as drawn, motion,
  and anything in UI Labs itself: the user's view there is the real check.

## Rounds and minigames (2026-11-13)

The user's brief for three minigames, last player standing in each: **BUMP** (a hex platform with
one ball fewer than players; ride a ball, roll others off; momentum, a charged dash that slows you
while charging, pull back to skrrt; a hit makes a rider unstable and a second knocks them off;
hitting someone on foot ragdolls them the way you rolled; the platform shrinks), **BOMBER
BLOXIANS** (hex arena in the sky, pass an enormous ticking bomb by tagging, the holder explodes at
zero, each explosion shrinks the arena, brief immunity after receiving it) and **TILT!** (one huge
floating platform tipping by where everyone stands). Their answers: bots that really play and fill
empty seats to 4 in live servers; a lobby, then a playlist with intro cards and results, then final
standings; gold by placing, saved; build the framework plus BUMP first, then Bomber, then TILT!.
BUMP, Bomber Bloxians and MELTDOWN (see "MELTDOWN") exist: the playlist (`RoundInfo.Playlist`) goes round them for six games (`Rounds.Games`, was five), BUMP first. TILT! was turned down for MELTDOWN as the third game (2026-11-14).

| File | What it does |
| --- | --- |
| `Shared/Rounds/RoundInfo.lua` | Where the round's state lives (attributes on `ReplicatedStorage.BumpRound`), each minigame's intro card text, the playlist |
| `Server/Systems/RoundServer.lua` | (Each game: Changeover with the arena arriving, `Setup` then wait, then the 7 s cinematic Intro (see "Round intro") with `Place`; after Results, back to the plaza and the arena leaving.) Lobby (the plaza; needs a player; `Rounds.Lobby`, Studio `StudioLobby`), seats (players up to 4, bots fill), each game's Intro (frozen, `Frozen` attribute) / Play / Results, then Standings, then everyone back to the plaza (`World.LobbySpot`). Placing: knocked out takes the place of how many were left; survivors at time-up share 1st. Gold `Rounds.Gold1..4` through the engine's `MoneyHandlerServer.AwardCurrencyPromise` (quiet) and a `GoldEarned` event. Prints `[Round] <name> out (<why>) at <pos>` |
| `Server/Rounds/Bots.lua` | Bots: R15 from a friend's avatar (`Server/Rounds/Friends.lua`) or a plain body painted per seat (`Bots.Paint`: a description's colours don't reach the body), named with "[AI]", tagged `BumpBody` and `BumpBot` |
| `Server/Rounds/BumpGame.lua` | The ball game: the hex arena in the lobby's pit (`World.ArenaOrigin`), 7 rings (169 tiles; the user wanted it "much larger" than the first 4), neon edges cyan to pink, balls, mounting, hits, knock-offs, shrink, falls. The bots' brains are `Server/Rounds/BumpBots.lua` (on foot, riding), handed what they need of the running game through `BumpBots.Bind`. Arena attributes `Hits`, `KnockedOff`, `Runover` count for tests |
| `Server/Rounds/HexArena.lua` | The hex platform both games stand on: cells (`Solid` / `Warning` / `Gone`), `FloorAt`, `IsEdge`, `DropCell`, `Crater`, `SafeSpot`, a glass stand (`StandSpot`) |
| `Server/Rounds/BomberGame.lua` | Bomber Bloxians: the arena in the lobby's pit, 5 rings (91 cells), neon edges yellow to red, the bomb, passing, blasts, the bots. Arena attributes `Passes`, `Blasts`. Prints `[Bomber] ...` |
| `Shared/Minigames/Hex.lua`, `BallPhysics.lua` | Hex grid maths and tiles; how a ball rolls (shared by players' clients and the server's bots) |
| `Shared/Ragdoll.lua` | Knocked flat: The Scramble's limp bodies (sockets with R15 limits, weak muscles towards a relaxed pose, no-collides, hip box off) driven by the `BumpRagdoll` attribute, followed on every machine by `Ragdoll.Watch` |
| `Client/Systems/BallRider.lua` | Riding your own ball: you drive it (the server hands you its physics); the platformer hands your body over (`Platformer.SetExternal`) |
| `Client/Systems/RoundClient.lua` | The HUD's source: the round attributes, your gold (engine `MoneyHandler`), `KnockedOut` / `GoldEarned`; preloaded by ClientMaster, reached by UI through `RuntimeDependencies` |
| `UIFusion/Root/FusionApp.lua` | Mounts `BumpHud` on `RoundClient` |
| `Client/Systems/BumpMusic.lua`, `Shared/Audio/BumpSounds.lua` | Music and the round whistle (the user, 2026-11-13: "music that speeds up as the game gets more intense as well as a whistle to mark when the rounds finish"): APM "Silly Chase" for games, APM "Comedy Clip (a)" in the lobby and results, crossfaded by phase; the game track's PlaybackSpeed climbs to `MaxSpeed` 1.32 with the round's `Intensity` (set by the game: floor gone, players out, time); a Pro Sound Effects referee whistle when a game ends. All from Roblox's licensed libraries; two other APM tracks failed to load here |

**BUMP's rules as built:** balls are `Ball.Size` 8; mount by landing within `Ball.MountReach` of a
free ball's top. Riding: `BallPhysics` (slow build to `MaxSpeed` 34, little drag, `Skrrt` pulling
back above `SkrrtMin`, hold attack to charge 0.8 s then a dash of 34 to 76). Two balls meeting with
a closing speed over `BumpHits.Min` is a hit, judged on the server on the **previous frame's
velocities** (a touch is reported after the bounce, when they're already separating). A hit rider
wobbles for `BumpHits.Wobble` (`BumpWobbleUntil` on the character; steering weakens); hit again
while wobbling and they're knocked off and ragdolled. A ball over `FootMin` running into someone on
foot throws and ragdolls them. **The user, 2026-11-13: "Diving into a player on a ball
should probably count the same as when a ball knocks another ball pretty hard"**, then "I'm diving
into players on balls and I'm not knocking them off": the platformer's body hits go first to
`BumpServer.SetBodyHitHandler` (BumpGame's `onBodyHit`), which judges a rider by the diver's distance
to their **ball** (a rider stands about 7 studs up, out of the old body-to-body reach) and knocks
them straight off on a dive; a shove or pound shock wobbles them. The client's `hitAround` also
counts a rider's ball (its surface within reach) and accepts a hit when your own movement carries
you into it. Someone on foot in a game (bots too; they used to get nothing) is thrown and ragdolled.
**Ground-pound ripple** (the user, 2026-11-13: "ground pounding should be able to create a ripple of
all the hexagons around you to make close ball players wobble"): a pound landing on the platform
sends "Pound" to the server, which broadcasts a `Ripple` Fx (every client bobs the tiles outward
from it, `BumpFx.onRipple`, local only) and hits every rider whose ball the wave reaches within
`Pound.RippleRadius` 28 as a ball hit (wobble, or off if already wobbling), timed by
`RippleSpeed`. Measured (2026-11-13): cells drop about one a second at first, quickening; the music fades by
phase, reached 1.18x speed when half the players were out, and the whistle blew at each game's end;
a capture from above showed a ragged notched edge with cells flashing and falling. Not reached in
the games watched: the "holes anywhere" stage (games ended in 25 to 60 s, before 55% was gone).
Seen in the log: dive on a rider, knocked off (dive); ripple reached two bots, one
knocked off (second hit). **The floor crumbles a cell at a time** (the user, 2026-11-13: "instead of deleting the outer edge
of the arena as a whole ... remove individual cells one by one"; their choices: edge first, holes
later; speeding up): after `BumpArena.Grace`, `pickCell` takes a random cell off the current edge
(a solid cell with a missing or falling neighbour) until `HolesAfter` of the floor is gone, then
any cell, weighted to where people are; `dropCell` shakes and flashes it for `Warn` (faster at the
end) then drops it. The gap between cells eases from `DropStart` to `DropEnd` over `DropRamp`;
it stops at `KeepCells`. Cells live in `state.cells` keyed by `Hex.Key(q, r)`
(`Hex.FromPosition` / `Neighbours` / `Key` in `Shared/Minigames/Hex.lua`); `floorAt(position)`
says whether there's floor that will stay (bots look ahead with it, skrrt at holes, head for
`safeSpot` near holes, and only dash where the dash lands on floor). Below `FallDepth` you're out
and go back to the plaza to watch; bots are removed. Free balls are popped to keep one fewer than players.

**Bomber Bloxians as built** (2026-11-13; the user's choices: hidden fuse with the ticking
speeding up, crater plus blast, the holder is faster, touch anyone to pass): 1.5 s in, a random
player gets the bomb, welded over their head (`Bomb`, tagged `BumpBomb`, attribute `Holder`). The
fuse is a random `Bomber.FuseMin`..`FuseMax` (15 to 25 s), never shown; the server sets the bomb's
`TickEvery` from `TickSlow` 1.0 to `TickFast` 0.1 on a curve, and every client ticks
(`clickfast.wav`), flashes it red and sparks its fuse (`BumpFx.watchBomb`). The holder has
`BumpCarrying` (the Animator puts the library's Carry clip on the arms, exported via
`clips_bump.REUSED`) and `BumpSpeedScale` 1.25 (the platformer's run speed; bots' WalkSpeed).
Passing: bodies within `PassReach` 4.5 (and 5 up/down), checked every frame, or the holder's
dive/shove through `BumpServer`'s body-hit handler; the receiver is nudged (`PassPush`) and can't
pass for `PassImmunity` 1.5 s. Anyone else's dive or shove just pushes. At zero: `Fx "Boom"`
(fireball, rings, light, `impact_explosion_03.mp3`, shake by distance), everyone within
`BlastRadius` 20 is thrown and ragdolled, the holder is out and pops (below), the cells
within `CraterRadius` fall and `EdgeBite` 8 more edge cells crumble; `NextBomb` 3 s later a new
bomb. A holder who falls takes the bomb with them. No clock (`NoClock` on the intro card); the
round's `Note` attribute ("Zippy has the bomb!", "Next bomb coming...") shows in `HudNote`; a
hidden 300 s safety limit. Intensity (music) follows the fuse. Bots: the holder chases the
nearest, leading them, on paths that stay on floor; the others flee to the reachable cell
furthest from the holder (not past them, not the edge), with per-bot reaction times.
Measured in Play (one idle player, three bots): seven passes in 48 s, ticks quickening 1.0 to
0.11, two blasts (crater 4 cells at radius 13, so it's now 16; 8 edge cells each), a blasted bot
thrown off the edge, game over at 50 s, then BUMP. **The holder pops** (the user: "When exploded by the bomb, the character should just pop and
disappear almost instantly. Perhaps a red highlight that fades into a sackboy level pop"; our own
cartoon pop, no borrowed art): `RoundInfo.PopAttr` ("BumpPopped") on the body; every client
(`Client/Systems/PopFx.lua`) floods it red with a Highlight for 0.22 s, then hides it
(LocalTransparencyModifier, name off) in a white and red puff with a ring, sparkles, 16 tufts of
stuffing flying out and a Pro Sound Effects balloon pop, and keeps it hidden until the server
clears the attribute: 0.6 s later the body goes to the stand (a bot is removed) and shows again
0.3 s after that. It replaced being thrown 110 studs up as a ragdoll. Measured in Play: red half in
at 0.1 s, body hidden by 0.35 s, 16 tufts; caught in a capture mid-puff. Not seen: your own body
popping.
**The carried bomb** (the user: "the bomb should wobble with the character ... It doesn't look fun
to carry at all"): the server's bomb is still welded to the holder's root at `BOMB_HEIGHT`, but each
client hides it (`LocalTransparencyModifier`) and draws its own (`BombView`, `BumpFx.watchBomb`),
sprung (220 stiffness, 13 damping: it overshoots) to a point 1.1 radii above the midpoint of the
holder's hands, so it rides the carry pose's arms: it bounces with the run, lags and tilts when
they turn or stop, squashes and stretches with vertical speed, pulses on each tick, and swings to
the new holder on a pass (it snaps if more than 40 studs off). Measured: it trails its rest point by
0.5 to 2 studs while the holder runs, stretching up to 17%; seen resting on the raised hands
(`design/animation/bomb_carry.jpg`). Seen in a second run: `HudNote`
("Arcwise has the bomb!", "Next bomb coming...") under the bar (a first try inside the status bar
was unreadably small), the bomb overhead flashing red with the arms up (it floated above the
hands, so `BOMB_HEIGHT` went 5.4 to 4.7, not re-seen), and a crater's ragged hole with red cells
falling. **Not seen:** the fireball itself (captures lag about a second), a human chasing or
fleeing, a phone.

**Riding, remade** (2026-11-13; the user: "The animation when rolling on a ball looks terrible. Can
we remake it", and "the dash on the ball should charge up like the player's running in spot on the
ball, VFX on the ground and around the ball to indicate the player's building up power, and then a
launch"). New clips in `clips_bump.py` (sheet `design/animation/ball_ride_clips.png`), all keeping the
body upright since BallRider already tilts it into the roll: `BallBalance` quick light steps with
arms out low; `BallCharge` running on the spot, knees high, arms pumping (the Animator plays it up to
three times as fast as the charge fills, `Ball.ChargeTime`); `BallDash` (new) thrown forward with the
arms swept back, held for 0.45 s after a dash as move `RideDash` (BallRider `ride.dashUntil`, bots
`brain.dashUntil`, in BumpServer's MOVES); `BallSkrrt` sat back with both feet braced; `BallWobble`
tipping side to side, arms windmilling. Effects (`chargeFx` in BumpFx, on every body by move): while
charging, a neon ring on the floor under the ball growing and pulsing faster, rings rippling out,
sparkles flying in from a sphere round the ball, dust spun out behind, all white to gold at full,
stars at full; on the launch, a gold ring burst, a dust blast thrown back and speed streaks. Seen in
Play: my charge (ring, ripples, sparkles, meter) and a bot's launch in one shot
(`design/animation/ball_charge.jpg`), then my own launch (`ball_launch.jpg`).

**Riding, third pass** (same day). The user: "now when running on the ball it should look like the
player's running matching momentum with the ball and trying to maintain their balance", then "The
current animation looks AWFUL. It should look intense as if the player is trying for dear god to
stay on the ball. Extremely cartoonish-exaggerated nintendo feeling". What changed:
- **The bug under it all:** a rider's body is pinned by a rigid AlignPosition and reports no
  velocity, so the Animator always thought riders stood still (steps never quickened, nothing
  reacted). It now measures speed from how far the body moved (`measuredVelocity`, used for the
  ride moves in `choose` and `flair`).
- `BallBalance` is a scramble (`design/animation/ball_scramble.png`): knees pumping high, both arms
  windmilling in wide circles half a turn apart, chest twisting against the legs, head bobbing.
  Cadence `BALL_SHUFFLE` 1.6 strides a second standing still plus one per `BALL_STRIDE_STUDS` 6
  studs rolled.
- `rideBalance` (Animator): loose springs (55 stiffness, 5 damping) for a sideways sway, a forward
  tip and an arm swing; a restless sway growing with speed, turns throwing the body outward, and a
  random lurch every 0.9 to 2.5 s; the hips tip with the sway, the chest and head counter it, the
  arms see-saw hard (the falling side's arm flung up). Each body has its own `Seed`.
- Riders bank into turns (BallRider `ride.bank`, bots `brain.bank` with the forward lean they lacked).
- Measured on a bot at an average 46 studs a second: 4 strides a second, the body swinging through
  about 20 degrees. **Not seen moving**: stills can't show it; the user's eye is the check.

**Knock-backs that carry** (the user: "Getting hit by a ball when on foot should knock the victim back
quite a bit. At the moment it looks like they only ragdoll"). The throw was there, but going limp in
the same moment loosens the joints into separate assemblies whose limbs start at rest and drag the
thrown torso to a stop: a dummy thrown at 76 studs a second was at 18 a tenth of a second later and
slid 6.8 studs. `Ragdoll.Fling(character, velocity, spin?)` gives every part the speed, now and for
the next three Heartbeats; `BumpServer.Throw` (bots, dummies) and `knockDummy` use it, and the
platformer flings its own body on a Knock and again the frame it goes limp (`lastKnock`). Measured
on a dummy: 45 studs in half a second, 90 by the time it stopped (at 90 and 42). `BumpHits.FootPush`
is now 75 and `FootLift` 40 so a run-over throws hard without always clearing the arena. Every
knock benefits (dive knock-offs, Bomber blasts, pound shocks).

**Faster balls, hits that land** (2026-11-13). The user: the ball game "seems a little too slow ...
when I charge my balls speed and ram into somebody, there's not really that feel good feeling
behind the impact". As built (every number a first guess, old in brackets in `MoveConfig`):
- `Ball`: `MaxSpeed` 44 (34), `Accel` 34 (22), `OverDrag` 14 (18), `SkrrtDecel` 110 (85),
  `ChargeTime` 0.55 (0.8), `ChargeDrag` 34 (26), dash `DashBase` 46 + `DashBonus` 54 = 100 at full
  (76). `BumpHits.Push` 30 (22), `PushShare` 0.8 (0.6).
- Every ball-on-ball hit goes through `ballImpact` (BumpGame): `Fx "BallHit"` { Position, Normal,
  Strength (0 to 1 from the closing speed up to `Hits.Hard` 75), Hitter, Hit, Off, Follow, Pause }.
  The hitter's ball carries on through at `Hits.Follow` 0.55 of its speed instead of bouncing
  back (a bot's here, a player's by their own client).
- Everyone (BumpFx `onBallHit`): a white flash swelling, a gold shockwave ring racing out, sparks
  thrown out, stars, a comic word sized by strength (BUMP!, WHAM!, KAPOW! for a knock-off), a thump
  (the KO boom pitched up) and a boing; a camera kick for the riders in it, less near.
- The riders in it (BallRider): their balls freeze `Pause` 0.05 + 0.07 x strength s (hit-stop),
  then carry on (the hitter with `Follow`); their view punches out up to 10 degrees. Riding, the
  view widens with speed (up to 16 degrees at full dash) and a wind trail streams off you above 40.
- Measured in Play: bot hits arrive with strengths 0.27 to 0.49, a knock-off flagged, hitters
  carried on at 16 to 26; bot balls up to 78 in dashes. **Not seen:** the freeze, view punch and
  carry-through on a player's own ball (bots kept knocking the idle test player off before a ram),
  and how it feels; bots still spend a lot of time slow (median 17 studs/s), staging or waiting.

**Diving steals the ball** (the user: "When knocking a player off a ball with my jump dive, I should
automatically be placed ontop of the ball - essentially stealing it from them"): in `onBodyHit`, a
Dive whose `hitRider` knocks the rider off then `mount`s the diver on that ball, which keeps rolling
with the hit; prints `[Bump] X stole Y's ball`, counts arena attribute `Steals`. Seen in Play: moves
Jump, Dive, Ride, and the ball's Rider went from bot1 to me.

**Eight seats and the bots' minds** (2026-11-13). The user: "Let's get 4 more AIs in and improve
the AI massively"; their choices: 8 seats in every game with players first and bots filling, and
what was wrong: bots "die stupidly", are "too passive / predictable" and have "no personality".
- `Rounds.Seats` 8; gold by place `Gold1..8` 12/9/7/5/4/3/2/1; XP by place 20/15/11/8/5/3/1/0;
  seat colours 5 to 8 (orange, purple, pink, teal) in `Tokens` and `Bots`; 14 bot names; the HUD's
  list, results and standings sized by `Tokens.SeatCount` with slimmer rows (Players row 34,
  phone 24); Bomber's arena 6 rings (127 cells, was 5).
- `Server/Rounds/BotMind.lua`: each bot is dealt a mind per session (`[Bots] X: Style, skill`
  in the log): Bully (goes for people, players most, meets charges head-on), Opportunist (waits,
  then pounces on whoever is wobbling or near an edge), Coward (keeps away, dodges, hides behind
  others from the bomb), Wildcard (random, feints); skill 0.55 to 0.95 sets how far ahead it
  looks, its aim error and its reaction time (0.15 to 0.4 s between decisions). Floor sense:
  `HoleDistance`, `PathClear`.
- BUMP riding: survival first (floor all the way to where this roll would stop, by speed, the
  skrrt's deceleration and reaction, further for the skilled; skrrt and head for safe floor if
  not); wobbling, get away from everyone toward the middle; an incoming ball, sidestep to the
  side with floor (a bully meets it head on); otherwise hunt a target chosen by style (close,
  near an edge, wobbling, players, people on foot; sticky), circling round to the side away from
  their nearest edge before charging, so hits send them off; dash or Turbo only with floor past
  the target; a margin from the edge when not hunting; a calm start (no power-ups or dashes for
  the first 2.5 to 5.5 s of play). On foot: dodge balls rolling at them, walk to free balls by
  paths over floor, else leap at a rider and steal the ball (`botDive`, through `onBodyHit`
  "Dive", as a player's dive).
- Bomber: the holder picks by style (close, cornered, players), leads over floor and leaps to pass
  when close (keener as the ticking quickens); the rest keep a distance that grows with how fast it
  ticks and their caution, juke sideways with a hop when it closes in, step off crumbling floor at
  once, keep off edges, and the cowardly pick spots with someone else between them and the holder.
- The log now says why someone fell in BUMP: "knocked off" (hit in the last 4 s) or "fell alone".
- **Second pass** (2026-11-14). The user: "There are moments where they're all just standing still
  for no reason", "when passing the bomb to an AI, they seem to run back after me as the closest
  target ... almost randomise their targets", and "update their targets based on changing factors
  like distance to other targets and aggro". Measured first: Bomber bots still 65% of the time
  (up to 9 s at a go) and 11 of 15 passes going straight back; BUMP riders still 9% (3 to 5 s
  parked).
  - **The main cause was a bug:** `Hex.Key` named a tile from a point just left of a column "-0,r"
    (Luau prints negative zero as "-0"), which matched no tile, so `FloorAt` said solid floor was
    gone: fleeing bots "stepped off" to the nearest safe spot, their own tile, and stood. Fixed (0
    is written "0"), with a spec case. It also gave BUMP's bots fake holes to recover from.
  - **Targets** (`BotMind.PickTarget`, both games): the game's score (distance, cornered, players,
    the style's leanings) plus a whim per target dealt again every 2 to 4.5 s (up to 1.5 x (0.6 +
    the style's Random), enough to outweigh 30 to 60 studs), a switch only when another beats the
    current target by 0.5 as people move, and giving up for 3 to 6 s on one chased 4 to 6 s
    without getting 3 studs closer.
  - **Bomber holders** don't go for whoever just passed it to them for 3.5 to 6 s
    (`bomb.passBackAt`) unless they're the only one left, and favour the easy to catch (standing
    about, coming their way) by skill. **Fleeing** bots always have a goal and pick the next on
    arriving: roam the floor when far enough (the brave near the holder, the careful away), kite
    to sideways floor 6+ studs away when close (held 0.7 to 1.2 s so they don't jitter), further
    when the holder is after them.
  - **BUMP**: riders with nobody worth hunting patrol a loop round the middle instead of parking;
    on-foot bots pick their next spot on arriving; a recovering rider whose nearest safe spot is
    under it heads inward.
  - Measured after: Bomber still 3% (no stretch over 1.5 s), 2 of 15 passes back within 6 s, the
    bomb round the field (players included); BUMP still 2%.
- **Bots as the players' friends** (2026-11-14). The user: "make the NPCs resemble players from
  the playing players' friends lists and add an "[AI]" tag next to their names".
  `Server/Rounds/Friends.lua` fetches each player's friends list on joining (`GetFriendsAsync`, up
  to 4 pages of 50, `[Friends] X: n friends`); `startSession` deals the empty seats to friends of
  the people playing (`Friends.Pick`: shuffled, nobody in the server, nobody twice), the rest to
  `Bots.Names`. Every bot's name ends in `RoundInfo.AITag` ("[AI]"), so the tag shows wherever a
  name does (overhead via Humanoid.DisplayName, the HUD list, results, standings, intro pops, the
  knockout card and feed, Bomber's note, the lobby boards, the log). A friend's bot has `FaceId`
  (their UserId): `Friends.Prefetch` fetches their avatar (`GetHumanoidDescriptionFromUserId`,
  cached) at the session's start, `Bots.Spawn(..., look)` builds the body from it and paints the
  body colours from it (a description's colours don't reach a built body here); seat colour
  stays on the ball, spotlight, name and ring. `FaceId` rides in the Players / Results /
  Standings entries for portraits (`UiSeat` shows `UserId or FaceId`) and as `ByUserId` on the
  knockout card; it isn't `UserId`, which marks real players. Any failure falls back to the plain
  seat-coloured bot. Measured in Play: 200 friends, seven bots dealt ("Baumz [AI]", "Phoenix [AI]"
  ...), bodies with 2 to 8 accessories, layered clothing and their own skin; the list with names
  and headshots (`design/lobby/L_friend_bots.jpg`). **Not seen:** the bodies on screen in a
  capture, long display names in the list, a friend joining mid-session.
- Measured in Play, one idle player and seven bots: BUMP games of 90, 50 and 90 s (the limit) and
  Bomber 82 and 83 s (were 8 to 27 s); over two BUMP games 12 knocked off and 2 fell alone; 4 balls
  stolen by bots' dives; no errors. **Not judged yet:** whether they feel fun and fair to the user
  (they may now be too good), how they treat a real player, and 8 real players.

**Traps found:** `GetDebugId` is plugin-only (the user saw it fail in Output); `Touched` velocities
are post-bounce; a PlatformStanding Humanoid gets no `MoveDirection` from Roblox's built-in
controls, so the rider uses `WalkSpeed` 0 instead; the engine's camera takes the camera back each
frame, so a test framing it binds a RenderStep after Last; `screen_capture` in Play shows the
player's view, HUD included. **Ragdolls killed players** until `Ragdoll.Prepare` set
`RequiresNeck = false` and `BreakJointsOnDeath = false` (The Scramble does this in its Fighters; the
port missed it): a loose neck killed the Humanoid, the engine respawned you, and the engine's
anti-cheat then threw `attempt to index nil with 'CharacterRemoving'` (AntiCheatHandlerServer:81)
and `Arcwise:WaitForChild("HumanoidRootPart")` waited forever. Measured after the fix: knocked flat,
Physics state on your client, joints loose, health 100, up again as the same character. The
anti-cheat's own nil check is still missing (engine code, left alone). **Studio tools trap:** the
assistant's `execute_luau` restores any camera type a script changes when it ends, so a test that
pins the camera must undo it from a `task.delay`, or the user is left on a Scriptable camera.

**Measured in Play (2026-11-13), one player and three bots:** a session ran lobby to standings with
gold saved (25 after five games, the same as the session total); intro, play, results and standings
cards show in the game; mounting in about 0.6 s; 0 to 34 in about 1.6 s; a full charge in 0.8 s
holding the ball still, a dash at 72; a skrrt from 36 to 13 in 0.3 s; ball hits counted; two dives
on a riding bot wobbled it then knocked it off into a ragdoll; a ragdolled dummy lies on its side
with bent limbs. **Not seen or still rough:** games are short (8 to 27 s, bots often roll each other
or themselves off before the ring drops); the second-hit knock-off between bots happened 0 times in
the games watched; two players together; a phone; how any of it feels to the user.

## MELTDOWN (2026-11-14)

The user: "Let's get a third gamemode in here. Probably something completely new, intense, and
incredibly fun". Of SPINOUT (sweeper beams), SPLAT ZONE (paint the floor), MELTDOWN and TILT!, they
picked MELTDOWN: a climb up a tower of floating platforms with lava rising, last one standing; all
four tower pieces (crumbling, moving, bounce pads, wall-jump chimneys) and all three hazards (lava
fireballs, surges, falling debris). Then, on the first tower: "the platforms of the tower should be
spread out a bit more. Make the player utilise their float jump and less likely to bang their heads
on platforms that are directly above each other".

| File | What it does |
| --- | --- |
| `Shared/Minigames/MeltLayout.lua` (+ spec) | The tower as data from a seed: the start ring and pit floor tiles, 14 tiers of 5 platforms (`Kind` Solid / Crumble / Mover / Summit) round a core, pads, chimneys, and a link graph of the jumps a bot can make (`CanJump`); rebuilt from the next seed until the summit is reachable. `MoverOffset` / `MoverVelocity` from server time |
| `Server/Rounds/Tower.lua` | Builds it in the pit (`HexArena` + `Centre` attributes, so ArenaShow plays it in bottom-up, tier pairs as rings); `PlatformUnder` (by height; `Tower.Base` the ring, `Tower.Pit` the pit floor), `Crumble` (shake, fall, back after `CrumbleBack` unless the lava's there), `SafeAbove`, movers moved each frame (carrying bots), the lava's `LavaY` / `LavaAt` / `LavaRate` |
| `Server/Rounds/MeltdownGame.lua` | The game: the rise and surges, fireballs, debris, the summit's last stand, lava outs (`melted`, blamed on a hit in the last 4 s), the pound shake, power-ups. Prints `[Melt] ...` |
| `Server/Rounds/MeltBots.lua` | The bots: assisted jumps flown exactly along the arc (a stock Humanoid steered by physics clipped edges and bounced off), skill-based misjudged leaps that fall short, a rest after each landing, routes by links-to-summit, pads, chimneys as hops wall to wall, climbing with the lava (waits when well ahead), shoves and dives (Bully) and pounds (Opportunist, Wildcard) after a calm start, dodging fireball and debris marks. In Studio each bot's `MeltBrain` attribute says what it's doing |
| `Client/Systems/MeltClient.lua`, `Client/Fx/MeltFx.lua` | Each client moves the lava and the movers itself (smooth), dresses the lava (ForceField crust, embers, bubbles, bubbling louder as you near it), warms the picture near it, and sends `Act "Melted"` the moment your root is under its top (the server's copy of a falling body lags). MeltFx: fireballs with landing rings, falling rocks with shadows, splashes, crumbles, the shake's jolt, the surge's rumble and shake, melted bodies smoking |
| `Shared/Movement/FloorUnder.lua` | The part under a body by a ray down: **Humanoid has no FloorPart** (reading it errors every frame) |

**As built** (every number in `MoveConfig.Melt`):
- **Layout:** tiers 7.5 apart (a single jump peaks at 7, so each takes a float jump); nothing overlaps a platform within 17 studs above or below it (two tiers: a float jump's reach); tiers alternate an inner and an outer ring a third of a step round, so a platform lines up again only three tiers up. Five a tier always (mixing counts broke the pattern and left empty tiers). The start ring (tiles poking in to radius 52; whole tiles only left notches up to 10 studs deep that bots walked into) and, 10 studs below, the **pit floor** under the tower: an early fall lands there and you climb back, until the lava floods it (about 15 to 20 s in). Without it a shove off the low tiers went straight into the lava and games ended in 30 s.
- **Lava:** from -32, after a 5 s grace rising 0.7 to 2.2 studs a second over 80 s; surges every 12 to 18 s (rumble, "SURGE!", +8 in 1.5 s); it stops 7 under the summit, and once it's 26 from the top the top tiers crumble for good, one every 1.4 s.
- **Hazards:** fireballs from 8 s (4.5 s apart down to 1.4) stagger whoever is within 6 of the ring; debris from 30 s (7 down to 2.5 s) knocks flat within 5 and cracks the platform.
- **Fighting:** shoves stagger, dives throw; a ground pound shakes your platform (everyone else on it staggers, a crumbling one goes). Shockwave staggers everyone on your own level in reach (it used to reach every tier and threw five bots in at once); Second Chance puts you on a solid platform 10+ above the lava.
- **Platformer:** a moving platform carries you (the CFrame delta of the floor's model each frame); landing or walking onto a pad (`RoundInfo.BounceAttr`) throws you as a PoundJump to its height, with a slide whistle.
- **Elsewhere:** the jumbotron rises 75 studs out of the tower's way while MELTDOWN is on; KnockoutCam shows the self shot for "melted" (not FallCam's iris); the card says MELTED!; ArenaShow takes `Centre` and sizes its finale by flat reach; HitFx's ripple only bobs tiles at the pound's level; `BumpServer.OnAct` takes several listeners per action (BUMP and MELTDOWN both hear "Pound").

**Found on the way, for every game:** RoundServer waited a full intro *after* `Place`, so a slow bot spawn pushed Play past the countdown's GO (the intro ran 20 to 40 s with avatar loads rate-limited); it now ends on the intro's own clock. Bots' friend avatars are taken only if already fetched (`Friends.Ready`), never waited for.

**Measured in Play (2026-11-14, one idle player, seven bots):** 40 of 40 seeds build, about 48 platforms, 4 pads, 1 chimney; games of 45 to 65 s with 2 to 4 surges, 9 to 18 fireballs, 3 to 7 debris; bots about a tier every 1 to 2 s; a lava touch to KnockedOut in 0.09 s; on a mover 0.00 studs of drift over 6 studs of travel; a pad throws you 27 studs up; no game errors. Captured: the tower from the plaza with the pit flooded. **Not seen:** the summit's last stand (bots knocked each other out before the lava got near the top), the new lava colour, a human climbing it, a phone; how it feels.

## Falls that land on time (2026-11-14)

The user: "Sometimes when I fall off the map, the feedback isn't as sudden as we'd expect it to be.
It's like the killbox isn't under every part of the arena or something". It was the server's copy
of a falling player's body, which lags or stops updating (measured: my client at y -26 while the
server had me at -9), and BUMP and Bomber judged falls by it alone, at -36. Now:
- `Client/Systems/FallCam` tells the server the moment your own body is below the game's fall line
  (`Act "FellOut"`, at most every 0.5 s); `BumpGame` and `BomberGame` take it as it stands (a false
  report could only knock its sender out) through the same path as their own check (Second Chance
  first, blamed on a hit in the last 4 s). The server's own check stays as the backstop.
- The fall line is 20 under the arena (`BumpArena.FallDepth`, `Bomber.FallDepth`, were 30).
- MELTDOWN does the same with its lava (`Act "Melted"`, MeltClient).

Measured in Play, walking off the edge: below the line 0.35 s after leaving it, out 0.06 s later,
in both games; a run-over in BUMP knocked me out with the server still showing me at y -15.

## Round intro (2026-11-13)

The user: "Let's give each round a nice AAA ADHD nintendo level intro with title card and camera pan
over along with some intro music into a 3 - 2 - 1 countdown"; their choices: sweep the arena, then
glide along the contestants with names, ending behind you; about 7 s. Then: "the intro should focus
more on the player ... it should take a little bit longer when showing the final player, which is
the player's character itself"; their choices: about 8.5 s, and for your moment a slow push-in and
orbit, a big name card on screen, a hero pose and a spotlight flare. Then (2026-11-14): "maybe the
camera should fly in smoothly past all the characters before settling on the player", replacing
the shot-by-shot lineup with one flight. Then (2026-11-14): "the intro cutscene should take twice
as long": the camera part doubled from 5.5 to 11 s, the 3, 2, 1 kept at 3 s. `Rounds.Intro` 14 (was 8.5, 7, 6),
`Rounds.IntroCountdown` 3; everything is timed off the Intro's `EndsAt` (RoundServer's `phase` now
sets `EndsAt` before `Phase`, so a client reacting to the phase reads the right time).

| t (s) | What happens |
| --- | --- |
| 0–2.6 | One unbroken camera flight begins (`along` in RoundIntro: a Catmull-Rom curve through timed points, so it never stops or turns a corner): a wide orbit high over the arena inside the pit, FOV 80, ending just short of you; cinema bars (`HudLetterbox`); the title slams in huge in the game's colour (`Tokens.GameColor`: BUMP cyan, Bomber orange) from twice its size, tilted and bouncing, a "GAME 1 OF 5" ribbon sliding in; blurb and controls along the bottom; the jingle (APM "Quizmaster (Jingle)", Showbiz, 10.6 s: the whole cutscene; was "Shooting Stars", 4.9 s) |
| 2.6–6.8 | The flight dives into the ring (FOV to 56) and carries on round it past each of the others in turn (3.5 to 6.1), 16 studs inside them and 4 up, its aim trailing what it's after by `AIM_LAG` 0.14 s; each name pops beside them in their seat colour as it arrives; it ends arriving at you, moving the way your shot starts |
| ~4.5 | The title card swells and fades (`Tokens.Timing.TitleUntil` 9.5 s left) |
| 6.8–10.0 | **Your moment**: the flight slows into an orbit from your left front across your face (-50° to 50° off where you face), pushing in 16 → 11 studs and sinking from chest to waist height, easing to rest, FOV 56 → 46, framing you a little right of centre. You strike `HeroPose` (move `Hero`, `Platformer.Pose`, locked, everyone sees it); your `BumpSpotTop` spotlight flares 7 → 18 and back (local); a seat-coloured ring, sparkles and stars burst at your feet with a whoosh; your name pop ("YOU"); and `HudHero` (cued by RoundClient's `IntroHero`) slams your name huge in your seat colour low on the left, a streak behind it and a YOU pill; the blurb and controls step away for it |
| 10.0–11.0 | The name card swells off and the camera layer fades into the gameplay camera behind you |
| 11–14 | 3, 2, 1 (`HudCountdown`): bare white numbers with the kit's dark outline, no plate (the user: "The 3 2 1 Go should be a lot more tasteful. No background on it"; it was a round plate with red, yellow and green numbers punching in at twice their size), above your head at 0.27 of the screen, swelling a touch as each lands and fading in and out, with a rising ping; the 1 stays up until GO! replaces it; the sting fades |
| 14 | GO! in the game's colour, no plate or tilt, for 0.9 s as Play starts; the whistle pitched up over a low boom; the game track starts from the top |

Someone watching (not in the game) gets the flight past everyone over 3.5–9, ending high over the
arena at 10. The others' bodies stream in to your client only once you're placed on the arena (at
the intro's start often just one bot's has arrived), so the flight is aimed from your own position
and re-reads the contestants at 0.5 and 1.0 s, before it reaches them.

Files: `Client/Systems/RoundIntro.lua` (the camera on the engine's `CameraService:AddLayer` with
`KeepBaseCamera`, the name pops, your moment's extras; removed on any phase change or respawn),
`HudIntro` (title card, blurb, controls), `HudHero`, `HudCountdown`, `HudLetterbox`, `BumpMusic`
(sting, pings, GO) and `BumpSounds` (`IntroSting`, `CountdownBeep`). `HeroPose` is in
`clips_bump.py` (`hero_pose`: a dip, then popping up into a fist punched high, the other arm
out, head cocked, weight on one leg, a small settling bounce; previewed and approved), played as
`HELD.Hero` in the Animator. The board has a "Your moment" scenario. Seat colours live in
`RoundInfo.SeatColors` (the bots and the name pops read them; the UI keeps its tokens).

Measured in Play (2026-11-14) at 14 s: 7 names popping 3.4 to 6.1, the title card gone by 5.5,
move Hero and the name card 6.8 to 10, the gameplay camera back by 11, the jingle 0 to 10.6, Play at
14. Earlier, at 8.5 s, the flight: all 7 names popping 0.2 s apart from 1.67 to 2.94, the
camera 16 to 17 studs from each as it passes at 100 to 180 studs/s, turning at 150 to 250°/s, slowing
from about 100 to 0 studs/s into my moment. First tries passed 10 studs out and whipped the view
round at up to 1,400°/s, popped only 1 to 3 names (bodies not streamed in yet), and flipped the view
as it dived in (aiming at the middle while flying in between it and the others). Measured earlier
(2026-11-13), with the old lineup: my move Hero 3.3–5.0 with the camera 15 → 11 studs at 5 to 38 degrees off my face, FOV 52 → 46, my spotlight
18 then back to 7 by 4.9, `HudHero` visible 3.5–5.0, the gameplay camera back by 5.7, Play at 8.5;
on screen my body spans 33% to 83% of the height at 58% across, the fist in frame. Captures:
`design/animation/intro_hero.jpg` (pose, name card, YOU pill, bars) and `intro_countdown.jpg` (the
bare "1" over the arena); measured 3, 2, 1 a second each from 5.5, GO! from 8.65 to 9.6. First tries were too close
(7 studs hid the head behind the fist), behind the shoulder (orbiting from the arena's inward
line, not the body's facing), and the blurb overlapped the card. **Trap:** `screen_capture`
lags 1 to 4 s in Play, so a capture meant for a moment is fired a couple of seconds early, and
it doesn't draw BillboardGuis, so the name pops (and every billboard effect: comic words,
power-up callouts) never show; check them by their properties. **Not seen:** GO! on screen, the
flare's burst in a capture, a phone, how it feels.

## Eliminations (2026-11-14)

The user: "Can we show "ELIMINATED BY X"'s and show a camera shot of the character on deaths?";
their choices: only your own elimination gets the camera shot (others get a small feed line), and
the shot shows you going down, then who did it.

- **Who did it:** the games blame the last hitter (`participant.LastHitBy` with `LastHitAt`):
  BUMP's `blame` on ball hits (the attacking ball's rider), run-overs, dives/shoves/pounds
  (`onBodyHit`) and ripples/Shockwaves (their source); Bomber's `knock(..., by)` on passes, blasts
  (the holder), dives/shoves and Shockwaves, and the bomb's `from` (who passed it) when it goes
  off on you. A fall within 4 s of a hit names them (BUMP's `fellWhy` returns reason and by).
  `ctx.Eliminate(participant, reason, by)` prints `[Round] X out (knocked off by Y)`.
- **Your elimination:** `You "KnockedOut"` now carries `By`, `BySeat`, `ById`, `Reason`. The
  server leaves your body where it went for `RoundInfo.KnockoutHold` 1.5 s (attribute
  `BumpKnockoutHold`, which the lobby's fall catch skips) before the game moves it to the stand.
  `Client/Systems/KnockoutCam.lua` (a camera layer, priority 45): 1.4 s looking down from just above
  where you went out at your body sinking (your own client caps every part's speed at `SLOW_FALL`
  16 studs/s: at full speed it was a dot 130 studs off within half a second), FOV 64 to 50; then a
  0.4 s swing to the eliminator and 1.6 s on them from in front (FOV 46); then a 0.5 s fade back.
  With nobody to blame it holds on you 0.6 s longer. `HudKnockout` is now bare text low in the
  middle (`Layout.Knockout`): "ELIMINATED BY", the name huge in their seat colour (or "ELIMINATED"
  and why), then place and gold.
- **Polish** (the user: "Can we polish it massively?"; they chose the card and the sound, punchy
  cartoon). The games also record how (`LastHitHow`: ram, runover, dive, shove, pound, shockwave
  in BUMP; pass, blast, dive, shove, shockwave, bomb in Bomber), sent as `How` with `ByUserId`.
  `HudKnockout`, after "We can make it look MUCHHHH better than that" and three mockups, is
  **cartoon broadcast bars** (their pick over a comic burst and a wanted poster): chunky slabs
  sweeping in from the left edge, low (`Layout.Knockout`, bottom left, phone at 0.62 scale), so
  the camera's shot keeps the middle. Each slab is a face, a thick ink outline and a hard ink
  shadow, three CanvasGroups so the slanted right end (a rotated piece) clips clean. At once the
  yellow (Gold) bar whips in with an overshoot and ELIMINATED! (Gotham Heavy Italic,
  `Tokens.Fonts.DisplayItalic`) pops on a letter at a time, each tipped; at
  `Tokens.Timing.KnockoutReveal` 1.5 s a bar in the eliminator's seat colour whips in under it, their
  face (`UiPortrait` in an ink and white ring) bursts out of its left end spinning upright, BY and
  their name in white with a thick ink outline, then an ink pill saying how in gold ("WITH A DIVE",
  "RAN YOU OVER"); with nobody to blame the bar is red and says why (FELL OFF!); place and gold
  fade in above; at `KnockoutSeconds` 3.7 the bars whip back out, top first. Captures:
  `design/animation/knockout_broadcast.jpg`, `knockout_broadcast_felloff.jpg` (taken before the
  reason text was pulled in to line up with the shout; not re-seen). The card's whole timeline:
  Sounds (`BumpMusic`, `BumpSounds.Knockout*`, Pro Sound Effects and APM): a cartoon
  clang, a slide whistle and a thud at once, a whoosh into the swing, a balloon pop and APM's
  "Fairytown Waltz - Tag3" comedy tag on the reveal; the game track muffled (an Equalizer on it,
  highs -30) until the card goes. Measured: every beat on time. To capture the card, fire
  `KnockedOut` at your client from the server's `Bump:You` remote and capture about 1.8 s later
  (captures lag). **Not heard:**
  the sounds were picked by their catalogue descriptions (whether the slide whistle falls or rises
  is unknown).
- **Falling under the map, Mario style** (the user: "When falling under the map, we should have a
  mario style camera follow disappearing into the screen turning black"; their choices: everywhere,
  an iris, and in a game only when nobody knocked you off). `Client/Systems/FallCam.lua`: the camera
  stops where it is and turns after you for 0.45 s, you drop away at full speed, an iris (a round
  frame with a huge black UIStroke, no image; DisplayOrder -10 so the HUD stays over it) closes on
  where you are on screen from 0.35 s over 0.75 s, the body is held still (anchored on your client)
  so it can't reach the kill plane at -500, it stays black until you're back above y -20 (0.35 s at
  least, 3 s at most), then opens from the middle. In a game, KnockoutCam hands it any knockout with
  no `By` (not "blew up"); the game moves you to the stand. Outside a game (the lobby's pit, off the
  yard: below y -40 and dropping, not a live contestant) FallCam plays it itself and, once black,
  sends Act "Fallen"; `Lobby` puts you on the plaza or the yard at its word (the server's copy of a
  falling body can be stuck where the fall began), at most once every 2 s, printing `[Lobby] X put
  back on the plaza (asked)`; its own catch below -45 now waits 3 s as a backstop. Measured: black at
  1.5 to 1.7 s, back on solid ground within 0.05 s of asking, open by 2.4 to 2.6 s, no respawns. Not
  seen in a capture.
- **Found on the way:** the whole Lobby system had been failing to load since the lobby was split
  into `Server/Lobby/Neon.lua` ("61 of 62" systems in the log: `pad()` set `label.Font = FONT`,
  never defined), so everything after the pads never ran: the fall catch, the door screens' live
  text, the confetti and fireworks. Fixed (`Neon.Font`); 62 of 62 load. The engine records a failed
  system as `ServerScriptService["[SOME SYSTEMS FAILED TO LOAD (n)] ServerMasterLoaderConfig"]`
  with an `ErrorMessage` attribute: check it whenever the log says fewer than all loaded.
- **Everyone else's:** `You "Eliminated"` to the other players (RoundClient emits `Eliminated`);
  `HudFeed` (`Layout.Feed`, top left; top right on a phone) lists "MOCHI eliminated FIZZ" or "FIZZ
  fell off / blew up", names in seat colours, four at most, each 4.5 s.
- Measured in Play (one idle player, seven bots): knocked off by Noodle, then by Tumble: the card
  named them, my body sank at 22 studs/s staying 20 to 41 studs from the camera and on screen, the
  camera then followed the bot on its ball, back to normal by 3.5 s; the feed got the bots' eliminations.
  The feed was seen drawn in a later capture ("Waffles eliminated Pogo"). **Not seen:** a phone.

## Spectators (2026-11-13)

A revenge launcher was built and then removed at the user's word ("Let's remove it"): anyone not
playing lobbed goo blobs from the plaza that pushed riders' balls or staggered people on foot,
the same in every game. Spectators have no way to act on a round now; the other ideas offered
were winner predictions and crowd votes on chaos. Ask before bringing any back.

## Power-ups and progression (2026-11-13)

The user: "We should add power ups and progression elements that can be purchased with gold".
Their choices: bring one power-up into each game and press a button to use it, once a game (bots
bring one too); the first set is Shield, Turbo, Shockwave and Second Chance; progression is
both kinds (gold unlocks then upgrades each power-up to level 3, and a player level from XP
gates the higher upgrades); a shop button that works anywhere (they turned down a storefront).
Every number is a first guess, all in `Shared/PowerUps/PowerUpInfo.lua`.

| File | What it does |
| --- | --- |
| `Shared/PowerUps/PowerUpInfo.lua` | The catalogue (name, glyph, colour, blurb, per-level numbers), prices 20 / 50 / 100, level gates 1 / 3 / 6, XP (10 a game + 15/10/5/0 by place, 20 a session; level n to n+1 takes 50 + 25n), attribute names |
| `Server/Systems/Progress.lua` | The save (`Bump = { Xp, PowerUps, Equipped }` in `Server/DefaultProfileData`), mirrored onto player attributes; the shop (`Act "Shop" "Buy"/"Equip"`, answered `You "Shop"`), paid through the engine's `SpendCurrencyPromise`; `AwardXp` (`You "XpEarned"`). In Studio a number attribute `BumpDebugGold` on a player gives that much gold |
| `Server/Rounds/PowerUps.lua` | In a game: `Arm` (after `Place`), `Use` (`Act "PowerUp"` or a bot's brain), `Shielded`, `Ready`, `TryRescue`; each game registers its own Turbo/Shockwave/Rescue through `SetGame`. Prints `[Power] X used Y` |
| `Client/Systems/PowerUpClient.lua` | Q / gamepad Y / touch `primary3` fires it (chip named after the power-up, hidden once you're out); B / Select toggles the shop (no chip); a Second Chance's bounce |
| `Client/Systems/PowerUpFx.lua` | The name popping over the holder, the shield bubble, Turbo streaks and trail, Shockwave's floor ring and boom, Second Chance's column of light; built from pieces BumpFx now exports |
| UI | `HudShop` (rows, unlock/upgrade/equip, level and gold header, the server's reply), `HudShopButton`, `HudPowerUp` (the slot, pressable), `HudLevel`, `HudLevelUp`, `UiPowerIcon`; results show +XP. The catalogue reaches the UI as the source's `Catalogue` (UI can't require Shared). Board scenarios "Shop" and "Level up" |

**What each does as built:** Shield 3/4/5 s: ball hits, knock-offs, dives, shoves, ripples, a ball
running you over and blasts do nothing, and in Bomber the bomb can't be passed to you (it doesn't
save the holder). Turbo: on a ball a full dash at once (`BallPhysics.Boost`, a player's client is
told `You "Turbo"`), on foot run speed x1.5 for 2/2.5/3 s (`BumpBoostScale`, separate from the bomb
holder's speed). Shockwave 20/25/30 studs: the pound ripple from where you stand, riders wobble,
people on foot are thrown. Second Chance (automatic): the first fall puts you back on safe floor
(shield 0/2/4 s after). Bots get a random one at level 1 or 2 and use it when it makes sense.

**Measured in Play (2026-11-13), one player and three bots:** buying with 0 gold refused ("You need
20 gold"), level 2 refused below level 3, unlock and equip saved to the attributes; a shield bubble
of 9 studs for 3 s, the slot greyed "Used"; Turbo on foot 35 to 53 studs/s for 2 s; Turbo on a ball
20 to 74 at once; Second Chance caught a fall on foot (Bomber) and a rider rolling off (BUMP); bots
used all four in both games and their ripples reached riders; XP took a fresh profile to level 2 in
one session; the shop drawn in Play (`design/` has no capture yet). **Found and fixed on the way:** a
rider rolling off was knocked out late, from the kill height: their body stops updating on the
server as it falls (frozen at y -35 while the client fell past -500), so BUMP now judges a rider's
fall by their ball; and a bot whose body was lost in the void was reused next game and knocked out
at once ("no body"), so `SpawnBot` respawns it. **Not seen:** a player's own Shockwave, the level-up
banner in the game, a phone or gamepad, two players, and saving across sessions (the Studio
datastore is in memory).

## Loading screen (2026-11-14)

The user: "change the loading screen for this game to something super simple? Let it say "Pls
hire me Cinnamon, hehe"". `src/ReplicatedFirst/BumpLoading.client.lua` (mapped as
`ReplicatedFirst.BumpLoading` in both project files; no requires): removes Roblox's default screen
and shows that one line, white Gotham Bold on a plain dark screen, at DisplayOrder 1000000 so it
covers the engine's own UI loading screen (Sunshine Valley's art, DisplayOrder 100000, engine
code, left alone). It fades out once the game is loaded, `PlayerDataLoaded` is set, your character
is in, and the engine's screen is done (`LoadingScreenActive` off and its `LoadingScreenFade`
hidden): at least 1.5 s, at most 30 s. Prints `[Loading] hiding after N s`. Measured in Studio:
3.2 s, the engine's screen already hidden underneath. Adding a top-level mapping to the project
files needs the dev server's generated project (`.bump.rojo.project.json`, written at `dev-all`
start) rewritten: `dev_tasks.write_common_rojo_project(dev_tasks.build_common_rojo_project())`
does it without a restart.

## Adding a system

A system is a plain module with `start()` (and optional `init`, `playerAdded`, `characterAdded`),
the engine's usual shape. Put it in `src/Server/Systems` or `src/Client/Systems` and add its path
to `src/Shared/SystemList.lua` (`@GameServer/Systems/<Name>` or `@GameClient/Systems/<Name>`).
The master scripts build their load orders from that list.

## Day to day

- `python3 BUMP/tools/dev_tasks.py dev-all`, then connect Studio's Rojo plugin to
  `127.0.0.1:1355`. Add `--shared-engine` if another game's stack is running. Resources serves
  on 13418.
- No watchers: `python3 BUMP/tools/dev_tasks.py prepare --shared-engine` (sourcemap and
  darklua; proves every file parses and every require resolves).
- The game's place is the user's Team Create, placeId 105611532229008 (in
  `Constants.GamePlaces`); the Studio window was titled "Arcwise's Place". Work and test there:
  `dev-all` running and the Rojo plugin in that window connected (the user clicks Connect). A
  running Play session keeps the old code, so restart Play after an edit.
- That place has Studio access to API services off, which made the engine kick the player
  ("Saves can't be reached"); `Constants.DataStores.USE_MOCK_DATASTORE_IN_STUDIO` is true to get
  round it, so Studio profiles are in memory. Turning the setting on is the user's call.
- `zsh BUMP/tools/open_place.sh` builds `$TMPDIR/BUMP.rbxl` and opens it in Studio.
  Its `pkill` doesn't close the old window, so each run adds one: close your own old test windows
  and leave any the user may be in.
- A local place file from `open_place.sh` has PlaceId 0: profiles are in memory, and a few engine
  server systems (social, codes, world sync, referrals) fail to load there; that's expected
  noise in a local file.
- Terrain `Decoration` and `GrassLength` can't be set by scripts; they're in the project files
  (`Workspace.Terrain`), as is `Lighting.Technology = Future`.
- Specs (`*.spec.lua`) use the Nevermore Jest loader like the other games and aren't built. BUMP's
  (2026-11-14): `Hex`, `BallPhysics`, `Moves`, `PowerUpInfo`, `MeltLayout`, 28 cases. Nothing here
  runs Jest, so they were checked by pasting their bodies into `execute_luau` in Edit with a small
  describe/it/expect stand-in, against the built modules: all passed. **Trap:** a module required
  from `execute_luau` stays cached after Rojo changes its Source; require a fresh Clone parented
  next to it (relative requires need the parent), then destroy the clone.
- Studio only: a minigame's id in `ReplicatedStorage.BumpRound`'s `DebugGame` attribute (set from
  the Server view once Play starts, before the lobby count ends) plays that game every time.
- History is on branch `bump-game` (2026-11-14): the work in seven commits by feature, then the
  tidy (the dead triple-jump chain removed, BumpBots, the Fx split, Moves, the specs).
- The engine's demo switches (`Constants.DEMO`) default on. `MailDemo` posted a "Goodbye!" letter
  with a free item (6007) to everyone leaving, and any mail brings up "You have new mail!" on join
  (the user asked why, 2026-11-14: every Studio Play stop had added one, 50 by then, in the real
  DataStore `ArcwiseAccountMail_v1`, key = UserId). BUMP's `Constants.DEMO.MailDemo = false` now;
  `WorldSyncDemo` and `GachaDemo` are still the engine's default (on).

## The lobby (2026-11-13)

The user's path: a hex lobby round the arena so spectators watch by walking round; Blender
concepts (bowl, plaza, islands, then colourful playground and parkour, in `design/lobby/`) were
turned down for "a more standard roblox lobby experience" styled on their own place **AR**
(placeId 85489799802972, same owner as BUMP's place): a night-time neon city hub. They liked a
neon concept, asked to reuse AR's assets, and pasted AR's `Game | Main Folder` into BUMP's place.

| What | Where |
| --- | --- |
| AR's hub, placed in Studio (not in the repo) | `Workspace.Lobby`: stores, plaza, gates, lanterns, skyline, clouds, AR's invisible bounds. Moved so AR's centre (-171, 0, 163) is the origin; the temple, pool and everything under 100 studs from the centre cleared down to AR's cloud floor (-73) |
| BUMP's signs on it | `Workspace.Lobby.BumpSigns`: SUMMON became REWARDS, RAIDS became PRACTICE, LAB became LOCKER (neon SurfaceGui text where AR's 3D titles were); PLAY, LEADERBOARD, SHOP kept. AR's "Anime Rush" skyline sign became BUMP!; AR's logo, anime unit figures, the "Anime Co." plate and its mechanic labels (S+, Stat Reroll, CLOSED...) removed; the pillar banners say PRACTICE. Japanese neon panels kept as city flavour |
| AR's walk-in areas, removed (the user: "remove areas that shouldnt exist like the play area in the lobby") | PLAY's matchmaking hall of pods (everything past x 186), RAIDS' elevator lobby and pods (past x -187), REWARDS' gacha room at the end of its street (z < -318, below y 50; the tall tower behind stays). Their doorways are filled by `Lobby.lua`: `World.PlayDoor` a live screen (the round's title and line), `World.RewardsDoor` "REWARDS / COMING SOON", `World.PracticeDoor` a green portal to the yard. LEADERBOARD's alcove and LOCKER's hologram door were already shallow and stay |
| `Shared/World.lua` | Where things are: `ArenaOrigin` (0, -6, 0), `PitRadius` 100, the wall, `YardOrigin`, `SpawnCFrame` (-132, 3.5, 0), `LobbySpot()` (a raycast spot on the plaza facing in) |
| `Server/Systems/Lobby.lua` | Builds `Workspace.LobbyFx`: the invisible `PitWall` (radius 101, y -5 to 120; nobody walks in, contestants can't jump out, thrown sideways you still drop into the gap; the platformer's raycasts ignore it), a glass and neon rail, the jumbotron over the arena (six screens, live from `BumpRound`), searchlights, a coin ring, balloons, a blimp, a giant BUMP! sign over Play, confetti and fireworks during Results/Standings, the PRACTICE doorway portal to the yard and a pad back, the door screens, and a catch below y -45 |
| Lighting | AR's night, brightened (the user: "make the world a bit brighter"): `ClockTime` 0, `Brightness` 2.2, `ExposureCompensation` 0.35, more ambient, in both project files (the dev server serves `build.project.json`, copied when `dev-all` starts: restart it after editing either); Sky, Atmosphere (density 0.25, haze 1.4), ColorCorrection (brightness 0.04, saturation 0.15), Bloom (0.35, threshold 0.9), SunRays set in the place |
| Arena build-in and fly-out (`Client/Systems/ArenaShow.lua`) | The user: "Each time we change the map, could we have a AAA ADHD sequence of the map loading in piece (or chunk) by piece?". A HexArena folder carries `HexArena`; when it appears (the game's intro, everyone frozen) each client hides the real tiles (`LocalTransparencyModifier`, still solid) and drops copies in from 55 studs up, spinning, ring by ring from the middle (0.2 s apart, sweeping round each ring), each landing with a bounce, a white flash fading to its colour, a ring and sparkles, and a ping climbing a step per ring; then a shockwave across the arena, confetti, a bang and a shake (about 2.2 s for BUMP's 7 rings). `HexArena:Destroy` makes the old arena unsolid, renames it `*_Leaving`, sets `Leaving` and goes 1.6 s later while clients fly its tiles off upward, rim first. Then (the user: "It looks like the map unloads whilst one's already loaded ... It needs to visibly unload, and then reload the new map before the round even starts ... before the round even teleports the players into it"): RoundServer now runs a `Changeover` phase. At the end of a game, anyone still in the pit is put on the plaza, the arena leaves and the round waits `HexArena.LeaveSeconds` + 0.4; the next game's `Setup` only builds its arena (returning `HexArena.ShowSeconds(rings)`), the round waits that out, and only then `Place` puts everyone on it and the frozen intro starts (the card straight away again). The jumbotron says NEXT UP. Measured in Play: Results, then the BUMP arena flying off for 1.6 s with everyone on the plaza, the pit empty for 0.4 s, the Bomber arena landing over 1.8 s, then everyone on it and the intro |
| KO blast (`BumpFx.onKO`, fired from `ctx.Eliminate` as Fx "KO") | The user: "a super smash bros style effect for eliminations" (our own take, no Nintendo art): at the arena's edge where someone went out (or where the bomb blew), a flash swelling to 40 studs, a 140 stud beam and about 20 streaks up and out in their seat colour, a 95 stud shockwave ring, stars and sparkles, a sped-up explosion with a slowed ping, a shake by distance; the last KO of a game is 1.5 times bigger. Seen in Play frozen 0.25 s in (`design/lobby/J_ko_blast.jpg`) |
| `Server/Rounds/Spotlight.lua` | A SpotLight 18 studs above each contestant's root, pointing down, warm white tinted by their seat colour; on from the intro, off when knocked out, survivors keep it through results. A visible beam cone was tried and turned down ("get rid of the cone spotlight. We just need the light itself") |
| Baseplate and spawn | Project files: the baseplate is under the yard (0, -8, 1600), the spawn on the plaza (-132, 0.6, 0) |

Both games play in the pit: arena tops at y -6, out below -26 (was -36). Tiles are `Hex.BuildTile` with an
`edge` colour: a thin plain (not Neon) outline round a slate top. The first neon tiles glowed so
much that "It's hard for the players to see eachother". Seen in Play: the intro put everyone on the neon
arena, the HUD and stores behind it; knocked-out players fell to -36 and were put on the plaza.
Also seen: Bomber in the pit (yellow to red tiles, "Tumble has the bomb!"), the PLAY door screen
up close, the PRACTICE portal glowing. **Not seen yet:** walking through the portal, the confetti
and fireworks, phones, and
how heavy AR's 6,000 parts and 350 lights are on a weak device. Studio traps: after restarting `dev-all` the plugin can look connected but sync nothing until a
Disconnect and Connect (check a changed module's `.Source` before testing); a module required from
`execute_luau` gets its own copy, so `Remotes.Fx` fired from there never reaches the game.
`execute_luau`
can't send data to localhost (allowlist) and a hub is ~2–3 MB serialized, so moving models
between places is the user's copy and paste.


## Lobby stores, daily reward, ball sounds (2026-11-14)

Asked whether BUMP meets the Cinnamon Software trial brief (48 h, judged on idea, feel, UX,
replayability, UI, art, polish and code; code-only repo, a 5-minute video, and an explanation of AI
and assets), I listed must-dos and the user said start them. Done here:

| What | Where |
| --- | --- |
| SHOP and LOCKER open the power-up shop | `Server/Systems/Stations.lua`: a glowing pad at each doorway (`World.ShopSpot`, `LockerSpot`, dropped onto the floor by a raycast) with a ProximityPrompt on **F** (E is the shove) / D-pad up / tap; the server sends `You "OpenShop"` and `RoundClient` opens the shop |
| REWARDS is a daily reward | `Progress.ClaimDaily`: once a UTC day, gold `Daily.Base` 15 + `PerDay` 5 x (streak - 1), streak up to 7 (`PowerUpInfo.Daily`); saved as `Bump.Daily = { Day, Streak }`, mirrored to `BumpDailyDay` / `BumpDailyStreak`; `Client/Systems/StationClient` writes your own prompt text ("Claim 15 gold" / "Back in 23h 36m"). The door screen says DAILY REWARD |
| LEADERBOARD's three boards | Stations puts a screen on each of AR's `LeaderboardTemp` boards, titles on their red headers: LAST WINNERS (game and name, seat colours), WINS TODAY (bots count), PLAYERS HERE (by XP). Read from the round's `Results` attribute; server-only (no global boards: no API access) |
| Lobby helpers | `Server/Lobby/Neon.lua` (palette, font, `Part`, `Sign`), shared by Lobby and Stations |
| Ball sounds | `Client/Systems/BallSounds.lua` (sounds in `BumpSounds`): every BumpBall loops a Pro Sound Effects skateboard roll (from 3 s, `LoopRegion`) whose volume and pitch follow its speed along the floor, cut in the air, with a thump landing after 0.3 s airborne; `BumpFx.OnMove` hands it rider moves for a tyre swerve on RideSkrrt, an ascending whoosh sped up as RideCharge fills, and a zoom whoosh on RideDash. `AI_AND_ASSETS.md` is the brief's write-up (in the user's voice; theirs to edit) |

Measured in Play: the pads sit on the floor at each store (seen); F at REWARDS paid 15 gold, the
counter showed 15 and the prompt turned to "Back in 23h 36m / Day 1 streak"; the boards filled
after a game; every ball's roll followed speed (0 at rest, 0.27 at 16 studs/s, 0.55 at 42, pitch
0.7 to 1.54 in a dash), and landings thumped. **Not seen:** the skid, charge and launch sounds
firing (the first run had the alias bug below; Play was stopped before the retest), any of it
heard by the user, the shop opening from a pad, a second day's streak.

**Trap:** client modules require each other as `@Client/Systems/X` (server: `@GameServer/...`).
`@GameClient` is only for `SystemList` paths; a `require("@GameClient/...")` passes `prepare` but
fails at runtime ("@gameclient is not a valid alias") and takes down everything that requires
that module (BumpFx took Animator, PowerUpFx, PopFx and RoundIntro with it).
