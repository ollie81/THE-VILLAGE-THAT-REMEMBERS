class_name VillageLayout
extends RefCounted
## Single source of truth for where everything in the village is.
## Buildings, walking paths, activity spots, the river and the bridge are all
## described here so the terrain, decoration, navigation and villager AI agree.
##
## Coordinates: +X east, +Z south, Y up. The meeting circle is at the origin.

const WORLD_HALF_SIZE := 80.0
const PLAYABLE_HALF_SIZE := 62.0

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

	var river_x := river_center_x(BRIDGE_Z)
	_locations["bridge"] = {
		"spots": [Vector3(river_x - 1.0, 0, BRIDGE_Z + 0.7), Vector3(river_x + 1.2, 0, BRIDGE_Z - 0.7)],
		"looks": [Vector3(river_x - 1.0, 0, BRIDGE_Z + 5.0), Vector3(river_x + 1.2, 0, BRIDGE_Z - 5.0)],
	}


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
