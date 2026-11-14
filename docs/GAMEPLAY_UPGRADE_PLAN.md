# Major gameplay upgrade: audit and plan

## 1. What exists today (audit)

| Area | What's there | Files |
|---|---|---|
| Player look | A detailed `CharacterAppearance` (skin, hair style and colour, eyes, shirt, trousers, accent, shoes, skirt, apron, hat colours, tunic and sleeve length, accessories), built into a skinned, animated mesh by `HumanoidMeshBuilder`. The player's look is fixed in code and not saved. | `character_appearance.gd`, `humanoid_mesh_builder.gd`, `character_model.gd`, `player_controller.gd`, `appearance_codec.gd` (look ⇄ dictionary) |
| Clothing pieces the mesh builder already draws | Hair: bald, balding, short, long, bun, ponytail, locs, curly, afro, braids. Head: straw hat, wide hat, cap, headband, headwrap, flower, flower crown, glasses, earrings, beards. Body: cloak, backpack, satchel, scarf, apron, suspenders, tool belt, necklace. Skirt/dress via skirt colour + tunic length, sleeves via sleeve length. | `humanoid_mesh_builder.gd` |
| Economy | Wood, stone, food, herbs (`GameState`). No currency. | `game_state.gd` |
| Rewarded ads | Optional, never forced. AdMob through the Poing plugin if installed (it isn't yet: needs your approval and IDs), a simulated ad in debug builds. Rewards fire only after the SDK's "earned" callback, with a daily cap and cooldown. Rewards today are village gifts (caravan, harvest, feast, traveller). | `ad_rewards.gd`, `village_gifts.gd`, `gifts_panel.gd` |
| Homes | Founder houses and built cottages/houses, all one footprint (6.2 × 4.8). Each has one 10 × 8 m interior with kitchen, bedroom (partition), dining and usable bed, hearth, chest, window seat and books. Furniture is fixed; nothing can be placed or moved. | `structure_catalog.gd`, `interiors.gd`, `placed_structure.gd` |
| Danger | Thornlings (3 HP, wander, chase, wind-up lunge, knockback) in the west woods after the first week; sword and shield from the workshop; attack, block, dodge, stew healing; one repeatable clearing mission. No village raids, warnings, bosses or difficulty curve. | `combat/thornwood.gd`, `combat/thornling.gd`, `combat/player_combat.gd` |
| Villagers | Schedules, memories, familiarity, requests, chatter, stories, festivals, population growth. | `villagers/`, `population/`, `gameplay/request_board.gd` |
| Saves | One JSON save (now written safely with a backup), sections per system; `SAVE_VERSION` 1. | `save_service.gd` |

## 2. Plan in stages

Each stage ends with tests, a fresh APK and a report. Existing saves keep working:
new sections start empty, and the player's look defaults to today's traveller.

1. **Village Credits and character customisation** (this stage)
   - One `VillageCredits` balance, saved with the game, with a ledger of reward
     tokens so the same reward can never be paid twice, and a checksum that detects
     edited save files.
   - Earned by play (objectives, villager requests, clearing the woods, chests,
     festivals, the daily gift) and by an optional rewarded ad, paid only after the
     ad SDK confirms the reward.
   - Every price and reward in one file (`economy_config.gd`).
   - **Wardrobe** with a live, turning 3D preview: tops, sleeves, trousers, skirts
     and dresses, shoes, hairstyles, hair colours, hats, accessories, colour
     swatches. Some items free, some bought with credits, some unlocked by play.
     The outfit is put on the real player model (same skeleton, so it animates) and
     saved.
   - **Shop**: building materials, seeds/herbs and food for credits.
2. **Bigger homes and furniture**: small, medium and large houses (different
   footprints and room counts), upgrading an existing house, interiors sized to
   the house with bedroom, kitchen, living room and storage, placeable and movable
   furniture and decorations bought with credits or materials, saved per house.
3. **Village danger**: warning signs before a threat (a horn, villagers talking,
   a sky tint), night raids by thornlings on the village edge a few times a week,
   villagers gathering at the meeting circle, defence missions with rewards,
   enemy types and difficulty that grow with progress, better equipment, a boss in
   a marked adventure area. Nothing destroys your buildings or progress.
4. **Village life connections**: villagers react to raids and help defend,
   comment on your outfit and home, ask for home improvements, and friendship
   unlocks missions.
5. **Polish and performance** on the lowest graphics setting.

## 3. Technical risks

- **Rebuilding the player's mesh** when the outfit changes costs some time on a
  phone (a fraction of a second; meshes are cached per look). The preview waits
  until you stop tapping before rebuilding.
- **Ad verification.** Without a server, "verified" means the AdMob SDK's
  *earned reward* callback on the phone, which is what the game uses now: credits
  are only added after it fires, and each ad's reward token is recorded so it's
  paid once. True server-side verification (AdMob SSV) needs a web server to
  receive Google's callbacks. That is an additional hosted service: **not used
  without your approval.**
- **Save security.** Everything is stored on the phone, so it can't be made
  tamper-proof; the checksum stops casual editing of the save file.
- **Bigger homes and raids** add draw calls; they'll be tested on the Low setting.

## 4. Paid or third-party services

- **None needed for stages 1–5.**
- **AdMob** (free; it pays you) needs the Poing Studios AdMob plugin and your
  AdMob app and rewarded unit IDs. Still waiting for your explicit
  "yes, add the AdMob plugin". Until then debug builds use a simulated ad.
- **Server-side ad verification** would need a hosted server (possibly a free
  tier): only with your approval.
