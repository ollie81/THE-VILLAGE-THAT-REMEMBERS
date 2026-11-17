extends Node3D
## Developer tool: newcomers in the new hair styles and accessories.
## Run: godot --path . --resolution 1612x720 res://tools/style_lineup.tscn -- --out=/some/dir
var _out := "user://screenshots"

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()

func _run() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.78, 0.9)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.8, 0.85)
	e.ambient_light_energy = 0.7
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.7, 0.4, 0)
	add_child(sun)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var looks := [["female", "braids", ["flower_crown", "apron"]], ["male", "afro", ["cap", "satchel"]], ["female", "afro", ["necklace", "earrings"]],
		["male", "short", ["cap", "necklace"]], ["female", "braids", ["necklace", "scarf"]], ["male", "braids", ["flower_crown"]]]
	for i in looks.size():
		var look := AppearanceGenerator.generate(rng, looks[i][0], 30, "farmer", [])
		look.hair_style = looks[i][1]
		look.accessories = PackedStringArray(looks[i][2])
		var model := CharacterModel.new(look)
		model.position = Vector3(-2.5 + i * 1.0, 0, 0)
		add_child(model)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 1.5, 4.2)
	cam.look_at(Vector3(0, 1.2, 0))
	cam.fov = 45
	for i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join("styles.png"))
	cam.position = Vector3(-1.0, 1.65, 1.6)
	cam.look_at(Vector3(-1.0, 1.55, 0))
	for i in 5:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join("styles_close.png"))
	print("saved")
	get_tree().quit()
