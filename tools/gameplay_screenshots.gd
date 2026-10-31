extends Node
## Developer tool: plays through the gameplay loop in the real game scene and
## captures what the player sees at each step (HUD, prompts, build menu,
## placement preview, construction, farming, asking for help, the meeting).
## Run: godot --path . --resolution 1612x720 res://tools/gameplay_screenshots.tscn -- --out=/some/dir

var _out_dir: String = "user://screenshots"
var _main
var _rig: CameraRig


func _ready() -> void:
	SaveService.enabled = false
	GameState.reset()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := _out_dir.path_join(file_name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path, "  t=", Time.get_ticks_msec() / 1000)


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _nearest(kind: StringName) -> ResourceNode:
	var player = GameManager.player
	var best: ResourceNode = null
	for node in ResourceSpawner.nodes:
		if node.kind == kind and node.uses_left > 0 and (best == null or node.global_position.distance_to(player.global_position) < best.global_position.distance_to(player.global_position)):
			best = node
	return best


## Stands the player next to a target, facing it, with the camera behind
## and to the side so both are in view.
func _approach(target: Node3D, offset: Vector3, side: float = 0.6, distance: float = 6.0) -> void:
	var player = GameManager.player
	player.global_position = target.global_position + offset + Vector3(0, 0.4, 0)
	player.velocity = Vector3.ZERO
	player.face_towards(target.global_position)
	_rig.yaw = player.model.rotation.y + PI + side
	_rig.pitch = -0.32
	_rig.distance = distance
	await _wait(30)


## Clicks through the rest of a conversation, picking the last choice
## ("Goodbye" / "Never mind") whenever a menu is open.
func _finish_dialogue(dialogue) -> void:
	for i in 80:
		if not GameManager.is_in_conversation():
			return
		if dialogue._choice_box.visible:
			dialogue._choose(dialogue._conversation.choices.size() - 1)
		else:
			dialogue.advance()
		await _wait(3)
	push_error("conversation did not end")
	GameManager.end_conversation()


func _use(target: Node3D) -> bool:
	return GameManager.player.detector.try_interact(GameManager.player)


func _run() -> void:
	WorldClock.day = 1
	WorldClock.set_time(9.5)
	WorldClock.set_time_scale(0.0)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _wait(200)
	_rig = _main.camera_rig
	var player = GameManager.player
	var panels: GameplayPanels = _main.find_child("GameplayPanels", true, false)
	var dialogue = _main.find_child("DialoguePanel", true, false)

	# 1. Chopping: prompt, swing, floating "+2 wood", resource bar, objective.
	var tree := _nearest(&"tree")
	await _approach(tree, Vector3(1.0, 0, 0.8), 0.9, 5.0)
	await _shot("01_tree_prompt")
	_use(tree)
	await _wait(4)
	await _shot("02_chopping")
	await _wait(60)
	for i in 5:
		_use(_nearest(&"tree"))
		await _wait(70)
	var rock := _nearest(&"rock")
	await _approach(rock, Vector3(1.4, 0, 0.9), 0.9, 5.0)
	_use(rock)
	await _wait(4)
	await _shot("03_mining")
	await _wait(60)
	for i in 3:
		_use(_nearest(&"rock"))
		await _wait(70)
	await _wait(30)
	await _shot("04_objective_progress")

	# 2. Building: the Build menu, then a red and a green placement preview.
	GameState.add(&"wood", 40)
	GameState.add(&"stone", 20)
	player.global_position = VillageLayout.ground_point(-30, 6) + Vector3(0, 0.4, 0)
	player.model.rotation.y = -PI * 0.5
	_rig.yaw = player.model.rotation.y + PI + 0.5
	_rig.pitch = -0.45
	_rig.distance = 8.0
	await _wait(30)
	panels._build_menu.visible = true
	await _wait(10)
	await _shot("05_build_menu")
	panels._build_menu.visible = false
	BuildMode.instance.start(&"farm_plot")
	await _wait(30)
	await _shot("06_placement_valid")
	# Facing the river from its bank: the preview turns red and says why.
	var river_x := VillageLayout.river_center_x(20.0)
	player.global_position = VillageLayout.ground_point(river_x - 7.0, 20.0) + Vector3(0, 0.4, 0)
	player.model.rotation.y = PI * 0.5
	_rig.yaw = player.model.rotation.y + PI + 0.5
	await _wait(30)
	await _shot("07_placement_blocked")
	player.global_position = VillageLayout.ground_point(-30, 6) + Vector3(0, 0.4, 0)
	player.model.rotation.y = -PI * 0.5
	await _wait(10)
	BuildMode.instance.confirm()
	await _wait(10)
	var plot: PlacedStructure = get_tree().get_nodes_in_group("placed_structures")[0]
	await _approach(plot, Vector3(2.4, 0, 2.0), 0.7, 6.5)
	await _shot("08_construction_site")
	_use(plot)
	await _wait(80)
	_use(plot)
	await _wait(80)
	_use(plot)  # plant
	await _wait(80)
	WorldClock.advance(PlacedStructure.CROP_HOURS + 0.5)
	await _wait(30)
	await _shot("09_ripe_crops")
	_use(plot)
	await _wait(4)
	await _shot("10_harvest")
	await _wait(60)

	# 3. Asking a villager for help through the real dialogue panel.
	player.global_position = VillageLayout.ground_point(-30, -8) + Vector3(0, 0.4, 0)
	player.model.rotation.y = PI
	await _wait(5)
	BuildMode.instance.start(&"house")
	await _wait(10)
	BuildMode.instance.confirm()
	await _wait(10)
	var house: PlacedStructure = null
	for s in get_tree().get_nodes_in_group("placed_structures"):
		if s.get_type() == &"house":
			house = s
	var mara = GameManager.get_villager(&"mara")
	var facing := Vector3(sin(mara.rotation.y), 0, cos(mara.rotation.y))
	player.global_position = mara.global_position + facing * 1.6 + Vector3(0, 0.3, 0)
	player.face_towards(mara.global_position)
	await _wait(20)
	var talk := Conversation.new(mara, GameManager.PLAYER_ID)
	talk.choices = DialogueService.closing_menu()
	GameManager.start_scene(mara, talk)
	await _wait(60)
	dialogue._choose(0)
	await _wait(60)
	await _shot("11_ask_for_help")
	dialogue._choose(0)  # help build
	await _wait(120)
	await _shot("12_mara_agrees")
	await _finish_dialogue(dialogue)
	# Mara walks over and works on the house.
	mara.global_position = VillageLayout.ground_point(mara.task["point"].x, mara.task["point"].z)
	mara.assign_task(mara.task)
	await _wait(120)
	TaskSystem.instance.contribute(mara, 2.0)
	# Stand where both Mara and the site are in view.
	var from: Vector3 = mara.global_position - house.global_position
	from.y = 0.0
	player.global_position = house.global_position + from.normalized().rotated(Vector3.UP, 0.7) * 8.0 + Vector3(0, 0.4, 0)
	player.face_towards(house.global_position)
	_rig.yaw = player.model.rotation.y + PI + 0.35
	_rig.pitch = -0.35
	_rig.distance = 6.0
	await _wait(60)
	await _shot("13_mara_building")
	while not house.is_complete():
		house.add_work(1.0)
	await _wait(30)
	await _shot("14_house_finished")

	# 4. Evening village meeting at the fire.
	for v in GameManager.villagers:
		v.task = {}
		v.mind.record_interaction(GameManager.PLAYER_ID, "conversation", WorldClock.day, 9.0)
	GameState.check_objectives()
	WorldClock.set_time(18.2)
	await _wait(120)
	var objects: WorldObjects = _main.find_child("WorldObjects", true, false)
	var fire: Node3D = objects.get_node("FirePit")
	await _approach(fire, Vector3(1.9, 0, 0.6), 0.8, 6.0)
	await _shot("15_fire_prompt")
	_use(fire)
	await _wait(10)
	for v in GameManager.villagers:
		if v.has_task():
			v.global_position = VillageLayout.ground_point(v.task["point"].x, v.task["point"].z)
			v.assign_task(v.task)
	await _wait(200)
	await _shot("16_meeting")
	for i in 3:
		dialogue.advance()
		await _wait(90)
	await _shot("17_meeting_speech")
	await _finish_dialogue(dialogue)
	await _wait(40)
	await _shot("18_week_complete")
	print("objectives done: ", GameState.objective_index, " / 7")
	get_tree().quit()
