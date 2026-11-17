class_name VillageNavigation
extends RefCounted
## Lightweight waypoint navigation for villagers. A small AStar3D graph over
## the village paths is far cheaper on mobile than a baked navmesh and makes
## villagers walk on the visible dirt paths.
## Also hands out activity spots so two villagers never stand in one place.

## Distance between rings of overflow places around a busy spot.
const OVERFLOW_STEP := 1.1

var _astar := AStar3D.new()
var _ids: Dictionary = {}
var _claims: Dictionary = {} # "location:index" -> villager id
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()
	var nodes := VillageLayout.get_nav_nodes()
	var next_id := 0
	for key in nodes:
		_ids[key] = next_id
		_astar.add_point(next_id, nodes[key])
		next_id += 1
	for edge in VillageLayout.get_nav_edges():
		_astar.connect_points(_ids[edge[0]], _ids[edge[1]])


## Route from `from` to `to` as flat (y = 0) points: nearest waypoint,
## along the graph, then straight to the destination.
func find_route(from: Vector3, to: Vector3) -> PackedVector3Array:
	var flat_from := Vector3(from.x, 0.0, from.z)
	var flat_to := Vector3(to.x, 0.0, to.z)
	var start := _astar.get_closest_point(flat_from)
	var goal := _astar.get_closest_point(flat_to)
	var route := PackedVector3Array()
	if start == goal and flat_from.distance_to(flat_to) < 3.5:
		route.append(flat_to)
		return route
	route.append_array(_astar.get_point_path(start, goal))
	route.append(flat_to)
	return route


func get_node_position(id: String) -> Vector3:
	return VillageLayout.get_nav_nodes().get(id, Vector3.ZERO)


func has_location(location_id: String) -> bool:
	return VillageLayout.get_locations().has(location_id)


func get_spot_count(location_id: String) -> int:
	var location: Dictionary = VillageLayout.get_locations().get(location_id, {})
	var spots: Array = location.get("spots", [])
	return spots.size()


## A spot's position. Indexes past the authored spots are overflow places
## in rings around them, so a busy location never puts two people on one
## spot (that renders as one body with two faces).
func get_spot(location_id: String, index: int) -> Vector3:
	var location: Dictionary = VillageLayout.get_locations().get(location_id, {})
	var spots: Array = location.get("spots", [])
	if spots.is_empty():
		return Vector3.ZERO
	if index < spots.size():
		return spots[maxi(index, 0)]
	return spots[index % spots.size()] + overflow_offset(index, spots.size())


static func overflow_offset(index: int, base_count: int) -> Vector3:
	var ring := index / base_count
	var angle := float(index) * 2.39996 # golden angle: neighbours spread out
	return Vector3(cos(angle), 0.0, sin(angle)) * (OVERFLOW_STEP * ring)


## Where a villager standing on this spot should face, or null.
func get_spot_look(location_id: String, index: int) -> Variant:
	var location: Dictionary = VillageLayout.get_locations().get(location_id, {})
	var looks: Array = location.get("looks", [])
	if index >= 0 and index < looks.size():
		return looks[index]
	if index >= 0 and not looks.is_empty():
		return looks[index % looks.size()] + overflow_offset(index, looks.size())
	return null


func is_inside_location(location_id: String) -> bool:
	var location: Dictionary = VillageLayout.get_locations().get(location_id, {})
	return bool(location.get("inside", false))


## Reserves a free spot (or a random one if all are taken). Returns its index.
func claim_spot(location_id: String, villager_id: StringName, exclude_index: int = -1) -> int:
	var count := get_spot_count(location_id)
	if count == 0:
		return -1
	var free: Array[int] = []
	for i in count:
		if i == exclude_index:
			continue
		if _is_free(location_id, i, villager_id):
			free.append(i)
	var index := -1
	if not free.is_empty():
		index = free[_rng.randi_range(0, free.size() - 1)]
	else:
		# Everything taken: the first free overflow place.
		index = count
		while not _is_free(location_id, index, villager_id) or index == exclude_index:
			index += 1
	_claims["%s:%d" % [location_id, index]] = villager_id
	return index


func _is_free(location_id: String, index: int, villager_id: StringName) -> bool:
	var key := "%s:%d" % [location_id, index]
	return not _claims.has(key) or _claims[key] == villager_id


func release_spot(location_id: String, index: int, villager_id: StringName) -> void:
	var key := "%s:%d" % [location_id, index]
	if _claims.get(key, &"") == villager_id:
		_claims.erase(key)
