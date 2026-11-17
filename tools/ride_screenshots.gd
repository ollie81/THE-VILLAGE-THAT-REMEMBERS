extends Node
## Developer tool (Stage 3): riding a horse. Your horse with its saddle, the
## rider in the saddle from the side, front and behind (the playing camera),
## walking, galloping and jumping. --close: only the close-up checks.
var _out := "user://screenshots"
var _close := false
var _main
func _ready() -> void:
	SaveService.enabled = false
	PopulationDirector.auto_arrivals = false
	GameState.reset()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
		if arg == "--close":
			_close = true
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()
func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame
func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("saved ", name)
func _view(rig: CameraRig, player: PlayerController, around: float, pitch: float, distance: float) -> void:
	# `around` 0 = behind the rider, PI/2 = their left side, PI = in front.
	rig.yaw = player.model.rotation.y + PI + around
	rig.pitch = pitch
	# Riding adds CameraRig.RIDE_EXTRA_DISTANCE; take it off for close-ups.
	rig.distance = maxf(distance - (CameraRig.RIDE_EXTRA_DISTANCE if player.is_riding() else 0.0), 0.6)
func _run() -> void:
	WorldClock.set_time(10.0)
	WorldClock.set_time_scale(0.0)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _wait(60)
	for tip in _main.find_children("TutorialTips", "", true, false):
		tip.visible = false
		tip.set_process(false)
	Weather.instance.set_weather(Weather.Kind.CLEAR, 48.0, true)
	for flock in BirdFlocks.instance.flocks:
		flock["center"] = Vector3(500, 0, 500)
	var player: PlayerController = GameManager.player
	var rig: CameraRig = _main.camera_rig
	GameState.add(&"wood", 60)
	GameState.add(&"stone", 20)
	var at := BuildMode.nearest_free_spot(&"stable", VillageLayout.ground_point(-30.0, 30.0), 0.0, Vector3(0, 0, 100))
	var stable := GameState.add_structure(&"stable", at, 0.0)
	await _wait(3)
	for s in get_tree().get_nodes_in_group("placed_structures"):
		if s.record == stable:
			while not s.is_complete():
				s.add_work(1.0)
	VillageCredits.instance.earn(200, "ride_tool")
	var record := AnimalManager.instance.buy(&"horse")
	player.global_position = Vector3(at.x, VillageLayout.get_walk_height(at.x, at.z + 6) + 0.3, at.z + 6)
	await _wait(40)
	var horse := AnimalManager.instance.node_of(String(record["id"]))
	# The saddled horse.
	horse.state = Animal.State.IDLE
	horse._timer = 100.0
	player.face_towards(horse.global_position)
	rig.yaw = atan2(-(horse.global_position - player.global_position).x, -(horse.global_position - player.global_position).z) + 0.5
	rig.pitch = -0.2
	rig.distance = 3.0
	await _wait(30)
	await _shot("1_saddled_horse")
	horse.interact(player)
	await _wait(20)
	# Out into the open to ride.
	var open := Vector3(-30, 0, -60)
	player.global_position = Vector3(open.x, VillageLayout.get_walk_height(open.x, open.z) + 0.1, open.z)
	player.model.rotation.y = PI
	await _wait(30)
	_view(rig, player, PI * 0.5, -0.05, 2.6)
	await _wait(20)
	await _shot("2_side")
	_view(rig, player, PI * 0.8, -0.1, 2.6)
	await _wait(20)
	await _shot("3_front")
	_view(rig, player, 0.0, -0.25, 7.5)
	await _wait(20)
	await _shot("4_behind_idle")
	if _close:
		get_tree().quit()
		return
	# Walk, then gallop (holding run), seen from the side.
	Input.action_press("move_forward")
	await get_tree().create_timer(1.5).timeout
	_view(rig, player, PI * 0.45, -0.1, 4.0)
	await _wait(10)
	await _shot("5_walking")
	Input.action_press("run")
	await get_tree().create_timer(2.5).timeout
	_view(rig, player, PI * 0.4, -0.1, 4.5)
	await _wait(6)
	print("gallop speed ", Vector2(player.velocity.x, player.velocity.z).length())
	await _shot("6_gallop")
	_view(rig, player, 0.15, -0.2, 6.0)
	await _wait(6)
	await _shot("7_gallop_behind")
	Input.action_release("run")
	Input.action_release("move_forward")
	await get_tree().create_timer(1.5).timeout
	player.dismount()
	await _wait(20)
	_view(rig, player, PI * 0.7, -0.15, 4.0)
	await _wait(20)
	await _shot("8_dismounted")
	get_tree().quit()
