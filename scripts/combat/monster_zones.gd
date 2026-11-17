class_name MonsterZones
extends RefCounted
## How dangerous each part of the world is:
## - SAFE: the village, the farmland and the south street. No monster sets
##   foot here.
## - FOREST: the woods and the lake, the ruins, the outskirts. Slimes and
##   bats by day; skeletons come out at night.
## - WILDS: the rocky east beyond the watchtower road, and the mountain edge.
##   Wolves and bats by day, skeletons at night, and the dragon's lair.

const SAFE := 0
const FOREST := 1
const WILDS := 2

const NAMES := ["the village", "the forest", "the wilds"]
## The safe square round the village (a little bigger than the old map).
const SAFE_HALF := 86.0
const SAFE_MARGIN := 5.0
const WILDS_EAST_FROM := 95.0
const WILDS_EDGE_FROM := 150.0


static func zone_at(x: float, z: float) -> int:
	if absf(x) <= SAFE_HALF and absf(z) <= SAFE_HALF:
		return SAFE
	if VillageLayout.FARMLAND.grow(SAFE_MARGIN).has_point(Vector2(x, z)) or VillageLayout.SOUTH_STREET.grow(SAFE_MARGIN).has_point(Vector2(x, z)):
		return SAFE
	if x > WILDS_EAST_FROM or absf(x) > WILDS_EDGE_FROM or absf(z) > WILDS_EDGE_FROM:
		return WILDS
	return FOREST
