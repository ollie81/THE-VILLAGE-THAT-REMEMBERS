extends Node
## Developer tool (Living Village stage A): the four house sizes in different
## styles, their rooms with furniture, the Furnish menu, placing and carrying
## furniture, and a storage chest. --outside / --inside for half the shots.
var _out := "user://screenshots"
var _main
var _houses: Array = []
func _ready() -> void:
	SaveService.enabled = false
	PopulationDirector.auto_arrivals = false
	GameState.reset()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()
func _args() -> PackedStringArray:
	return OS.get_cmdline_user_args()
func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame
func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("saved ", name)
func _look(from: Vector3, to: Vector3, pitch: float, distance: float) -> void:
	var player: PlayerController = GameManager.player
	var rig: CameraRig = _main.camera_rig
	player.global_position = Vector3(from.x, VillageLayout.get_walk_height(from.x, from.z) + 0.3, from.z)
	var d := to - from
	rig.yaw = atan2(-d.x, -d.z)
	player.model.rotation.y = atan2(d.x, d.z)
	rig.pitch = pitch
	rig.distance = distance
func _build(type: StringName, near: Vector3, design: Dictionary) -> Dictionary:
	var info := StructureCatalog.info(type)
	for r in info["cost"]:
		GameState.add(r, int(info["cost"][r]))
	var at := _open_ground(type, near)
	var record := GameState.add_structure(type, at, 0.0)
	record["design"] = design
	await _wait(3)
	for s in get_tree().get_nodes_in_group("placed_structures"):
		if s.record == record:
			while not s.is_complete():
				s.add_work(1.0)
	print(type, " at ", at)
	return record
## The nearest flat, open spot to `near` where `type` can stand.
func _open_ground(type: StringName, near: Vector3) -> Vector3:
	var best := Vector3.INF
	var best_d := INF
	for gx in range(-30, 31):
		for gz in range(-30, 31):
			var at := Vector3(near.x + gx * 2.0, 0, near.z + gz * 2.0)
			var d := Vector2(gx, gz).length()
			if d >= best_d:
				continue
			at = VillageLayout.ground_point(at.x, at.z)
			if BuildMode.placement_reason(type, at, 0.0, null, true) == "":
				best = at
				best_d = d
	return best


func _run() -> void:
	WorldClock.set_time(10.5)
	WorldClock.set_time_scale(0.0)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _wait(60)
	for tip in _main.find_children("TutorialTips", "", true, false):
		tip.visible = false
		tip.set_process(false)
	Weather.instance.set_weather(Weather.Kind.CLEAR, 400.0, true)
	MonsterSpawner.instance.set_process(false)
	var designs := [
		{"style": "timber", "wall": 0, "roof": 3, "door": 1, "window": "shutters", "floor": "planks"},
		{"style": "stone", "wall": 5, "roof": 1, "door": 0, "window": "arched", "floor": "stone"},
		{"style": "painted", "wall": 4, "roof": 0, "door": 4, "window": "lattice", "floor": "tiles"},
		{"style": "stone", "wall": 1, "roof": 4, "door": 2, "window": "lattice", "floor": "carpet"},
	]
	var spots := [Vector3(30, 0, 40), Vector3(45, 0, 40), Vector3(60, 0, 30), Vector3(50, 0, 62)]
	var i := 0
	for type in HouseDesigns.SIZES:
		_houses.append(await _build(type, spots[i], designs[i]))
		i += 1
	await _wait(10)
	if not _args().has("--inside"):
		for j in 4:
			var r: Dictionary = _houses[j]
			var p: Array = r["position"]
			var at := Vector3(float(p[0]), 0, float(p[2]))
			var d := float(HouseDesigns.size_info(StringName(String(r["type"])))["d"])
			_look(at + Vector3(d * 0.4 + 4.0, 0, d * 0.5 + 7.0 + j), at, -0.12, 3.0 + j)
			await _wait(40)
			await _shot("%d_outside_%s" % [j + 1, r["type"]])
	if _args().has("--outside"):
		get_tree().quit()
		return
	# Inside: the small house (starter furniture) and the manor.
	for j in [0, 3]:
		var r: Dictionary = _houses[j]
		var place := Furnishings.place_of(r)
		Interiors.instance.enter(place, GameManager.player.global_position, 0.0)
		await get_tree().create_timer(1.0).timeout
		await _wait(10)
		var type := StringName(String(r["type"]))
		var size: Vector2 = HouseDesigns.size_info(type)["inside"]
		var rig: CameraRig = _main.camera_rig
		rig.pitch = -0.75
		rig.distance = 5.0 if j == 0 else 7.0
		rig.yaw = 0.0
		await _wait(30)
		await _shot("%d_inside_%s" % [5 + (0 if j == 0 else 1), type])
		if j == 3:
			# Add pieces to the manor's rooms, then look into the back rooms.
			for spec in [[&"bed_double", Vector3(0, 0, -4.4), 0.0], [&"wardrobe", Vector3(-1.6, 0, -1.0), PI], [&"settle", Vector3(-5.0, 0, 2.0), 0.0],
					[&"bookshelf", Vector3(-7.6, 0, 3.5), PI * 0.5], [&"table_round", Vector3(5.0, 0, 3.0), 0.0], [&"chair", Vector3(5.0, 0, 2.0), 0.0],
					[&"plant", Vector3(1.5, 0, 1.0), 0.0], [&"lamp", Vector3(-7.4, 0, 0.8), 0.0], [&"bed", Vector3(5.3, 0, -4.4), 0.0]]:
				var spot := Furnishings.instance.free_spot(spec[0], place, spec[1], spec[2])
				if spot != Vector3.INF:
					Furnishings.instance.add(spec[0], place, spot, spec[2])
			await _wait(10)
			GameManager.player.global_position = Interiors.ROOM_ORIGIN + Vector3(0, 0.05, -2.5)
			GameManager.player.model.visible = false
			rig.yaw = 0.0
			rig.pitch = -1.2
			rig.distance = 2.4
			await _wait(30)
			await _shot("7_manor_rooms")
			# Furnish menu.
			GameState.add(&"wood", 40)
			GameState.add(&"stone", 10)
			GameState.add(&"herbs", 6)
			GameManager.player.model.visible = true
			FurnishPanel.instance.toggle()
			await _wait(10)
			await _shot("8_furnish_menu")
			FurnishPanel.instance.toggle()
			# Placing a new table (preview).
			GameManager.player.global_position = Interiors.ROOM_ORIGIN + Vector3(5.0, 0.05, 4.0)
			GameManager.player.model.rotation.y = PI
			FurnishMode.instance.start_new(&"table")
			rig.yaw = 0.0
			rig.pitch = -0.6
			rig.distance = 4.0
			await _wait(20)
			await _shot("9_placing_table")
			FurnishMode.instance.cancel()
			# Carrying a chair.
			FurnishMode.instance.set_arranging(true)
			var chair: FurniturePiece = null
			for c in Interiors.instance._room.get_children():
				if c is FurniturePiece and c.type == &"chair":
					chair = c
			if chair:
				GameManager.player.global_position = chair.global_position + Vector3(0, 0.05, 1.2)
				chair.interact(GameManager.player)
				await _wait(20)
				rig.yaw = PI * 0.75
				rig.pitch = -0.35
				rig.distance = 3.5
				await _wait(10)
				await _shot("10_carrying_chair")
				FurnishMode.instance.cancel()
			FurnishMode.instance.set_arranging(false)
		if j == 0:
			var chest: FurniturePiece = null
			for c in Interiors.instance._room.get_children():
				if c is FurniturePiece and c.type == &"chest":
					chest = c
			GameState.add(&"wood", 12)
			GameManager.player.global_position = chest.global_position + Vector3(0, 0.05, 1.0)
			chest.interact(GameManager.player)
			await _wait(5)
			StoragePanel.instance._move(&"wood", 5, true)
			await _wait(5)
			await _shot("6b_storage_chest")
			StoragePanel.instance.close_panel()
		Interiors.instance.leave()
		await get_tree().create_timer(1.0).timeout
	get_tree().quit()
