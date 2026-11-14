extends Node
## Developer tool: the real character models (player and villagers).
## Run: godot --path . --resolution 1612x720 res://tools/character_screenshots.tscn -- --out=/some/dir
var _out := "user://screenshots"
var _main

func _ready() -> void:
	SaveService.enabled = false
	PopulationDirector.auto_arrivals = false
	GameState.reset()
	GameSettings.touch_mode = 1
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
	print("player model: ", player.model.get_class(), " ", player.model.get_script().get_global_name())
	# The player, from the front.
	player.global_position = VillageLayout.ground_point(0, 12) + Vector3(0, 0.3, 0)
	player.model.rotation.y = 0.0
	rig.yaw = 0.0
	rig.pitch = -0.05
	rig.distance = 2.4
	await _wait(40)
	await _shot("1_player_front")
	player.model.rotation.y = -0.4
	rig.yaw = 0.0
	rig.distance = 1.3
	rig.pitch = 0.0
	await _wait(30)
	await _shot("2_player_face")
	# The founders lined up.
	var i := 0
	for v in GameManager.villagers:
		if not is_instance_valid(v) or i >= 5:
			continue
		v.set_physics_process(false)
		v.set_process(false)
		v.global_position = VillageLayout.ground_point(-3.0 + i * 1.5, 16.0)
		v.model.rotation.y = 0.0
		v.model.set_animation(&"idle")
		i += 1
	for v in GameManager.villagers:
		if is_instance_valid(v):
			v.model.rotation.y = 0.0
	player.global_position = VillageLayout.ground_point(-6.0, 19.0) + Vector3(0, 0.3, 0)
	rig.yaw = -0.5
	rig.pitch = -0.1
	rig.distance = 3.5
	await _wait(60)
	await _shot("3_villagers")
	# Walking.
	player.global_position = VillageLayout.ground_point(0, 12) + Vector3(0, 0.3, 0)
	player.model.set_animation(&"walk", 1.5)
	rig.yaw = PI * 0.5
	rig.distance = 3.0
	await _wait(20)
	await _shot("4_walking")
	# Accessories on the player.
	var look := AppearanceCodec.from_dict(AppearanceCodec.to_dict(player.model.appearance))
	WardrobeCatalog.apply(look, "straw_hat")
	WardrobeCatalog.apply(look, "glasses")
	WardrobeCatalog.apply(look, "scarf")
	player.set_appearance(look)
	player.global_position = VillageLayout.ground_point(0, 12) + Vector3(0, 0.3, 0)
	player.model.set_animation(&"idle")
	player.model.rotation.y = -0.3
	rig.yaw = 0.0
	rig.pitch = -0.05
	rig.distance = 1.4
	await _wait(40)
	await _shot("5_accessories")
	# A crowd of newcomers: many different looks.
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var jobs: Array = Professions.ids()
	var others: Array = []
	for k in 8:
		var person_look: CharacterAppearance = AppearanceGenerator.generate(rng, "female" if k % 2 == 0 else "male", 20 + k * 6, String(jobs[k % jobs.size()]), others)
		others.append(person_look)
		var m := CharacterModel.create(person_look)
		_main.add_child(m)
		m.global_position = VillageLayout.ground_point(-5.0 + k * 1.4, 30.0)
		m.rotation.y = 0.0
	player.global_position = VillageLayout.ground_point(0, 34.5) + Vector3(0, 0.3, 0)
	player.model.rotation.y = PI
	rig.yaw = 0.0
	rig.pitch = -0.08
	rig.distance = 2.5
	await _wait(50)
	await _shot("6_crowd")
	get_tree().quit()
