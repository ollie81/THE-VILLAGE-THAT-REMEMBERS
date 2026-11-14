extends Node
## Developer tool (Stage 4): villagers' daily lives. A villager feeding the
## cows at the pasture (with the info panel saying so), and the village when
## it starts to rain (people hurrying home to shelter).
var _out := "user://screenshots"
var _main
func _ready() -> void:
	SaveService.enabled = false
	PopulationDirector.auto_arrivals = false
	GameState.reset()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()
func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame
func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("saved ", name)
func _look(rig: CameraRig, from: Vector3, to: Vector3, pitch: float, distance: float) -> void:
	var player: PlayerController = GameManager.player
	player.global_position = Vector3(from.x, VillageLayout.get_walk_height(from.x, from.z) + 0.3, from.z)
	var d := to - from
	rig.yaw = atan2(-d.x, -d.z)
	rig.pitch = pitch
	rig.distance = distance
func _run() -> void:
	WorldClock.set_time(14.0)
	WorldClock.set_time_scale(0.0)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _wait(60)
	for tip in _main.find_children("TutorialTips", "", true, false):
		tip.visible = false
		tip.set_process(false)
	Weather.instance.set_weather(Weather.Kind.CLEAR, 48.0, true)
	var rig: CameraRig = _main.camera_rig
	# A villager feeding the cows.
	var v = GameManager.villagers[1]
	(v.brain as LifeBrain).use_plan([{"activity": "work", "location": "pasture", "label": "Feeding the cows at the pasture", "anim": "gather", "hour": 0.0}])
	var spot: Vector3 = VillageLayout.get_locations()["pasture"]["spots"][1]
	v.global_position = VillageLayout.ground_point(spot.x, spot.z + 1.0)
	v.start_activity(v.brain.choose_activity(v, WorldClock.time_of_day))
	_look(rig, spot + Vector3(-4, 0, 7), spot + Vector3(0, 0, -5), -0.15, 3.5)
	await get_tree().create_timer(3.0).timeout
	await _wait(60)
	GameManager.select_villager(v)
	await _wait(20)
	print(v.data.display_name, ": ", v.get_activity_description())
	await _shot("1_feeding_cows")
	GameManager.select_villager(null)
	# The village at work, then the rain starts.
	WorldClock.set_time(10.0)
	for p in GameManager.villagers:
		(p.brain as LifeBrain).plan_day(WorldClock.day)
		p._think()
	_look(rig, Vector3(10, 0, 16), Vector3(0, 0, 0), -0.25, 9.0)
	await get_tree().create_timer(4.0).timeout
	for p in GameManager.villagers:
		print("  dry: ", p.data.display_name, ": ", p.get_activity_description())
	Weather.instance.set_weather(Weather.Kind.RAIN, 4.0, true)
	await get_tree().create_timer(2.0).timeout
	for p in GameManager.villagers:
		print("  rain: ", p.data.display_name, ": ", p.get_activity_description())
	await _shot("2_rain_hurrying_home")
	get_tree().quit()
