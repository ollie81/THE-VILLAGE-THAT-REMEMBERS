extends Node
## Developer tool: families and generations in the real village. Builds a
## family through the real birth path (children's looks come from both
## parents), ages them, and captures a family portrait, three generations,
## children at play, talking to a child, and the family tree panel.
## Run: godot --path . --resolution 1612x720 res://tools/generations_screenshots.tscn -- --out=/some/dir

var _out_dir := "user://screenshots"
var _main
var _camera: Camera3D
var _director: PopulationDirector
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	SaveService.enabled = false
	PopulationDirector.auto_arrivals = false
	GameState.reset()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_rng.seed = 2024
	_run.call_deferred()


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out_dir.path_join(file_name + ".png"))
	print("saved ", file_name)


func _settle() -> void:
	_director.update_bodies()
	for i in 2000:
		if not _director.is_spawning():
			break
		await get_tree().process_frame
	await _wait(5)


func _villager(person: Person):
	return GameManager.get_villager(StringName(person.id))


func _cottage(at: Vector3) -> String:
	var record := GameState.add_structure(&"cottage", VillageLayout.ground_point(at.x, at.z), 0.0)
	await _wait(3)
	for structure in get_tree().get_nodes_in_group("placed_structures"):
		if structure.record == record:
			while not structure.is_complete():
				structure.add_work(1.0)
	await _wait(3)
	return Population.cottage_home_id(record)


func _child(a: Person, b: Person, age: int) -> Person:
	var child := Population.register_birth(a, b, _rng)
	child.birth_day = WorldClock.day - age * Person.year_days - 2
	if age >= Population.APPRENTICE_AGE:
		child.profession = Population.choose_trade(child, _rng)
	return child


## Freezes these villagers' own logic in front of a camera, keeping their
## animation going.
func _pose(people: Array, centre: Vector3, spacing: float, facing: float) -> void:
	for i in people.size():
		var villager = _villager(people[i])
		villager.process_mode = Node.PROCESS_MODE_DISABLED
		villager.model.process_mode = Node.PROCESS_MODE_ALWAYS
		var offset := Vector3((float(i) - (people.size() - 1) * 0.5) * spacing, 0, 0).rotated(Vector3.UP, facing)
		villager.global_position = VillageLayout.ground_point(centre.x + offset.x, centre.z + offset.z)
		villager.rotation.y = facing
		villager.model.set_detail(CharacterModel.Detail.FULL)
		villager.model.set_animation(&"idle")
		villager.model.set_expression(&"happy", 0.7)


func _release(people: Array) -> void:
	for person: Person in people:
		var villager = _villager(person)
		if villager:
			villager.process_mode = Node.PROCESS_MODE_INHERIT
			villager.model.process_mode = Node.PROCESS_MODE_INHERIT


func _look(from: Vector3, at: Vector3, fov: float) -> void:
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
	_director = PopulationDirector.instance
	_camera = Camera3D.new()
	add_child(_camera)
	var hud: Node = _main.find_child("Hud", true, false)

	# A family: two newcomers, together for years, with four children.
	var home := await _cottage(Vector3(-24.0, 0, 26.0))
	var mum := _director.settle_newcomer("female", 38)
	var dad := _director.settle_newcomer("male", 41)
	await _settle()
	mum.partner = ""
	dad.partner = ""
	Population.form_partnership(mum, dad)
	Population.marry(mum, dad)
	Population._move_in(mum, home)
	Population._move_in(dad, home)
	var children: Array = [_child(mum, dad, 15), _child(mum, dad, 10), _child(mum, dad, 6), _child(mum, dad, 3)]
	await _settle()

	# 1. Family portrait in front of their cottage.
	if hud:
		hud.visible = false
	var family: Array = [dad] + children + [mum]
	var portrait_centre := Vector3(-22.5, 0, 30.5)
	_pose(family, portrait_centre, 0.9, 0.0)
	_look(VillageLayout.ground_point(portrait_centre.x + 1.0, portrait_centre.z + 5.4) + Vector3(0, 1.3, 0), VillageLayout.ground_point(portrait_centre.x, portrait_centre.z) + Vector3(0, 0.95, 0), 42.0)
	await _wait(40)
	await _shot("01_family_portrait")
	# Close-up of the family's faces: resemblance between parents and children.
	var strip := Image.create(1612, 300, false, Image.FORMAT_RGBA8)
	var cell := 1612 / family.size()
	for i in family.size():
		var face: Vector3 = _villager(family[i]).model.get_face_position()
		_look(face + Vector3(0, 0.0, 1.0), face + Vector3(0, -0.03, 0), 28.0)
		await _wait(3)
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var crop := image.get_region(Rect2i(806 - 170, 360 - 160, 340, 320))
		crop.resize(cell, int(320.0 * cell / 340.0))
		strip.blit_rect(crop, Rect2i(0, 0, cell, 300), Vector2i(i * cell, 0))
	strip.save_png(_out_dir.path_join("02_family_faces.png"))
	print("saved 02_family_faces")
	_release(family)

	# 2. Three generations: Elias, his daughter and her son.
	var elias: Person = Population.get_person("elias")
	elias.birth_day = WorldClock.day - 66 * Person.year_days
	var daughter := _director.settle_newcomer("female", 34)
	await _settle()
	daughter.parents = ["elias"]
	elias.children.append(daughter.id)
	daughter.generation = 2
	var son_in_law := _director.settle_newcomer("male", 36)
	await _settle()
	daughter.partner = ""
	son_in_law.partner = ""
	Population.form_partnership(daughter, son_in_law)
	var grandson := _child(daughter, son_in_law, 5)
	# Elias's daughter looks like him.
	var elias_look := AppearanceCodec.from_dict(elias.appearance)
	var her_look := AppearanceGenerator.generate(_rng, "female", 25, daughter.profession, [], elias_look)
	daughter.appearance = AppearanceCodec.to_dict(her_look)
	daughter.look_age = 25
	_villager(daughter).visual_stage = -1  # rebuild with her new look
	await _settle()
	var generations: Array = [elias, daughter, grandson]
	var gen_centre := Vector3(-5.0, 0, 10.0)
	_pose(generations, gen_centre, 1.0, 0.0)
	_look(VillageLayout.ground_point(gen_centre.x, gen_centre.z + 4.2) + Vector3(0, 1.25, 0), VillageLayout.ground_point(gen_centre.x, gen_centre.z) + Vector3(0, 0.95, 0), 42.0)
	await _wait(40)
	await _shot("03_three_generations")
	_release(generations)
	if hud:
		hud.visible = true

	# 3. Children at play in the morning.
	WorldClock.set_time(8.0)
	for villager in GameManager.villagers:
		villager._place_for_current_time()
	await _wait(60)
	_camera.current = false
	var player = GameManager.player
	var rig: CameraRig = _main.camera_rig
	var playing: Array = children.filter(func(c: Person): return c.life_stage() == Person.STAGE_CHILD)
	var kid = _villager(playing[0])
	player.global_position = kid.global_position + Vector3(4.0, 0.4, 4.0)
	player.face_towards(kid.global_position)
	rig.yaw = player.model.rotation.y + PI + 0.3
	rig.pitch = -0.3
	rig.distance = 4.5
	await _wait(60)
	await _shot("04_children_playing")

	# 4. Talking to a child.
	var talker = _villager(children[2])
	var facing := Vector3(sin(talker.rotation.y), 0, cos(talker.rotation.y))
	player.global_position = talker.global_position + facing * 1.3 + Vector3(0, 0.3, 0)
	player.face_towards(talker.global_position)
	await _wait(10)
	GameManager.start_conversation(talker)
	var dialogue = _main.find_child("DialoguePanel", true, false)
	await _wait(60)
	dialogue.advance()
	await _wait(5)
	dialogue.advance()
	await _wait(60)
	await _shot("05_talking_to_a_child")
	while GameManager.is_in_conversation():
		if dialogue._choice_box.visible:
			dialogue._choose(dialogue._conversation.choices.size() - 1)
		else:
			dialogue.advance()
		await _wait(3)

	# 5. The family tree.
	var panel: PopulationPanel = _main.find_child("PopulationPanel", true, false)
	panel._selected = mum.id
	panel.toggle()
	await _wait(20)
	await _shot("06_family_tree")
	panel.toggle()
	get_tree().quit()
