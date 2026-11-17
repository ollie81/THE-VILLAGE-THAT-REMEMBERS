class_name VillageLayout
extends RefCounted
## Single source of truth for where everything in the village is.
## Buildings, walking paths, activity spots, the river and the bridge are all
## described here so the terrain, decoration, navigation and villager AI agree.
##
## Coordinates: +X east, +Z south, Y up. The meeting circle is at the origin.

const WORLD_HALF_SIZE := 200.0
const PLAYABLE_HALF_SIZE := 175.0
## The original village square: its terrain never changes, so saves and
## buildings keep their ground. The world grows around it.
const CORE_HALF_SIZE := 80.0

# --- The wider world (outside the core) ---
## A lake in the western forest, for swimming.
const LAKE_CENTER := Vector3(-128.0, 0.0, 18.0)
const LAKE_RADIUS := 20.0
## A pond by the south street.
const POND_CENTER := Vector3(-34.0, 0.0, 122.0)
const POND_RADIUS := 8.5
## Farmland to the north and a second street of homes to the south.
const FARMLAND := Rect2(-95.0, -170.0, 110.0, 70.0)
const SOUTH_STREET := Rect2(-70.0, 98.0, 95.0, 52.0)
## Mountains rise beyond this distance from the centre (square measure).
const MOUNTAINS_FROM := 142.0

const PLAZA_RADIUS := 7.5
const PLAZA_RING_RADIUS := 6.2
## The plaza floor's top above its platform base, and the log seats' top
## above the floor (see BuildingFactory._build_plaza).
const PLAZA_FLOOR_TOP := 0.04
const PLAZA_SEAT_HEIGHT := 0.67

const RIVER_BASE_X := 32.0
const RIVER_HALF_WIDTH := 3.6
const RIVER_WALL_OFFSET := 5.2
const RIVER_BED_HEIGHT := -2.0
const WATER_LEVEL := -0.7

const BRIDGE_Z := 0.0
const BRIDGE_HALF_LENGTH := 7.0
const BRIDGE_HALF_WIDTH := 1.4
const BRIDGE_ARCH := 0.7

const HOUSE_RADIUS := 17.0

## Order matches the five founding villagers.
const HOUSE_OWNERS: Array[String] = ["mara", "elias", "nia", "tomas", "sera"]

const LOCATION_LABELS := {
	"plaza": "the meeting circle",
	"farm": "the farm",
	"garden": "the herb garden",
	"workshop": "the workshop",
	"storage": "the storehouse",
	"build_site": "the new house site",
	"forest_edge": "the forest edge",
	"riverbank": "the riverbank",
	"bridge": "the bridge",
	"plaza_seats": "the meeting circle",
	"woodlot": "the woodlot",
	"quarry": "the quarry",
	"camp": "the travellers' camp",
	"home_mara": "Mara's house",
	"home_elias": "Elias's house",
	"home_nia": "Nia's house",
	"home_tomas": "Tomas's house",
	"home_sera": "Sera's house",
	"lake_shore": "the forest lake",
	"farmland": "the farmland",
	"windmill": "the windmill",
	"ruins": "the old ruins",
	"watchtower": "the watchtower",
	"pond": "the pond",
	"pasture": "the pasture",
	"sheepfold": "the sheepfold",
	"sty": "the pig sty",
	"paddock": "the paddock",
	"market": "the market",
}

## Which side of each farm-animal home villagers come to (towards the road).
const ANIMAL_HOME_SIDE := {
	"pasture": Vector3(0, 0, 1), "paddock": Vector3(1, 0, 0), "sheepfold": Vector3(1, 0, 0), "sty": Vector3(1, 0, 0),
}

const DEFAULT_WANDER_LOCATIONS: Array[String] = [
	"plaza", "farm", "garden", "workshop", "storage", "riverbank", "bridge",
]

## Where the travellers' camp stands, east of the river.
const CAMP_TENTS := 10

static var _nav_nodes: Dictionary = {}
## Locations added while the game runs (homes in player-built cottages).
static var _dynamic_labels: Dictionary = {}
static var _locations: Dictionary = {}
static var _buildings: Array[Dictionary] = []


# --- River and bridge ---------------------------------------------------------------

static func river_center_x(z: float) -> float:
	return RIVER_BASE_X + 4.0 * sin(z * 0.045) + 1.5 * sin(z * 0.11 + 1.3)


## How deep the water is at (x, z): 0 on dry land. The river, the lake and
## the pond all share the same water level.
static func water_depth(x: float, z: float) -> float:
	if not is_water_area(x, z):
		return 0.0
	return maxf(WATER_LEVEL - TerrainGenerator.get_height(x, z), 0.0)


## True inside the river, lake or pond (plus `margin` metres of shore).
static func is_water_area(x: float, z: float, margin: float = 0.0) -> bool:
	if absf(x - river_center_x(z)) < RIVER_HALF_WIDTH + 1.6 + margin:
		return true
	if Vector2(x - LAKE_CENTER.x, z - LAKE_CENTER.z).length() < LAKE_RADIUS + margin:
		return true
	return Vector2(x - POND_CENTER.x, z - POND_CENTER.z).length() < POND_RADIUS + margin


static func bridge_x_range() -> Vector2:
	var center := river_center_x(BRIDGE_Z)
	return Vector2(center - BRIDGE_HALF_LENGTH, center + BRIDGE_HALF_LENGTH)


## Height of the arched bridge deck surface at `x` (only valid within the span).
static func bridge_deck_height(x: float) -> float:
	var span := bridge_x_range()
	var t := clampf((x - span.x) / (span.y - span.x), 0.0, 1.0)
	var west := TerrainGenerator.get_height(span.x, BRIDGE_Z)
	var east := TerrainGenerator.get_height(span.y, BRIDGE_Z)
	return lerpf(west, east, t) + BRIDGE_ARCH * sin(PI * t) + 0.05


static func is_on_bridge(x: float, z: float) -> bool:
	var span := bridge_x_range()
	return absf(z - BRIDGE_Z) <= BRIDGE_HALF_WIDTH and x >= span.x and x <= span.y


## Ground height including walkable structures. Used by villagers, who move
## along paths without physics, and by decoration placement.
static func get_walk_height(x: float, z: float) -> float:
	var room_floor := Interiors.floor_at(x, z)
	if not is_nan(room_floor):
		return room_floor
	var cottage_floor := KitCottage.floor_at(x, z)
	if not is_nan(cottage_floor):
		return cottage_floor
	var ground := TerrainGenerator.get_height(x, z)
	if is_on_bridge(x, z):
		return maxf(ground, bridge_deck_height(x))
	# The meeting circle is a stone floor raised level over the slope.
	if x * x + z * z < PLAZA_RADIUS * PLAZA_RADIUS:
		return maxf(ground, plaza_floor_height())
	return ground


static var _plaza_floor: float = NAN

## Height of the meeting circle's stone floor (the platform is built level
## with the highest ground under it; see BuildingFactory._build_plaza).
static func plaza_floor_height() -> float:
	if is_nan(_plaza_floor):
		_plaza_floor = BuildingFactory._base_height(Vector3.ZERO, Vector2(PLAZA_RADIUS * 2.0, PLAZA_RADIUS * 2.0), 0.0) + PLAZA_FLOOR_TOP
	return _plaza_floor


static func ground_point(x: float, z: float) -> Vector3:
	return Vector3(x, get_walk_height(x, z), z)


## Why something of `radius` can't stand at (x, z), or "" if the ground is
## free: inside the world, away from water, paths, the meeting circle and the
## village's buildings. `path_margin` is the clearance kept from dirt paths.
static func blocking_reason(x: float, z: float, radius: float, path_margin: float = 1.5) -> String:
	if absf(x) > PLAYABLE_HALF_SIZE - radius - 2.0 or absf(z) > PLAYABLE_HALF_SIZE - radius - 2.0:
		return "Too close to the edge of the world"
	if absf(x - river_center_x(z)) < RIVER_WALL_OFFSET + radius + 0.5:
		return "Too close to the river"
	if is_water_area(x, z, radius + 1.0):
		return "Too close to the water"
	if WorldExpansion.reserves(x, z, radius):
		return "There's already something here"
	if maxf(absf(x), absf(z)) > MOUNTAINS_FROM - radius:
		return "Too steep up in the hills"
	if Vector2(x, z).length() < PLAZA_RADIUS + radius + 1.0:
		return "That's the meeting circle"
	if TerrainGenerator.distance_to_paths(x, z) < radius * 0.7 + path_margin:
		return "That would block a path"
	for building in get_buildings():
		var center: Vector3 = building["position"]
		var footprint: Vector2 = building["footprint"]
		if Vector2(x - center.x, z - center.z).length() < footprint.length() * 0.5 + radius + 0.5:
			return "Too close to %s" % String(LOCATION_LABELS.get(building["type"], "a building")).trim_prefix("the ")
	for node in get_nav_nodes().values():
		var p: Vector3 = node
		if Vector2(x - p.x, z - p.z).length() < radius + 1.0:
			return "That would block a path"
	if KitCottage.reserves(x, z, radius):
		return "Too close to the cottage"
	return ""


# --- Buildings ----------------------------------------------------------------------

## Each entry: { id, type, position (Vector3, y = 0), yaw, footprint (Vector2), owner }.
## Front doors face local +Z, which `yaw` turns toward the meeting circle.
static func get_buildings() -> Array[Dictionary]:
	if _buildings.is_empty():
		_build_tables()
	return _buildings


static func get_building(id: String) -> Dictionary:
	for building in get_buildings():
		if building["id"] == id:
			return building
	return {}


# --- Navigation graph ---------------------------------------------------------------

## Waypoints villagers walk between: id -> Vector3 (y = 0).
static func get_nav_nodes() -> Dictionary:
	if _nav_nodes.is_empty():
		_build_tables()
	return _nav_nodes


## Pairs of waypoint ids. These are also painted onto the terrain as dirt paths.
static func get_nav_edges() -> Array:
	var edges: Array = []
	for i in 8:
		edges.append(["plaza_%d" % i, "plaza_%d" % ((i + 1) % 8)])
	edges.append_array([
		["door_mara", "plaza_5"],
		["door_elias", "plaza_5"],
		["door_nia", "plaza_6"],
		["door_tomas", "plaza_7"],
		["door_sera", "plaza_7"],
		["storage_door", "plaza_4"],
		["build_site_front", "plaza_4"],
		["workshop_front", "plaza_3"],
		["garden_gate", "plaza_2"],
		["garden_gate", "garden_inner"],
		["farm_gate", "plaza_1"],
		["farm_gate", "farm_inner"],
		["bridge_west", "plaza_0"],
		["bridge_west", "bridge_east"],
		["bridge_west", "riverbank"],
		["bridge_east", "forest_edge"],
		# Roads out to the wider world.
		["plaza_4", "build_site_front"],
		["build_site_front", "west_road"],
		["west_road", "north_road"],
		["north_road", "farm_road"],
		["farm_road", "farmland_gate"],
		["farmland_gate", "windmill"],
		["west_road", "forest_road"],
		["forest_road", "lake_shore"],
		["forest_road", "ruins"],
		["workshop_front", "south_road"],
		["south_road", "south_street_west"],
		["south_street_west", "south_street_east"],
		["south_street_west", "pond"],
		["forest_edge", "wilds_road"],
		["wilds_road", "watchtower"],
		# Paths round the farm animals.
		["farmland_gate", "pasture"],
		["pasture", "paddock"],
		["paddock", "sheepfold"],
		["farm_road", "sty"],
	])
	return edges


## Activity locations: id -> { "spots": Array[Vector3], "label": String }.
static func get_locations() -> Dictionary:
	if _locations.is_empty():
		_build_tables()
	return _locations


static func get_location_label(id: String) -> String:
	if _dynamic_labels.has(id):
		return String(_dynamic_labels[id])
	return LOCATION_LABELS.get(id, id.replace("_", " "))


## Adds (or replaces) a location at runtime, e.g. the home inside a cottage
## the player built.
static func register_location(id: String, spots: Array, looks: Array, inside: bool, label: String) -> void:
	get_locations()[id] = {"spots": spots, "looks": looks, "inside": inside}
	_dynamic_labels[id] = label


static func unregister_location(id: String) -> void:
	get_locations().erase(id)
	_dynamic_labels.erase(id)


## Places to sit on the meeting-circle logs: { position, yaw (facing the
## fire), height (seat surface above the ground) }. Two per log.
static func plaza_seats() -> Array:
	var seats: Array = []
	for i in 4:
		var angle := deg_to_rad(22.5 + i * 90.0)
		var centre := Vector3(cos(angle) * 4.6, 0, sin(angle) * 4.6)
		var along := Basis(Vector3.UP, atan2(centre.x, centre.z)) * Vector3.RIGHT
		for side: float in [-0.6, 0.6]:
			var at := centre + along * side
			seats.append({"position": at, "yaw": atan2(-at.x, -at.z), "height": PLAZA_SEAT_HEIGHT})
	return seats


static func camp_center() -> Vector3:
	var span := bridge_x_range()
	return Vector3(span.y + 9.0, 0.0, -7.0)


# --- Table construction ---------------------------------------------------------

static func _polar(angle_degrees: float, radius: float) -> Vector3:
	var a := deg_to_rad(angle_degrees)
	return Vector3(cos(a) * radius, 0.0, sin(a) * radius)


static func _yaw_facing_origin(position: Vector3) -> float:
	var direction := -position
	return atan2(direction.x, direction.z)


static func _add_building(id: String, type: String, position: Vector3, footprint: Vector2,
		owner: String = "", yaw: float = INF) -> void:
	var facing := _yaw_facing_origin(position) if yaw == INF else yaw
	_buildings.append({
		"id": id, "type": type, "position": position, "yaw": facing,
		"footprint": footprint, "owner": owner,
	})


static func _build_tables() -> void:
	_buildings.clear()
	_nav_nodes.clear()
	_locations.clear()

	# Meeting-circle ring waypoints (0 = east, counting clockwise seen from above).
	for i in 8:
		_nav_nodes["plaza_%d" % i] = _polar(i * 45.0, PLAZA_RING_RADIUS)

	# Five homes on an arc north of the meeting circle.
	var house_angles: Array[float] = [210.0, 240.0, 270.0, 300.0, 330.0]
	for i in HOUSE_OWNERS.size():
		var owner := HOUSE_OWNERS[i]
		var position := _polar(house_angles[i], HOUSE_RADIUS)
		_add_building("house_" + owner, "house", position, Vector2(6.2, 4.8), owner)
		var door := _polar(house_angles[i], HOUSE_RADIUS - 3.4)
		_nav_nodes["door_" + owner] = door
		_locations["home_" + owner] = {"spots": [door], "inside": true}

	var storage_pos := _polar(165.0, 19.0)
	_add_building("storage", "storage", storage_pos, Vector2(7.4, 5.8))
	_nav_nodes["storage_door"] = _polar(165.0, 15.3)

	var workshop_pos := _polar(125.0, 20.0)
	_add_building("workshop", "workshop", workshop_pos, Vector2(7.0, 5.0))
	_nav_nodes["workshop_front"] = _polar(125.0, 15.8)

	_add_building("garden", "garden", Vector3(0.0, 0.0, 17.0), Vector2(9.0, 7.0), "", 0.0)
	_nav_nodes["garden_gate"] = Vector3(0.0, 0.0, 12.6)

	_add_building("farm", "farm", Vector3(17.0, 0.0, 16.0), Vector2(14.0, 11.0), "", 0.0)
	_nav_nodes["farm_gate"] = Vector3(12.0, 0.0, 9.3)

	var build_site_pos := _polar(190.0, 27.0)
	_add_building("build_site", "build_site", build_site_pos, Vector2(6.0, 5.0))
	_nav_nodes["build_site_front"] = _polar(190.0, 23.0)

	_add_building("plaza", "plaza", Vector3.ZERO, Vector2(PLAZA_RADIUS * 2.0, PLAZA_RADIUS * 2.0), "", 0.0)
	_add_building("memory_oak", "memory_oak", Vector3(10.3, 0.0, 3.8), Vector2(2.0, 2.0), "", 0.6)

	var span := bridge_x_range()
	_nav_nodes["bridge_west"] = Vector3(span.x - 0.6, 0.0, BRIDGE_Z)
	_nav_nodes["bridge_east"] = Vector3(span.y + 0.6, 0.0, BRIDGE_Z)
	_nav_nodes["riverbank"] = Vector3(river_center_x(-9.0) - 6.6, 0.0, -9.0)
	_nav_nodes["forest_edge"] = Vector3(span.y + 5.5, 0.0, 3.0)

	# Activity spots. Villagers walk the waypoint graph to the waypoint nearest
	# a spot, step onto it, then face its "look" target while they work.
	var plaza_spots: Array = []
	var plaza_looks: Array = []
	for i in 8:
		plaza_spots.append(_polar(i * 45.0, 3.0))
		plaza_looks.append(Vector3.ZERO)
	_locations["plaza"] = {"spots": plaza_spots, "looks": plaza_looks}
	# Sitting on the logs around the fire (villagers chatting in the evening).
	var seat_spots: Array = []
	var seat_looks: Array = []
	for seat: Dictionary in plaza_seats():
		seat_spots.append(seat["position"])
		seat_looks.append(Vector3.ZERO)
	_locations["plaza_seats"] = {"spots": seat_spots, "looks": seat_looks, "seat_height": PLAZA_SEAT_HEIGHT}

	# The farm and garden are fenced, so they get an interior waypoint.
	_nav_nodes["farm_inner"] = Vector3(12.0, 0.0, 11.4)
	var farm_spots: Array = [
		Vector3(13.5, 0, 12.5), Vector3(16.0, 0, 14.0), Vector3(19.5, 0, 13.0),
		Vector3(22.0, 0, 16.5), Vector3(14.5, 0, 18.5), Vector3(18.5, 0, 19.5),
	]
	var farm_looks: Array = []
	for spot in farm_spots:
		farm_looks.append(spot + Vector3(1.0, 0, 0))
	_locations["farm"] = {"spots": farm_spots, "looks": farm_looks}

	_nav_nodes["garden_inner"] = Vector3(0.0, 0.0, 17.1)
	_locations["garden"] = {
		"spots": [Vector3(-2.4, 0, 17.1), Vector3(2.4, 0, 17.1), Vector3(0.0, 0, 15.6), Vector3(0.0, 0, 18.6), Vector3(0.0, 0, 19.9)],
		"looks": [Vector3(-2.4, 0, 15.6), Vector3(2.4, 0, 18.6), Vector3(-2.4, 0, 15.6), Vector3(2.4, 0, 18.6), Vector3(-2.4, 0, 18.6)],
	}

	_locations["workshop"] = _local_location(get_building("workshop"), [
		[Vector3(1.0, 0, -0.25), Vector3(1.0, 0, -1.2)],
		[Vector3(-1.4, 0, 0.55), Vector3(-1.4, 0, -0.4)],
		[Vector3(-1.5, 0, 2.6), Vector3(-2.2, 0, 2.0)],
	])
	_locations["storage"] = _local_location(get_building("storage"), [
		[Vector3(-1.3, 0, 3.6), Vector3(-2.6, 0, 4.1)],
		[Vector3(1.6, 0, 3.8), Vector3(2.8, 0, 3.9)],
		[Vector3(0.0, 0, 3.4), Vector3(0.0, 0, 2.7)],
	])
	_locations["build_site"] = _local_location(get_building("build_site"), [
		[Vector3(1.0, 0, 4.4), Vector3(1.0, 0, 3.6)],
		[Vector3(3.6, 0, 2.8), Vector3(3.9, 0, 0.5)],
		[Vector3(-1.2, 0, 3.0), Vector3(-1.2, 0, 0.0)],
	])

	var forest: Vector3 = _nav_nodes["forest_edge"]
	_locations["forest_edge"] = {"spots": [
		forest + Vector3(2.0, 0, -2.5), forest + Vector3(3.5, 0, 1.5),
		forest + Vector3(0.5, 0, 3.0), forest + Vector3(-0.5, 0, -1.0),
	]}
	var bank: Vector3 = _nav_nodes["riverbank"]
	var bank_spots: Array = [bank + Vector3(0.5, 0, -1.5), bank + Vector3(0.6, 0, 1.2), bank + Vector3(-0.4, 0, -3.5)]
	var bank_looks: Array = []
	for spot in bank_spots:
		bank_looks.append(spot + Vector3(3.0, 0, 0))
	_locations["riverbank"] = {"spots": bank_spots, "looks": bank_looks}
	# Work places for the new trades, beside the forest and the rocks the
	# player gathers from.
	var woodlot_spots: Array = []
	var woodlot_looks: Array = []
	for z: float in [-12.0, -6.0, 0.0, 6.0, 12.0, 18.0]:
		woodlot_spots.append(Vector3(-31.2, 0, z))
		woodlot_looks.append(Vector3(-36.0, 0, z + 1.0))
	_locations["woodlot"] = {"spots": woodlot_spots, "looks": woodlot_looks}
	var quarry_spots: Array = []
	var quarry_looks: Array = []
	for x: float in [-9.0, -4.5, 0.0, 4.5, 9.0]:
		quarry_spots.append(Vector3(x, 0, -27.3))
		quarry_looks.append(Vector3(x * 1.1, 0, -32.0))
	_locations["quarry"] = {"spots": quarry_spots, "looks": quarry_looks}

	# The travellers' camp: tents in a ring around a fire, east of the river.
	# Newcomers without a home sleep here.
	var camp := camp_center()
	_add_building("camp", "camp", camp, Vector2(10.0, 10.0), "", 0.0)
	var camp_spots: Array = []
	var camp_looks: Array = []
	for i in CAMP_TENTS:
		var a := TAU * float(i) / CAMP_TENTS
		camp_spots.append(camp + Vector3(cos(a), 0, sin(a)) * 2.5)
		camp_looks.append(camp)
	_locations["camp"] = {"spots": camp_spots, "looks": camp_looks, "inside": true}

	# Roads and places in the wider world.
	_nav_nodes["west_road"] = Vector3(-46.0, 0.0, -2.0)
	_nav_nodes["north_road"] = Vector3(-58.0, 0.0, -58.0)
	_nav_nodes["farm_road"] = Vector3(-50.0, 0.0, -92.0)
	_nav_nodes["farmland_gate"] = Vector3(-42.0, 0.0, -104.0)
	_nav_nodes["windmill"] = Vector3(-22.0, 0.0, -128.0)
	_nav_nodes["forest_road"] = Vector3(-92.0, 0.0, 4.0)
	_nav_nodes["lake_shore"] = LAKE_CENTER + Vector3(LAKE_RADIUS + 4.0, 0.0, -2.0)
	_nav_nodes["ruins"] = Vector3(-140.0, 0.0, -52.0)
	_nav_nodes["south_road"] = Vector3(-16.0, 0.0, 52.0)
	_nav_nodes["south_street_west"] = Vector3(-20.0, 0.0, 106.0)
	_nav_nodes["south_street_east"] = Vector3(14.0, 0.0, 108.0)
	_nav_nodes["pond"] = POND_CENTER + Vector3(POND_RADIUS + 3.0, 0.0, -4.0)
	_nav_nodes["wilds_road"] = Vector3(88.0, 0.0, 6.0)
	_nav_nodes["watchtower"] = Vector3(118.0, 0.0, -18.0)
	# Where villagers stand to tend the village's animals (see AnimalManager):
	# at the edge of each home area, looking in.
	for home in ["pasture", "paddock", "sheepfold", "sty"]:
		var centre: Vector3 = AnimalManager.VILLAGE_HOMES[home][0]
		var radius: float = AnimalManager.VILLAGE_HOMES[home][1]
		var toward := ANIMAL_HOME_SIDE[home] as Vector3
		_nav_nodes[home] = centre + toward * (radius + 3.0)
		var care_spots: Array = []
		var care_looks: Array = []
		for i in 3:
			var side := toward.rotated(Vector3.UP, (i - 1) * 0.45)
			care_spots.append(centre + side * (radius + 1.0))
			care_looks.append(centre)
		_locations[home] = {"spots": care_spots, "looks": care_looks}
	# Places to walk out to: by the windmill, round the pond, along the south
	# street.
	_locations["windmill"] = _ring_location(_nav_nodes["windmill"], WorldExpansion.WINDMILL, 3, 2.5)
	_locations["pond"] = _ring_location(_nav_nodes["pond"], POND_CENTER, 3, 2.0)
	_locations["south_street_east"] = _ring_location(_nav_nodes["south_street_east"], _nav_nodes["south_street_east"] + Vector3(0, 0, -6), 3, 2.0)
	var lake_spots: Array = []
	var lake_looks: Array = []
	for i in 4:
		var a := 0.3 + i * 0.35
		lake_spots.append(LAKE_CENTER + Vector3(cos(a), 0, sin(a)) * (LAKE_RADIUS + 3.0))
		lake_looks.append(LAKE_CENTER)
	_locations["lake_shore"] = {"spots": lake_spots, "looks": lake_looks}
	_locations["farmland"] = {"spots": [Vector3(-36, 0, -112), Vector3(-30, 0, -120), Vector3(-44, 0, -124), Vector3(-26, 0, -112)],
		"looks": [Vector3(-36, 0, -118), Vector3(-30, 0, -126), Vector3(-44, 0, -130), Vector3(-26, 0, -118)]}

	var river_x := river_center_x(BRIDGE_Z)
	_locations["bridge"] = {
		"spots": [Vector3(river_x - 1.0, 0, BRIDGE_Z + 0.7), Vector3(river_x + 1.2, 0, BRIDGE_Z - 0.7)],
		"looks": [Vector3(river_x - 1.0, 0, BRIDGE_Z + 5.0), Vector3(river_x + 1.2, 0, BRIDGE_Z - 5.0)],
	}


## A few spots near `at`, side by side, everyone looking at `look`.
static func _ring_location(at: Vector3, look: Vector3, count: int, spacing: float) -> Dictionary:
	var toward := Vector3(look.x - at.x, 0, look.z - at.z).normalized()
	var side := Vector3(-toward.z, 0, toward.x)
	var spots: Array = []
	var looks: Array = []
	for i in count:
		spots.append(at + side * (i - (count - 1) * 0.5) * spacing)
		looks.append(look)
	return {"spots": spots, "looks": looks}


## Converts [local_spot, local_look] pairs in a building's frame to world space.
static func _local_location(building: Dictionary, pairs: Array) -> Dictionary:
	var origin: Vector3 = building["position"]
	var basis := Basis(Vector3.UP, float(building["yaw"]))
	var spots: Array = []
	var looks: Array = []
	for pair in pairs:
		spots.append(origin + basis * Vector3(pair[0]))
		looks.append(origin + basis * Vector3(pair[1]))
	return {"spots": spots, "looks": looks}
