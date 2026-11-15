# Living Village Expansion: plan from the code as it stands

Written after inspecting the repository (Godot 4.3, Mobile renderer, GDScript).

## What already exists (and is reused, not replaced)

| Area | Where | What works today |
| --- | --- | --- |
| Building | `gameplay/build_mode.gd`, `structure_catalog.gd`, `placed_structure.gd`, `structure_manager.gd` | Pick a structure in the Build menu, a green/red preview follows you, rotate in 90° steps, place, then tap Build at the site (villagers can help). Move and remove existing structures. One house size. |
| Homes outside | `world/building_factory.gd` (`_build_house`), `world/kit_cottage.gd` | Founders' houses (one 6×4.4 m shape, per-owner colours). The kit cottages on the south street (real walk-in houses, no loading). |
| Interiors | `gameplay/interiors.gd` | Each door builds a room off-world (10×8 m, one room) with furniture baked into one mesh; sleep in your bed, cook stew, sit at tables in others' homes, read, open the chest (just shows stores). Rooms aren't saved. |
| Homes for people | `population/population.gd` (`homes`, `assign_home`, `home_owners`) | Founders' houses and player-built cottages hold residents; newcomers are housed automatically. |
| Villager days | `villagers/villager.gd`, `life_brain.gd` (stage 4) | Timetables varied daily, walk the waypoint graph, enter homes to sleep, shelter, visit friends. |
| Friendship | `villagers/villager_mind.gd`, `population/social_life.gd`, `gameplay/player_social.gd`, `village_gifts.gd` | Affection/trust, memories, gifts, villagers befriending each other, gossip. |
| Animals | `animals/*` (stage 2) | Bought pets (dog, small dog, cat) with saved records, follow/stay, pet, feed. |
| Saving | `core/save_service.gd` | One JSON save with sections (game state incl. structures, population, animals...). |

## Stage A (this change): building, interiors, furnishing, saving

- **House sizes** in the existing catalog and Build menu: Small house (the existing `house`), Medium house,
  Large house, Manor. Each is a real structure placed, rotated and built with the existing flow.
- **Designs:** three architectural styles (timber-framed, stone, painted boards) and choices of wall colour,
  roof colour, door colour, window style and floor, picked in a Design panel while placing, saved on the
  structure record, and changeable later ("Redecorate").
- **Exteriors** built from the design and size (wider houses get more windows, the manor two storeys and a
  wing).
- **Interiors with rooms:** small = one room; medium = living room + bedroom; large = living room, kitchen,
  bedroom; manor = hall, living room, dining room, kitchen and two bedrooms. Real walls with doorways and
  colliders, windows, the chosen floor, lights. Built off-world like today's rooms (no extra memory outdoors).
- **Furniture as saved objects** (not baked): beds, chairs, stools, tables, benches, storage chests,
  wardrobes, bookshelves, rugs, lamps, plants, crates, barrels. Bought with materials from a Furniture tab;
  placed with a preview (valid only inside rooms, not through walls or other furniture); moved, rotated and
  put away in Arrange mode; small items are carried in your hands. Positions saved per house and outdoors.
- **Furniture you can use:** beds (sleep, in your own home), chairs/stools/benches (sit), chests and
  wardrobes (real storage: put resources in, take them out; saved), bookshelves (read), lamps (on/off).
- **Upgrades:** a finished house can be expanded to the next size (pay the difference, build the extra
  stages); its design and furniture stay (anything a new wall would cut through is moved to free floor).
- Existing saves: a house built before this gets the small-house design and its old furniture as movable
  pieces.

## Stage B: houses for villagers

Give a finished house to a villager (from the house's door): it becomes their `home` in Population (one
household per house unless it's a shared family home), their timetable's "home" entries point there, they
walk over, enter, and sleep in its bed. Saved with the population. Reuses `Population.assign_home`/`_move_in`
and the villagers' existing enter/sleep code.

## Stage C: friendships and visits

Build on `VillagerMind` opinions and memories: spending time together (sitting, walking with you), invites to
visit your home (they come at the agreed hour and use your furniture), gift preferences by personality, and
villagers visiting each other's homes (stage 4 already plans visits; Stage C makes the visit happen inside).

## Stage D: pets

Extend `AnimalManager`: adopt from the Shop with a name you choose, feed/play/pet raising a bond, dog vs cat
behaviours, pet beds as furniture, following you indoors.

## Limits to keep in mind

- One storey inside, even in the manor (stairs and upper floors are a bigger change).
- Furniture is the game's own low-poly style built in code (no new model files, so the APK barely grows).
