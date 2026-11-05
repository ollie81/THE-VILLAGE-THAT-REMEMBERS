class_name BuildMode
extends Node3D
## Placing new structures: a see-through preview follows the player (green
## where it can go, red where it can't), can be rotated, and is placed or
## cancelled. Placing spends the resources and creates a construction site.

signal started(type: StringName)
signal ended
signal validity_changed(reason: String)

const DISTANCE_AHEAD := 4.5
const GRID := 0.5

static var instance: BuildMode

var active: bool = false
var type: StringName = &""
var reason: String = ""

## "" normally; "move" or "remove" while picking a building to change.
var edit_mode: String = ""
## The structure being moved (hidden while its preview follows the player).
var moving: PlacedStructure = null

signal edit_mode_changed(mode: String)

var _ghost: Node3D
var _turns: int = 0
var _position := Vector3.ZERO
var _valid_material: StandardMaterial3D
var _invalid_material: StandardMaterial3D
## The spot straight ahead last frame, and the free spot found near it (so
## the search only runs when the player has moved to a new grid cell).
var _searched_from := Vector3.INF
var _searched_turns: int = -1
var _found: Vector3 = Vector3.INF

## How far from the spot ahead to look for room when that spot is taken.
const SEARCH_RADIUS := 9.0


func _ready() -> void:
	name = "BuildMode"
	instance = self
	_valid_material = _ghost_material(Color(0.35, 0.95, 0.45, 0.45))
	_invalid_material = _ghost_material(Color(1.0, 0.3, 0.25, 0.45))


func _exit_tree() -> void:
	if instance == self:
		instance = null


static func _ghost_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = false
	return material


func start(structure_type: StringName) -> void:
	cancel()
	if StructureCatalog.info(structure_type).is_empty():
		return
	type = structure_type
	active = true
	_turns = 0
	_searched_from = Vector3.INF
	_ghost = StructureCatalog.create_finished(type)
	_strip_ghost(_ghost)
	add_child(_ghost)
	_update(0.0)
	started.emit(type)


func cancel() -> void:
	if not active:
		return
	active = false
	if moving and is_instance_valid(moving):
		moving.visible = true
	moving = null
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	ended.emit()


func rotate_preview() -> void:
	_turns = (_turns + 1) % 4


func current_yaw() -> float:
	var player = GameManager.player
	var facing: float = player.model.rotation.y if player else 0.0
	# Face back toward the player by default, then in 90 degree steps.
	return snappedf(facing + PI, PI * 0.5) + _turns * PI * 0.5


## Places the structure. Returns "" on success or why it can't be placed.
func confirm() -> String:
	if not active:
		return "Nothing to place"
	_update(0.0)
	if reason != "":
		GameManager.notify(reason)
		return reason
	var info := StructureCatalog.info(type)
	if moving and is_instance_valid(moving):
		moving.move_to(_position, current_yaw())
		moving.visible = true
		moving = null
		GameManager.notify("%s moved." % info["name"])
		cancel()
		return ""
	GameState.spend(info["cost"])
	GameState.add_structure(type, _position, current_yaw())
	GameManager.notify("%s placed. Work on it to finish building." % info["name"])
	cancel()
	return ""


# --- Moving and removing ---------------------------------------------------------------

## Starts picking a building to move ("move") or remove ("remove"); "" stops.
func set_edit_mode(mode: String) -> void:
	edit_mode = mode
	edit_mode_changed.emit(mode)


## Picks up a structure: its preview follows the player until placed again.
func start_move(structure: PlacedStructure) -> void:
	set_edit_mode("")
	start(structure.get_type())
	moving = structure
	structure.visible = false
	_update(0.0)


## Takes a structure down and gives back half of what it cost.
func remove(structure: PlacedStructure) -> Dictionary:
	set_edit_mode("")
	var info := structure.get_info()
	var refund := {}
	for resource in info["cost"]:
		refund[resource] = int(info["cost"][resource]) / 2
		GameState.add(resource, int(refund[resource]))
	structure.take_down()
	GameManager.notify("%s removed. You got back %s." % [info["name"], GameState.cost_text(refund)])
	return refund


func _process(delta: float) -> void:
	if active:
		_update(delta)


func _update(_delta: float) -> void:
	var player = GameManager.player
	if player == null or _ghost == null:
		return
	var ahead: Vector3 = player.global_position + player.get_facing() * (DISTANCE_AHEAD + StructureCatalog.radius(type) * 0.6)
	ahead.x = snappedf(ahead.x, GRID)
	ahead.z = snappedf(ahead.z, GRID)
	var yaw := current_yaw()
	# Ahead is taken (trees, steep ground, a path)? Use the nearest free spot,
	# so the preview turns green somewhere close instead of staying red.
	if ahead != _searched_from or _turns != _searched_turns:
		_searched_from = ahead
		_searched_turns = _turns
		_found = ahead if placement_reason(type, ahead, yaw) == "" else nearest_free_spot(type, ahead, yaw, player.global_position)
	if _found != Vector3.INF:
		ahead = _found
	_position = Vector3(ahead.x, _ground_height(ahead, yaw), ahead.z)
	_ghost.global_position = _position
	_ghost.rotation.y = current_yaw()
	var new_reason := placement_reason(type, _position, current_yaw())
	if new_reason != reason or _delta == 0.0:
		reason = new_reason
		_tint(_ghost, _valid_material if reason == "" else _invalid_material)
		validity_changed.emit(reason)


## The closest place near `around` where `structure_type` fits, not on top
## of the player; Vector3.INF if there's none (or it can't be afforded).
static func nearest_free_spot(structure_type: StringName, around: Vector3, yaw: float, player_at: Vector3) -> Vector3:
	var info := StructureCatalog.info(structure_type)
	var moving_now: bool = instance != null and instance.moving != null
	if not moving_now and GameState.missing_text(info["cost"]) != "":
		return Vector3.INF
	var keep_clear := StructureCatalog.radius(structure_type) + 0.8
	var ring := 1.0
	while ring <= SEARCH_RADIUS:
		var best := Vector3.INF
		var best_distance := INF
		var steps := int(ceil(TAU * ring / 1.0))
		for i in steps:
			var a := TAU * i / steps
			var spot := around + Vector3(cos(a) * ring, 0.0, sin(a) * ring)
			spot.x = snappedf(spot.x, GRID)
			spot.z = snappedf(spot.z, GRID)
			if Vector2(spot.x - player_at.x, spot.z - player_at.z).length() < keep_clear:
				continue
			if placement_reason(structure_type, spot, yaw) != "":
				continue
			var d := Vector2(spot.x - player_at.x, spot.z - player_at.z).length()
			if d < best_distance:
				best_distance = d
				best = spot
		if best != Vector3.INF:
			return best
		ring += 1.0
	return Vector3.INF


## Why `structure_type` can't go at `at`, or "" if it can.
static func placement_reason(structure_type: StringName, at: Vector3, yaw: float) -> String:
	var info := StructureCatalog.info(structure_type)
	var moving_now: bool = instance != null and instance.moving != null
	var missing := "" if moving_now else GameState.missing_text(info["cost"])
	if missing != "":
		return missing
	var radius := StructureCatalog.radius(structure_type)
	var blocked := VillageLayout.blocking_reason(at.x, at.z, radius, 0.6)
	if blocked != "":
		return blocked
	if instance and instance.get_tree():
		for structure in instance.get_tree().get_nodes_in_group("placed_structures"):
			if structure == instance.moving:
				continue
			var other: float = StructureCatalog.radius(structure.get_type())
			if Vector2(at.x - structure.global_position.x, at.z - structure.global_position.z).length() < radius + other + 0.3:
				return "Too close to your %s" % String(structure.get_info()["name"]).to_lower()
	for node in ResourceSpawner.nodes:
		if is_instance_valid(node) and Vector2(at.x - node.global_position.x, at.z - node.global_position.z).length() < radius + 0.8:
			return "Something is in the way"
	var footprint: Vector2 = info["footprint"]
	var basis := Basis(Vector3.UP, yaw)
	var lowest := INF
	var highest := -INF
	for corner in [Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(-0.5, 0, 0.5), Vector3(0.5, 0, 0.5)]:
		var offset: Vector3 = basis * (corner * Vector3(footprint.x, 0, footprint.y))
		var h := TerrainGenerator.get_height(at.x + offset.x, at.z + offset.z)
		lowest = minf(lowest, h)
		highest = maxf(highest, h)
	if highest - lowest > 0.9:
		return "The ground is too steep here"
	return ""


static func _ground_height(at: Vector3, yaw: float) -> float:
	return TerrainGenerator.get_height(at.x, at.z)


static func _strip_ghost(node: Node) -> void:
	for child in node.get_children():
		if child is CollisionObject3D or child is Light3D:
			child.queue_free()
		else:
			_strip_ghost(child)


static func _tint(node: Node, material: Material) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).material_override = material
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_tint(child, material)


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event.is_action_pressed("menu"):
		cancel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact"):
		confirm()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("rotate_camera_right"):
		rotate_preview()
		get_viewport().set_input_as_handled()
