extends Node
## Developer tool: the visual pilot (textured ground, the cottage, nature).
## Run: godot --path . --resolution 1612x720 res://tools/pilot_screenshots.tscn -- --out=/some/dir [--only=a,b]
var _out := "user://screenshots"
var _only: PackedStringArray = []
var _main

func _ready() -> void:
	SaveService.enabled = false
	PopulationDirector.auto_arrivals = false
	GameState.reset()
	GameSettings.touch_mode = 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
		if arg.begins_with("--only="):
			_only = arg.substr(7).split(",")
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()

func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _want(name: String) -> bool:
	return _only.is_empty() or _only.has(name.get_slice("_", 0))

func _shot(name: String) -> void:
	if not _want(name):
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("saved ", name)

func _view(rig: CameraRig, player: Node3D, at: Vector3, yaw: float, pitch: float, distance: float) -> void:
	player.global_position = VillageLayout.ground_point(at.x, at.z) + Vector3(0, 0.5, 0)
	rig.yaw = yaw
	rig.pitch = pitch
	rig.distance = distance

func _run() -> void:
	WorldClock.set_time(9.5)
	WorldClock.set_time_scale(0.0)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _wait(60)
	for tip in _main.find_children("TutorialTips", "", true, false):
		tip.visible = false
		tip.set_process(false)
	var player: PlayerController = GameManager.player
	var rig: CameraRig = _main.camera_rig
	_view(rig, player, Vector3(0, 0, 12), 0.0, -0.32, 9.0)
	await _wait(60)
	await _shot("1_plaza")
	# Looking at a group of the village's trees.
	var best := Vector3.INF
	for entry: Dictionary in NatureSpawner._clearable:
		var p: Vector3 = entry["pos"]
		if String(entry["kind"]) in ["tree", "pine"] and p.length() > 14.0 and p.length() < 32.0 and (best == Vector3.INF or p.length() < best.length()):
			best = p
	if best != Vector3.INF:
		var from := best - best.normalized() * 9.0
		player.global_position = VillageLayout.ground_point(from.x, from.z) + Vector3(0, 0.5, 0)
		rig.yaw = atan2(-(best - from).x, -(best - from).z)
		rig.pitch = -0.08
		rig.distance = 5.0
	await _wait(40)
	await _shot("2_trees")
	var cottage = _main.find_child("KitCottage", true, false)
	if cottage:
		var door: Vector3 = cottage.door_outside()
		_view(rig, player, door + (door - cottage.global_position).normalized() * 3.0, cottage.rotation.y + 0.35, -0.12, 7.5)
		await _wait(60)
		await _shot("3_cottage")
		_view(rig, player, door + (door - cottage.global_position).normalized() * 3.0, cottage.rotation.y + 0.7, -0.12, 6.0)
		await _wait(40)
		await _shot("4_cottage_side")
		for room in ["living", "kitchen", "bedroom"]:
			var spot: Dictionary = cottage.room_view(room)
			player.global_position = spot["player"]
			rig.yaw = float(spot["yaw"])
			rig.pitch = -0.95
			rig.distance = 6.0
			await _wait(40)
			await _shot("5_" + room)
	WorldClock.set_time(19.2)
	_view(rig, player, Vector3(0, 0, 12), 0.0, -0.28, 9.0)
	await _wait(60)
	await _shot("6_evening")
	get_tree().quit()
