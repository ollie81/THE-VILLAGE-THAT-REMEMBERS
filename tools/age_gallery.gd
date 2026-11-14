extends Node
## Developer tool: one person at different ages, side by side in the
## village, to check child proportions, growing up and growing old.
## Run: godot --path . --resolution 1612x720 res://tools/age_gallery.tscn -- --out=/some/dir

const AGES: Array[int] = [3, 6, 9, 12, 15, 18, 35, 55, 72]

var _out_dir := "user://screenshots"


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


func _lineup(people: Array, file_name: String, spacing: float) -> void:
	var models: Array = []
	for i in people.size():
		var look: CharacterAppearance = people[i]
		var model := CharacterModel.new(look)
		add_child(model)
		model.position = Vector3((float(i) - (people.size() - 1) * 0.5) * spacing, 0, 0)
		model.set_animation(&"idle")
		models.append(model)
	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true
	camera.fov = 40.0
	var width := spacing * people.size()
	camera.position = Vector3(0, 1.25, width * 0.92)
	camera.look_at(Vector3(0, 0.85, 0), Vector3.UP)
	await _wait(40)
	await _shot(file_name)
	# Faces: a close-up strip of every age.
	var strip := Image.create(1612, 300, false, Image.FORMAT_RGBA8)
	var cell := 1612 / models.size()
	camera.fov = 30.0
	for i in models.size():
		var face: Vector3 = models[i].get_face_position()
		camera.global_position = face + Vector3(0, 0.0, 1.1)
		camera.look_at(face + Vector3(0, -0.04, 0), Vector3.UP)
		await _wait(3)
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var crop := image.get_region(Rect2i(806 - 160, 360 - 150, 320, 300))
		crop.resize(cell, int(300.0 * cell / 320.0))
		strip.blit_rect(crop, Rect2i(0, 0, cell, 300), Vector2i(i * cell, 0))
	strip.save_png(_out_dir.path_join(file_name + "_faces.png"))
	print("saved ", file_name, "_faces")
	for model in models:
		model.queue_free()
	camera.queue_free()
	await _wait(3)


func _run() -> void:
	WorldClock.set_time(10.5)
	WorldClock.set_time_scale(0.0)
	add_child(DayNightCycle.new())
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.42, 0.6, 0.32)
	plane.material = material
	ground.mesh = plane
	add_child(ground)
	await _wait(5)
	var rng := RandomNumberGenerator.new()
	for sex in ["female", "male"]:
		rng.seed = 11 if sex == "female" else 23
		var base := AppearanceGenerator.generate(rng, sex, 25, "farmer", [])
		var people: Array = []
		for age in AGES:
			people.append(AgeLook.for_age(base, age, 25, sex))
		await _lineup(people, "ages_" + sex, 0.95)
	get_tree().quit()
