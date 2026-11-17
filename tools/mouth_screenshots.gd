extends Node
## Developer tool: close-ups of people talking (the mouth opening and closing),
## a woman and a man, from the front and the side.
## Run: godot --path . --resolution 1612x720 res://tools/mouth_screenshots.tscn -- --out=/some/dir
var _out := "user://screenshots"

func _ready() -> void:
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
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.62, 0.7)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.8)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.6, 0.4, 0)
	add_child(sun)
	var people: Array = []
	var i := 0
	for female in [true, false]:
		var look := CharacterAppearance.new()
		look.chest_shape = 0.6 if female else 0.0
		look.hair_style = "long" if female else "short"
		var model := CharacterModel.create(look)
		add_child(model)
		model.position = Vector3(i * 0.6 - 0.3, 0, 0)
		people.append(model)
		i += 1
	await _wait(10)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 22.0
	for k in 2:
		var side := k == 1
		cam.position = Vector3(1.6, 1.62, 0.9) if side else Vector3(0, 1.6, 1.6)
		cam.look_at(Vector3(0, 1.58, 0))
		for m in people:
			m.set_animation(&"idle")
			m.set_talking(false)
		await _wait(20)
		await _shot("%d_quiet%s" % [k * 2 + 1, "_side" if side else ""])
		for m in people:
			m.set_talking(true)
		for f in 30:
			await get_tree().process_frame
			if f in [12, 22]:
				await _shot("%d_talking%s_%d" % [k * 2 + 2, "_side" if side else "", f])
	# Close-ups at fixed openings.
	for m in people:
		m.set_talking(false)
		m.set_process(false)
	cam.fov = 7.0
	for who in 2:
		var m = people[who]
		var face: Vector3 = m.get_face_position()
		for side in [false, true]:
			cam.position = face + (Vector3(0.9, 0.02, 0.9) if side else Vector3(0, 0.02, 1.4))
			cam.look_at(face + Vector3(0, -0.04, 0))
			for w in [0.0, 0.45, 0.85]:
				m.head.set_blend_shape_value(m._jaw_shape, w)
				await _wait(3)
				await _shot("close_%s_%s_%d" % ["woman" if who == 0 else "man", "side" if side else "front", int(w * 100)])
	get_tree().quit()
