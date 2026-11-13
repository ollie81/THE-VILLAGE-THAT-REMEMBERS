# The Village That Remembers: adventure plan

This file is the audit, the list of what's missing, the technical plan, the development order and the
first playable milestone for turning the village game into a village-life adventure with combat.
It is kept up to date as milestones land.

## 1. Audit: what the game already has (verified in code and tests)

| Area | What exists | Where |
| --- | --- | --- |
| Player | Third-person controller: walk, run (joystick to the rim), jump, sit (seats and ground), lie down/sleep, short actions (chop, mine, build, gather), wave/bow/cheer/dance, footsteps | `scripts/player/player_controller.gd`, `scripts/ui/actions_menu.gd` |
| Camera | Orbit camera with wall collision, never below the ground; Village View (high, pan/zoom/tap a villager); conversation close-ups with a face light | `scripts/player/camera_rig.gd` |
| Controls | Touch joystick, drag-to-look, pinch zoom, Jump and context button (Talk/Chop/Build...); keyboard and mouse | `scripts/ui/touch_controls.gd`, `scripts/core/input_router.gd` |
| Characters | Code-generated skinned low-poly humans: one shared skeleton, faces with blend-shape expressions, hair, beards, hats, clothes, ages (child to elder), level of detail, mesh cache, built on a worker thread | `scripts/characters/*` |
| Animations | 14 hand-keyed clips (idle, walk, run, jump, work, gather, talk, wave, sit, sit_ground, sleep, cheer, dance, bow) | `humanoid_animations.gd` |
| Villagers | Five founders plus generated newcomers (no clones): schedules, homes, jobs, routes, needs-like happiness, ambitions, relationships, marriages, children, ageing, death, leaving | `scripts/villagers/*`, `scripts/population/*` |
| Memory and talk | Episodic memory, gossip, opinions, remembered deeds, kind/unkind actions, non-repeating chatter about real events, voices (Android TTS or babble) | `villager_mind.gd`, `chatter.gd`, `dialogue_service.gd`, `voices.gd` |
| World | Procedural terrain, river and bridge, meeting circle with fire, five homes, storehouse, workshop, garden, farm, travellers' camp, forest and outskirts (MultiMesh trees, rocks, grass, flowers), day/night with sun and moon | `scripts/world/*` |
| Gathering | Chop any tree, mine any rock, pick herbs; they regrow | `wild_harvest.gd`, `resource_node.gd` |
| Building | 13 buildables in a tabbed menu, green/red preview that finds free ground, staged construction, move/remove, village beauty | `build_mode.gd`, `structure_catalog.gd`, `placed_structure.gd` |
| Crafting | One recipe: tools at the workshop (+1 per harvest) | `world_objects.gd` |
| Progress | First-week objectives with a guide (marker, edge arrow, Build hints) and rewards; daily requests; daily welcome gift; weekly festivals; villager stories | `game_state.gd`, `guide.gd`, `request_board.gd`, `daily_gift.gd`, `festival.gd`, `village_stories.gd` |
| Economy and ads | Wood, stone, food, herbs; optional rewarded ads (simulated in debug builds; AdMob plugin not installed) | `game_state.gd`, `ad_rewards.gd` |
| Audio | Procedural music (day/night), effects, ambience, fire, volume settings | `scripts/audio/*` |
| Save | One JSON save (clock, player, every villager's mind, population, structures, requests, gift, festival, stories), autosave every minute and when the app is paused | `save_service.gd` |
| Tests | 9 headless suites in CI (smoke, gameplay, population, life, hooks, build, sound, guide, retention) plus a debug APK build | `tests/`, `.github/workflows/build.yml` |

## 2. What's missing for the adventure vision

- **Interiors**: houses are closed boxes; villagers vanish inside. No furniture, shops or interior interactions.
- **Combat**: no health, damage, weapons, attack/block/dodge, enemies or knock-outs. No combat animations or sounds.
- **Monsters and bosses**: none.
- **World beyond the village**: the playable area is about 124 x 124 m around the village; no caves, ruins,
  mountains, dungeons or unlockable areas; no area streaming.
- **Village defence**: no threats, raids, damage or repairs.
- **Missions**: the first week's objectives, daily requests and festivals exist; no storyline after week 1,
  no villager-specific missions with steps, no quest log.
- **Equipment and crafting**: one recipe (tools); no inventory of items, equipment slots or upgrades.
- **Camera**: tree canopies (which have no collision) can hide the player.
- **Presentation**: the village is tidy but sparse around the homes; weather is missing.
- **Not verified on a phone**: performance, touch feel, Vulkan renderer (only tested with OpenGL on a server).

## 3. Technical plan

Principles: reuse the existing systems (Interactable/UsableObject for anything usable, the action system for
animations, SaveService sections for persistence, the Guide for pointing at goals, SoundBank for effects,
MeshBuilder for low-poly models), keep everything procedural (no external assets needed), and keep every new
system behind tests.

- **Interiors** (`Interiors`): rooms are built on demand from code at a spot far outside the world, so entering
  is a short fade and a teleport with no scene loading. Each home gets a layout from its owner (bed, table and
  chairs, hearth, shelves, rug, chest, lamps, windows, colours matching the house). A door outside and inside;
  the camera switches to a closer indoor setting; saving indoors saves the doorstep. Your house: sleep in bed,
  cook at the hearth. Others' houses: sit at their table. Rooms are freed when you leave (memory stays low).
- **Combat** (`PlayerCombat` on the player, `Enemy` base): health, damage numbers and a red flash, knock-back,
  short invulnerability after a hit, a sword slash with a hit arc, a shield block (hold), a dodge roll with
  invulnerability frames, eating a stew to heal, being knocked out (wake at home, nothing lost). New animation
  clips: slash, block, roll, hurt. Sword and shield attach to the hand bones. Touch buttons (Attack, Block,
  Dodge, Eat) appear only when you're armed and enemies are near, so village life stays uncluttered.
- **Enemies**: a state machine (wander, notice, chase, wind-up, attack, recover, hurt, defeated) with readable
  wind-ups. Low-poly procedural bodies animated by code (no skeleton needed for creatures). Encounters are
  placed spawn groups with respawn timers, saved.
- **Equipment and crafting**: the workshop bench gains recipes (sword and shield first, later upgrades);
  equipment is saved in GameState flags; later an item inventory if recipes grow.
- **Adventure areas**: new regions attached at the world's edges through gates/paths, built like the village
  (procedural terrain patches, MultiMesh scatter), unlocked by progress; caves as interiors (same teleport
  method as houses). Bosses live at the end of an area with telegraphed patterns.
- **Village defence**: occasional raids by creatures from the forest (announced, with time to prepare),
  damaged structures that lose function until repaired with the existing Build action, villagers' requests for
  protection through the existing RequestBoard.
- **Missions**: a quest log on top of GameState flags with steps that point the Guide at targets; villager
  missions offered through the existing conversation menus.
- **Performance**: rooms and enemies only exist near the player; enemies think every few frames when far away;
  effects are pooled; everything measured in tests and on a phone before more content.

## 4. Recommended development order

1. **Milestone 1 (this one)**: enterable homes, a livelier village, a camera that sees past trees, and a basic
   combat encounter (sword and shield from the workshop, thornlings in the west woods).
2. Phone check: install on a real phone, measure FPS, tune controls and camera. Fix what's found.
3. Missions and quest log; villager missions; the first story chapter that leads out of the village.
4. A forest area beyond the village with two more enemy kinds and treasure.
5. A cave (interior method) with a guardian and the first boss.
6. Village defence events and repairs.
7. Equipment upgrades and more recipes; shops in the market stall and storehouse.
8. Mountains/ruins area; second boss; weather; location music.
9. Release preparation (AdMob, release signing, store listing) and a wider phone test.

## 5. Milestone 1: the first playable milestone

Goal: from a new game, a player can walk into homes and use them, sees a fuller village, gets a sword and
shield, and wins (or loses and retries) a real fight that pays off.

- Enter and leave all five founders' homes and your own house (and cottages); furnished, distinct rooms; sit at
  tables; sleep in your own bed; cook stew at your hearth; save and load indoors safely.
- The village: flower planters and herb beds at the homes, a market corner at the meeting circle; trees between
  the camera and the player are hidden while they block the view.
- Combat: forge a sword and shield at the workshop; thornlings live in the west woods; attack, block, dodge,
  eat stew to heal; thornlings notice you, wind up and lunge, take hits, and are defeated with rewards;
  clearing the woods is a mission with a reward; they come back after a couple of days; being knocked out
  wakes you at home with nothing lost.
- Tests for all of it in CI.

Status: milestone 1 is implemented and covered by `tests/adventure_test.gd` (48 checks, in CI). It has not been
tried on a real phone yet; that is step 2 of the order above.
