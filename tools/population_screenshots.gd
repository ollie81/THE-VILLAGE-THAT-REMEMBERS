extends Node
## Developer tool: grows the village through the real arrival path and
## captures the newcomers: a line-up of generated villagers, face portraits,
## a traveller walking in, the welcome conversation, the camp, an evening at
## the meeting circle, Village View and the population panel.
## Run: godot --path . --resolution 1612x720 res://tools/population_screenshots.tscn -- --out=/some/dir

const NEWCOMERS := 22

var _out_dir: String = "user://screenshots"
var _main
var _camera: Camera3D


func _ready() -> void:
	SaveService.enabled = false
	PopulationDirector.auto_arrivals = false
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
	print("saved ", path)


func _image() -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _look(from: Vector3, at: Vector3, fov: float = 50.0) -> void:
	_camera.current = true
	_camera.fov = fov
	_camera.global_position = from
	_camera.look_at(at, Vector3.UP)


func _run() -> void:
	WorldClock.day = 2
	WorldClock.set_time(10.5)
	WorldClock.set_time_scale(0.0)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _wait(60)
	_camera = Camera3D.new()
	add_child(_camera)
	var director: PopulationDirector = PopulationDirector.instance
	var hud_root: Node = _main.find_child("Hud", true, false)

	# Grow the village through the real arrival path, one person at a time.
	for i in NEWCOMERS:
		director.settle_newcomer()
		while director.is_spawning():
			await _wait(2)
	print("population: ", Population.count())

	# 1. Line-up of twelve newcomers in the village, frozen mid-idle.
	var newcomers: Array = []
	for villager in GameManager.villagers:
		if villager.person and not villager.person.founder:
			newcomers.append(villager)
	# Their own logic is paused (so they stay put) but the model keeps
	# animating and keeps full detail.
	var row_centre := Vector3(-2.0, 0, 9.5)
	for i in 12:
		var villager = newcomers[i]
		villager.process_mode = Node.PROCESS_MODE_DISABLED
		villager.model.process_mode = Node.PROCESS_MODE_ALWAYS
		var row := i / 6
		var x := (float(i % 6) - 2.5) * 1.15 + (0.55 if row == 1 else 0.0)
		var z := row_centre.z - row * 1.6
		villager.global_position = VillageLayout.ground_point(row_centre.x + x, z)
		villager.rotation.y = 0.0
		villager.model.set_detail(CharacterModel.Detail.FULL)
		villager.model.set_animation(&"idle")
		villager.model.set_expression(&"happy" if i % 3 == 0 else &"neutral", 0.6)
	if hud_root:
		hud_root.visible = false
	_look(Vector3(row_centre.x, 1.6, row_centre.z + 6.0), Vector3(row_centre.x, 1.05, row_centre.z - 0.6), 44.0)
	await _wait(30)
	await _shot("01_newcomers_lineup")

	# 2. Portraits: six faces in a grid.
	var grid := Image.create(1612, 720, false, Image.FORMAT_RGBA8)
	for i in 6:
		var villager = newcomers[i]
		var face: Vector3 = villager.model.get_face_position()
		_look(face + Vector3(0.22, 0.04, 0.8), face + Vector3(0.0, -0.04, 0), 30.0)
		await _wait(4)
		var image: Image = await _image()
		image.resize(1612 / 3, 360)
		var crop := image.get_region(Rect2i(0, 0, 537, 360))
		grid.blit_rect(crop, Rect2i(0, 0, 537, 360), Vector2i((i % 3) * 537, (i / 3) * 360))
	grid.save_png(_out_dir.path_join("02_newcomer_portraits.png"))
	print("saved portraits")
	for i in 12:
		newcomers[i].process_mode = Node.PROCESS_MODE_INHERIT
		newcomers[i].model.process_mode = Node.PROCESS_MODE_INHERIT
		newcomers[i]._place_for_current_time()
	if hud_root:
		hud_root.visible = true

	# 3. A traveller walks in over the bridge.
	WorldClock.day = 3
	var traveller := director.bring_traveller()
	while director.is_spawning():
		await _wait(2)
	var visitor = director.get_villager(traveller)
	var bridge := VillageLayout.ground_point(VillageLayout.river_center_x(0.0) + 2.0, 0.0)
	visitor.global_position = bridge
	await _wait(30)
	_camera.current = false
	var player = GameManager.player
	player.global_position = bridge + Vector3(-9.0, 0.6, 2.0)
	player.face_towards(visitor.global_position)
	var rig: CameraRig = _main.camera_rig
	rig.yaw = player.model.rotation.y + PI + 0.35
	rig.pitch = -0.2
	rig.distance = 5.5
	await _wait(40)
	await _shot("03_traveller_arrives")

	# 4. Meeting them: welcome, hear more, or turn away.
	visitor.global_position = VillageLayout.ground_point(3.0, 0.5)
	await _wait(5)
	var facing := Vector3(sin(visitor.rotation.y), 0, cos(visitor.rotation.y))
	player.global_position = visitor.global_position + facing * 1.6 + Vector3(0, 0.3, 0)
	player.face_towards(visitor.global_position)
	await _wait(10)
	GameManager.start_conversation(visitor)
	var dialogue = _main.find_child("DialoguePanel", true, false)
	for i in 3:
		await _wait(50)
		dialogue.advance()
		await _wait(5)
		dialogue.advance()
	await _wait(30)
	await _shot("04_welcome_choice")
	dialogue._choose(0)
	await _wait(80)
	await _shot("05_welcomed")
	while GameManager.is_in_conversation():
		if dialogue._choice_box.visible:
			dialogue._choose(dialogue._conversation.choices.size() - 1)
		else:
			dialogue.advance()
		await _wait(3)

	# 5. Evening at the meeting circle: everyone at their spot.
	WorldClock.set_time(19.6)
	for villager in GameManager.villagers:
		villager._place_for_current_time()
	await _wait(90)
	player.global_position = VillageLayout.ground_point(9.0, 6.0) + Vector3(0, 0.4, 0)
	player.face_towards(Vector3.ZERO)
	rig.yaw = player.model.rotation.y + PI + 0.25
	rig.pitch = -0.32
	rig.distance = 7.0
	await _wait(60)
	await _shot("06_evening_gathering")

	# 6. The camp, where newcomers sleep until there's a cottage for them.
	WorldClock.set_time(16.0)
	await _wait(10)
	var camp := VillageLayout.camp_center()
	_look(VillageLayout.ground_point(camp.x - 4.0, camp.z + 5.5) + Vector3(0, 3.2, 0), camp + Vector3(0, 0.3, -0.5), 58.0)
	await _wait(30)
	await _shot("07_camp")
	_camera.current = false

	# 7. Midday in the village: the farm and garden at work.
	WorldClock.set_time(13.5)
	for villager in GameManager.villagers:
		villager._place_for_current_time()
	await _wait(30)
	_look(Vector3(4.0, 7.5, 2.0), Vector3(12.0, 0.0, 15.0), 55.0)
	await _wait(40)
	await _shot("08_village_at_work")
	_camera.current = false
	await _wait(10)

	# 8. The population panel.
	var panel: PopulationPanel = _main.find_child("PopulationPanel", true, false)
	panel.toggle()
	await _wait(20)
	await _shot("09_population_panel")
	print("done: population ", Population.count())
	get_tree().quit()
