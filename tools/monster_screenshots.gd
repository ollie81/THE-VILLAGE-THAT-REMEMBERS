extends Node
## Developer tool (Stage 5): the monsters where they live. Slimes and a bat
## in the forest, a wolf in the wilds, skeletons at night, the dragon at its
## lair, and a fight.
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
func _clear() -> void:
	for m in MonsterSpawner.instance.active():
		m.free()
	MonsterSpawner.instance._dragon = null
## Player at `at` facing `dir`; monsters placed `ahead` metres in front.
func _scene(at: Vector3, yaw: float, kinds: Array, ahead: float, pitch: float, distance: float) -> void:
	_clear()
	var player: PlayerController = GameManager.player
	player.global_position = Vector3(at.x, VillageLayout.get_walk_height(at.x, at.z) + 0.3, at.z)
	player.model.rotation.y = yaw
	var rig: CameraRig = _main.camera_rig
	rig.yaw = yaw + PI
	rig.pitch = pitch
	rig.distance = distance
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	var side := Vector3(cos(yaw), 0, -sin(yaw))
	for i in kinds.size():
		var p := at + fwd * ahead + side * (i - (kinds.size() - 1) * 0.5) * 2.2
		var m := MonsterSpawner.instance.spawn(kinds[i], Vector3(p.x, TerrainGenerator.get_height(p.x, p.z) + 0.3, p.z))
		m.set_physics_process(false)
		m.rotation.y = yaw + PI
func _run() -> void:
	WorldClock.set_time(11.0)
	WorldClock.set_time_scale(0.0)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _wait(60)
	for tip in _main.find_children("TutorialTips", "", true, false):
		tip.visible = false
		tip.set_process(false)
	Weather.instance.set_weather(Weather.Kind.CLEAR, 400.0, true)
	MonsterSpawner.instance.set_process(false)
	GameState.set_flag(&"has_sword", true)
	GameManager.player.combat.refresh_equipment()
	var forest := VillageLayout.LAKE_CENTER + Vector3(30, 0, 24)
	_scene(forest, PI * 0.25, [&"slime", &"bat", &"slime"], 5.0, -0.15, 4.0)
	await _wait(60)
	await _shot("1_forest_slimes_bat")
	_scene(Vector3(112, 0, 30), -PI * 0.5, [&"wolf", &"wolf"], 5.0, -0.12, 4.0)
	await _wait(60)
	await _shot("2_wilds_wolves")
	if OS.get_cmdline_user_args().has("--wolves"):
		get_tree().quit()
		return
	WorldClock.set_time(22.5)
	_scene(forest, PI * 0.25, [&"skeleton", &"skeleton"], 5.0, -0.1, 4.0)
	await _wait(80)
	await _shot("3_night_skeletons")
	WorldClock.set_time(11.0)
	var lair := MonsterSpawner.DRAGON_LAIR
	_scene(lair + Vector3(-14, 0, 0), PI * 0.5, [&"dragon"], 10.0, -0.02, 5.0)
	await _wait(80)
	await _shot("4_dragon_lair")
	# A fight: let a slime come at you.
	_scene(forest, PI * 0.25, [&"slime"], 4.0, -0.2, 4.5)
	for m in MonsterSpawner.instance.active():
		m.set_physics_process(true)
	await get_tree().create_timer(1.5).timeout
	GameManager.player.combat.attack()
	await _wait(8)
	await _shot("5_fight")
	get_tree().quit()
