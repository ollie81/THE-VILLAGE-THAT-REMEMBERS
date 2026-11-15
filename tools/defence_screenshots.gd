extends Node
## Developer tool (Stage 6): the alarm bell, the guards waiting at the edge
## with sword and shield, the raid, and the village gathered at the meeting
## circle.
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
	player.model.rotation.y = atan2(d.x, d.z)
	rig.pitch = pitch
	rig.distance = distance
func _run() -> void:
	WorldClock.set_time(17.5)
	WorldClock.set_time_scale(0.0)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _wait(60)
	for tip in _main.find_children("TutorialTips", "", true, false):
		tip.visible = false
		tip.set_process(false)
	Weather.instance.set_weather(Weather.Kind.CLEAR, 400.0, true)
	MonsterSpawner.instance.set_process(false)
	var rig: CameraRig = _main.camera_rig
	var defence := VillageDefence.instance
	var bell := defence.bell_position()
	# From the meeting circle, looking out at the bell.
	_look(rig, bell * 0.35, bell, -0.1, 3.0)
	await _wait(40)
	await _shot("1_alarm_bell")
	# The warning: guards take up arms and wait at the west edge.
	defence.schedule_raid("west road", WorldClock.time_of_day + 1.0)
	await _wait(5)
	var edge := defence.edge_point()
	for g in defence.guards():
		var spot: Vector3 = edge + defence._guard_offset(g)
		g.global_position = VillageLayout.ground_point(spot.x, spot.z)
	GameState.set_flag(&"has_sword", true)
	GameManager.player.combat.refresh_equipment()
	_look(rig, edge + Vector3(6, 0, 5), edge + Vector3(-6, 0, 0), -0.12, 4.0)
	await get_tree().create_timer(2.0).timeout
	await _shot("2_guards_waiting")
	# The raid.
	WorldClock.set_time(WorldClock.time_of_day + 1.05)
	await _wait(3)
	for m in defence.raiders_left():
		m.global_position = VillageLayout.ground_point(edge.x - 6 + randf_range(-2, 2), edge.z + randf_range(-3, 3)) + Vector3(0, 0.3, 0)
	await get_tree().create_timer(3.0).timeout
	_look(rig, edge + Vector3(5, 0, 6), edge + Vector3(-5, 0, 0), -0.15, 4.5)
	await get_tree().create_timer(1.5).timeout
	await _shot("3_raid")
	# Everyone else at the meeting circle.
	for v in GameManager.villagers:
		if not defence.is_guard(v):
			var p := Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
			v.global_position = VillageLayout.ground_point(p.x, p.z)
			v._think()
	_look(rig, Vector3(0, 0, 13), Vector3(0, 0, 0), -0.2, 5.0)
	await get_tree().create_timer(4.0).timeout
	for v in GameManager.villagers:
		print("  ", v.data.display_name, ": ", v.get_activity_description())
	await _shot("4_gathered")
	get_tree().quit()
