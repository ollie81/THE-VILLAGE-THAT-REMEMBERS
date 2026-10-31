extends Node
## Developer tool: village life around the player in the real scene: the
## Actions menu, dancing with villagers joining in, sitting on the logs by
## the fire, sleeping under the stars, a passer-by's greeting, the kind and
## unkind menus, a witness reacting, and the voice settings.
## Run: godot --path . --resolution 1612x720 res://tools/life_screenshots.tscn -- --out=/some/dir

var _out_dir := "user://screenshots"
var _main


func _ready() -> void:
	SaveService.enabled = false
	PopulationDirector.auto_arrivals = false
	GameState.reset()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out_dir.path_join(file_name + ".png"))
	print("saved ", file_name)


func _behind(rig: CameraRig, player, side: float, pitch: float, distance: float) -> void:
	rig.yaw = player.model.rotation.y + PI + side
	rig.pitch = pitch
	rig.distance = distance


func _run() -> void:
	WorldClock.day = 3
	WorldClock.set_time(18.6)
	WorldClock.set_time_scale(0.0)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _wait(60)
	var player: PlayerController = GameManager.player
	var rig: CameraRig = _main.camera_rig
	var actions: ActionsMenu = _main.find_child("ActionsMenu", true, false)
	var dialogue = _main.find_child("DialoguePanel", true, false)
	for v in GameManager.villagers:
		v.mind.record_interaction(GameManager.PLAYER_ID, "conversation", 1, 9.0)
		v.mind.adjust_opinion(GameManager.PLAYER_ID, 20.0, 10.0)

	# Everyone gathers at the meeting circle for the evening (some on the logs).
	for v in GameManager.villagers:
		v._place_for_current_time()
	await _wait(120)

	# 1. The Actions menu.
	player.global_position = VillageLayout.ground_point(6.0, 3.0) + Vector3(0, 0.4, 0)
	player.face_towards(Vector3.ZERO)
	_behind(rig, player, 0.35, -0.28, 5.5)
	await _wait(40)
	actions.toggle()
	await _wait(10)
	await _shot("01_actions_menu")
	# 2. Dance: the outgoing ones join in, others laugh or grumble.
	actions.do(&"dance")
	await _wait(14)
	await _shot("02_dancing_together")
	await _wait(360)

	# 3. Sitting on a log by the fire with the villagers.
	var objects: WorldObjects = _main.find_child("WorldObjects", true, false)
	var log_object: Node3D = objects.get_node("Log1")
	player.global_position = log_object.global_position + (log_object.global_position.normalized() * 1.2) + Vector3(0, 0.4, 0)
	await _wait(10)
	objects._sit_on(player, [VillageLayout.plaza_seats()[2], VillageLayout.plaza_seats()[3]])
	await _wait(30)
	_behind(rig, player, 0.6, -0.22, 4.2)
	await _wait(60)
	await _shot("03_sitting_by_the_fire")
	player.stand_up()

	# 4. A conversation: the kind and unkind menus.
	GameState.add(&"herbs", 2)
	var mara = GameManager.get_villager(&"mara")
	mara.global_position = VillageLayout.ground_point(-2.0, -9.0)
	mara._decision_timer = 1000.0
	var facing := Vector3(sin(mara.rotation.y), 0, cos(mara.rotation.y))
	player.global_position = mara.global_position + facing * 1.6 + Vector3(0, 0.3, 0)
	player.face_towards(mara.global_position)
	await _wait(10)
	GameManager.start_conversation(mara)
	for i in 8:
		await _wait(30)
		if dialogue._choice_box.visible:
			break
		dialogue.advance()
		await _wait(3)
		dialogue.advance()
	await _wait(20)
	await _shot("04_conversation_menu")
	# Answer her topic, then the closing menu appears.
	if not dialogue._conversation.choice_texts().has("Be kind..."):
		dialogue._choose(0)
		for i in 10:
			await _wait(20)
			if dialogue._choice_box.visible:
				break
			dialogue.advance()
			await _wait(3)
			dialogue.advance()
	await _wait(10)
	var texts: PackedStringArray = dialogue._conversation.choice_texts()
	dialogue._choose(Array(texts).find("Be kind..."))
	await _wait(20)
	await _shot("05_be_kind")
	dialogue._choose(0)  # give a gift
	await _wait(90)
	await _shot("06_gift_reply")
	while not dialogue._choice_box.visible and GameManager.is_in_conversation():
		dialogue.advance()
		await _wait(3)
	texts = dialogue._conversation.choice_texts()
	dialogue._choose(Array(texts).find("Be unkind..."))
	await _wait(20)
	await _shot("07_be_unkind")
	# Insult her, with Tomas watching.
	var tomas = GameManager.get_villager(&"tomas")
	tomas.global_position = mara.global_position + Vector3(2.4, 0, 1.0)
	tomas._decision_timer = 1000.0
	tomas.state = Villager.State.IDLE
	tomas.visible = true
	dialogue._choose(1)
	await _wait(90)
	await _shot("08_insult")
	while GameManager.is_in_conversation():
		if dialogue._choice_box.visible:
			dialogue._choose(dialogue._conversation.choices.size() - 1)
		else:
			dialogue.advance()
		await _wait(3)
	_behind(rig, player, 1.0, -0.2, 4.0)
	await _wait(6)
	await _shot("09_witness")

	# 5. Sleeping under the stars, then a greeting in the morning.
	WorldClock.set_time(22.5)
	player.global_position = VillageLayout.ground_point(12.0, -4.0) + Vector3(0, 0.4, 0)
	await _wait(10)
	actions.do(&"sleep")
	_behind(rig, player, 1.3, -0.5, 3.6)
	await _wait(60)
	await _shot("10_sleeping_outside")
	await _wait(int(PlayerController.FALL_ASLEEP_TIME * 60.0))
	player.stand_up()
	for v in GameManager.villagers:
		v._place_for_current_time()
		v.last_spoke_msec = -1000000
	await _wait(30)
	var elias = GameManager.get_villager(&"elias")
	elias.visible = true
	elias.state = Villager.State.IDLE
	elias._decision_timer = 1000.0
	player.global_position = elias.global_position + Vector3(1.8, 0.4, 0.6)
	player.face_towards(elias.global_position)
	_behind(rig, player, 0.5, -0.2, 4.0)
	PlayerSocial.instance._last_greeting_msec = -100000
	await _wait(12)
	await _shot("11_morning_greeting")

	# 6. Settings: voices.
	var settings = _main.find_child("SettingsPanel", true, false)
	if settings == null:
		for node in _main.find_children("*", "Control", true, false):
			if node.get_script() == SettingsPanel:
				settings = node
	if settings:
		settings.visible = true
		if settings.has_method("_sync"):
			settings._sync()
		await _wait(10)
		await _shot("12_voice_settings")
	get_tree().quit()
