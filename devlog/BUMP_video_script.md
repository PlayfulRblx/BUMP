# BUMP: narration

4:56 of gameplay in three stretches, with hard cuts at 3:37 and 4:45. Each beat starts at its timecode, over what's on screen; the same lines sit in a marker's note in the timeline. Swap in your name in the first line.

**0:00** · The lobby counts down; the BUMP card *(20 s, 48 words)*

Hi, I'm [your name], and this is BUMP, a party game I built for the Cinnamon trial. You arrive in a neon city hub with the arena sunk into the middle, and a session is six quick minigames back to back. Any empty seats are filled by bots.

**0:20** · BUMP: riding, the dash, the hit, knocked off *(16 s, 31 words)*

The first game is BUMP. There's one ball fewer than players: you ride a ball, charge a dash and roll everyone else off while the floor crumbles away. And... I'm out.

**0:36** · Back on the plaza, walking the rim *(23 s, 54 words)*

Being knocked out isn't dead time. You're back on the rim, and the jumbotron keeps up with the round. I wanted a cartoony, Nintendo-ish feel with a minimal UI that stays out of the way. The bots wear your friends' avatars and names, so even a half-empty server feels like your mates are there.

**0:59** · Bomber's intro: the flyover, the hero pose, 3-2-1 *(11 s, 24 words)*

Every game opens with a camera flight past the whole line-up that lands on you for a hero pose, then a three, two, one.

**1:10** · Bomber Bloxians *(14 s, 30 words)*

Bomber Bloxians: pass an enormous ticking bomb by touching someone. The fuse is hidden, so the ticking speeds up instead, and every blast bites a crater out of the arena.

**1:24** · Bomber, running and dodging *(44 s, 97 words)*

Movement is the part I cared about most. It's a custom controller, a state machine for every move, with Roblox's stock jump turned off. Jumps rise quickly and fall heavier than they rise, and you can steer in the air to get yourself out of trouble. I had a triple jump for a while, but it felt awful and didn't fit, so it went. The shove started as a big lunge and became a short, snappy burst. Every movement number is live-tunable in Studio while you play, so it was tuned by feel rather than by guesswork.

**2:08** · The last of Bomber; the shop opens *(22 s, 40 words)*

Placing earns gold and XP. Gold buys and upgrades power-ups: Shield, Turbo, Shockwave and Second Chance. Your level from XP unlocks the higher upgrades. That's the reason to come back: a short competitive session that also moves your character forward.

**2:30** · MELTDOWN: the card, the climb, melted *(32 s, 55 words)*

The third game is Meltdown. Lava rises up a tower of floating platforms: crumbling ledges, moving platforms, bounce pads and wall-jump chimneys, with fireballs, surges and falling debris on the way up. The tiers are spaced so you need your float jump, and a ground pound shakes everyone off your platform. And there I go.

**3:02** · The lava tower from above *(35 s, 76 words)*

On the technical side, systems are plain modules registered in a load-order list, the same pattern as my own framework. Movement, effects and anything that needs instant feedback run on the client so it feels immediate, with checks on the server to keep the responses valid. The UI kit was built in UI Labs first, from modular components and design tokens, so every screen stays consistent. And problems were tracked down by measuring rather than guessing.

**3:37** · Final standings; the next lobby; the hero intro; BUMP *(52 s, 104 words)*

After six games you get the final standings, and it's straight into the next session. On AI and assets: Claude Code wrote a lot of the Luau from my direction, one feature at a time. I set the structure and the programming style, then reviewed it, staged it and sent it back. I made the simple assets in Blender, and used Nano Banana image models to expand on inspirations. The lobby is reworked from an unfinished project of mine from a couple of years ago. Animation is my weak spot: I know the feeling I'm after, and that's where I'd lean on great animators.

**4:29** · Run over; the camera swings to who did it; results *(12 s, 21 words)*

When you're knocked out, the camera follows you down, then swings round to whoever did it. Egzekiel, there, running me over.

**4:41** · Results; Bomber; the bomb pops *(16 s, 38 words)*

I've got more ideas in the same spirit: Silly Billies, The Scramble, Steal The Sky and Build a Boss. But that's BUMP: quick to pick up, easy to come back to, and built to grow. Thanks for watching.
