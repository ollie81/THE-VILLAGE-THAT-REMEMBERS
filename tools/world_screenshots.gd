extends Node
## Developer tool: the wider world (Stage 1): farmland and windmill, the
## south street, the forest lake and swimming, the ruins, the watchtower,
## the mountains.
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
func _go(player: PlayerController, rig: CameraRig, at: Vector3, look_at: Vector3, pitch: float, distance: float) -> void:
	player.global_position = Vector3(at.x, VillageLayout.get_walk_height(at.x, at.z) + 0.3, at.z)
	var to := look_at - at
	rig.yaw = atan2(-to.x, -to.z)
	rig.pitch = pitch
	rig.distance = distance
func _run() -> void:
	WorldClock.set_time(10.0)
	WorldClock.set_time_scale(0.0)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _wait(60)
	for tip in _main.find_children("TutorialTips", "", true, false):
		tip.visible = false
		tip.set_process(false)
	var player: PlayerController = GameManager.player
	var rig: CameraRig = _main.camera_rig
	_go(player, rig, Vector3(-30, 0, -96), WorldExpansion.WINDMILL, -0.12, 7.0)
	await _wait(60)
	await _shot("1_farmland")
	_go(player, rig, Vector3(0, 0, 100), Vector3(0, 0, 121), -0.15, 9.0)
	await _wait(60)
	await _shot("2_south_street")
	_go(player, rig, VillageLayout.LAKE_CENTER + Vector3(30, 0, 6), VillageLayout.LAKE_CENTER, -0.12, 7.0)
	await _wait(60)
	await _shot("3_lake")
	# Swim out into the lake.
	var water := VillageLayout.LAKE_CENTER + Vector3(4, 0, 2)
	player.global_position = Vector3(water.x, VillageLayout.WATER_LEVEL - 0.5, water.z)
	for i in 60:
		await get_tree().physics_frame
	player.model.set_animation(&"swim", 2.0)
	rig.yaw = player.model.rotation.y + PI * 0.6
	rig.pitch = -0.2
	rig.distance = 4.0
	await _wait(30)
	print("swimming: ", player.swimming, " y=", player.global_position.y)
	await _shot("4_swimming")
	_go(player, rig, WorldExpansion.RUINS + Vector3(12, 0, 6), WorldExpansion.RUINS, -0.15, 6.0)
	await _wait(60)
	await _shot("5_ruins")
	_go(player, rig, WorldExpansion.WATCHTOWER + Vector3(-14, 0, 8), WorldExpansion.WATCHTOWER, -0.05, 7.0)
	await _wait(60)
	await _shot("6_watchtower")
	_go(player, rig, Vector3(0, 0, -60), Vector3(0, 0, -200), 0.05, 6.0)
	await _wait(60)
	await _shot("7_mountains")
	get_tree().quit()
