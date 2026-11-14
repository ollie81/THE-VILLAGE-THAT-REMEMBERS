extends Node
## Headless test of the visual pilot: the textured ground, the walk-in
## cottage built from real models (rooms, door, walls you can't walk
## through, a floor you stand on, the roof hidden while inside) and the real
## tree models near the village.
## Run:  godot --headless --path . res://tests/pilot_test.tscn

var _failures: int = 0
var _main = null


func _ready() -> void:
	SaveService.enabled = false
	PopulationDirector.auto_arrivals = false
	Guide.rewards = false
	DailyGift.persist = false
	GameState.reset()
	_run.call_deferred()


func _check(condition: bool, description: String) -> void:
	if condition:
		print("  PASS  ", description)
	else:
		_failures += 1
		print("  FAIL  ", description)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _ray_blocked(from: Vector3, to: Vector3) -> bool:
	var space := (_main as Node3D).get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	return not space.intersect_ray(query).is_empty()


func _run() -> void:
	print("== Pilot test ==")
	WorldClock.set_time(10.0)
	WorldClock.set_time_scale(0.0)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _frames(40)
	# Ground.
	var terrain := _main.find_child("TerrainMesh", true, false) as MeshInstance3D
	_check(terrain != null and terrain.mesh.surface_get_material(0) == Materials.ground(), "the ground uses the textured grass, path and cobblestone material")
	_check(_main.find_child("PlazaCobbles", true, false) != null, "the meeting circle is paved with cobblestones")
	# Cottage.
	var cottage := KitCottage.instance
	_check(cottage != null and KitCottage.spot != Vector3.INF, "the cottage was placed in the village")
	if cottage == null:
		_finish()
		return
	var pieces := cottage.find_children("*", "MeshInstance3D", true, false).size()
	_check(pieces > 80, "built from real models (%d mesh pieces)" % pieces)
	for room in ["LivingRoom", "Kitchen", "Bedroom"]:
		_check(cottage.find_child(room, false, false) != null and cottage.find_child(room, false, false).get_child_count() >= 5, "it has a furnished %s" % room)
	_check(VillageLayout.blocking_reason(KitCottage.spot.x, KitCottage.spot.z, 1.0) != "", "nothing else can be built on its plot")
	# Walls block, the doorway doesn't.
	var y := KitCottage.floor_y + 1.0
	var door_out := cottage.to_global(Vector3(KitCottage.DOOR_X, 1.0, KitCottage.DEPTH * 0.5 + 1.5))
	var door_in := cottage.to_global(Vector3(KitCottage.DOOR_X, 1.0, KitCottage.DEPTH * 0.5 - 1.5))
	_check(not _ray_blocked(door_out, door_in), "you can walk in through the open door")
	var wall_out := cottage.to_global(Vector3(-3.0, 1.0, KitCottage.DEPTH * 0.5 + 1.5))
	var wall_in := cottage.to_global(Vector3(-3.0, 1.0, KitCottage.DEPTH * 0.5 - 1.5))
	_check(_ray_blocked(wall_out, wall_in), "but not through the walls")
	cottage.toggle_door()
	for i in 3:
		await get_tree().physics_frame
	_check(not cottage.door_open and _ray_blocked(door_out, door_in), "closing the door shuts the doorway")
	cottage.toggle_door()
	for i in 3:
		await get_tree().physics_frame
	var kitchen_door_a := cottage.to_global(Vector3(-1.0, 1.0, KitCottage.PARTITION_Z + 1.2))
	var kitchen_door_b := cottage.to_global(Vector3(-1.0, 1.0, KitCottage.PARTITION_Z - 1.2))
	_check(not _ray_blocked(kitchen_door_a, kitchen_door_b), "a doorway leads from the living room to the kitchen")
	var bed_a := cottage.to_global(Vector3(1.0, 1.0, KitCottage.PARTITION_Z + 1.2))
	var bed_b := cottage.to_global(Vector3(1.0, 1.0, KitCottage.PARTITION_Z - 1.2))
	_check(not _ray_blocked(bed_a, bed_b), "and another to the bedroom")
	# Standing inside.
	var player: PlayerController = GameManager.player
	var inside := cottage.room_view("living")["player"] as Vector3
	_check(is_equal_approx(VillageLayout.get_walk_height(inside.x, inside.z), KitCottage.floor_y), "the floor counts as ground inside (for sitting, villagers, hens)")
	player.global_position = inside + Vector3(0, 0.3, 0)
	for i in 30:
		await get_tree().physics_frame
	_check(absf(player.global_position.y - KitCottage.floor_y) < 0.25, "the player stands on the floorboards (%.2f vs %.2f)" % [player.global_position.y, KitCottage.floor_y])
	await _frames(3)
	_check(cottage.is_player_inside() and not cottage.roof.visible, "inside, the roof is hidden so the camera can see in")
	var rig: CameraRig = _main.camera_rig
	_check(rig.overhead, "and the camera looks down over the walls")
	# Walk out of the door.
	player.global_position = cottage.room_view("living")["player"] + Vector3(0, 0.2, 0)
	var start := player.global_position
	var target := cottage.door_outside()
	for i in 240:
		var to := target - player.global_position
		to.y = 0.0
		if to.length() < 0.6:
			break
		player.velocity = to.normalized() * 3.0
		player.global_position += to.normalized() * 3.0 / 60.0
		await get_tree().physics_frame
	await _frames(3)
	_check(not cottage.is_player_inside() and cottage.roof.visible and not rig.overhead, "walking out brings the roof and the normal camera back")
	# Furniture you can use.
	var usables := cottage.find_children("*", "UsableObject", true, false).map(func(u): return u.name)
	_check(usables.has("Bed") and usables.has("Hearth") and usables.has("Bookcase") and usables.has("Door") and usables.has("Seat"), "bed, hearth, books, chair and door can be used: %s" % str(usables))
	# Real trees near the village.
	var kit_trees := 0
	for node in _main.find_children("*_kit", "MultiMeshInstance3D", true, false):
		kit_trees += (node as MultiMeshInstance3D).multimesh.instance_count
	_check(kit_trees > 50, "real tree, bush and rock models stand near the village (%d)" % kit_trees)
	var choppable := ResourceSpawner.nodes.filter(func(n): return is_instance_valid(n) and n.kind == &"tree")
	_check(not choppable.is_empty() and choppable[0].find_children("*", "MeshInstance3D", true, false).any(func(m): return m.mesh and m.mesh.get_surface_count() >= 2),
		"the trees you chop are real models too")
	_finish()


func _finish() -> void:
	print("== %s: %d failure(s) ==" % ["PASSED" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(0 if _failures == 0 else 1)
