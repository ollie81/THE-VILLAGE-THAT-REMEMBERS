extends Node3D
## Developer tool: every house size in a different style side by side on open
## ground, front three-quarter view, by day (and --night for glowing windows).
var out := "user://screenshots"
func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.76, 0.9)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.75, 0.7, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 80)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.45, 0.6, 0.3)
	ground.material_override = gm
	add_child(ground)
	var designs := [
		{"style": "timber", "wall": 0, "roof": 3, "door": 1, "window": "shutters", "floor": "planks"},
		{"style": "stone", "wall": 5, "roof": 1, "door": 0, "window": "arched", "floor": "stone"},
		{"style": "painted", "wall": 4, "roof": 0, "door": 4, "window": "lattice", "floor": "tiles"},
		{"style": "stone", "wall": 1, "roof": 4, "door": 2, "window": "lattice", "floor": "carpet"},
	]
	var x := -22.0
	var i := 0
	for type in HouseDesigns.SIZES:
		var w := float(HouseDesigns.size_info(type)["w"])
		x += w * 0.5
		var house := HouseBuilder.build(type, designs[i])
		house.position = Vector3(x, 0, 0)
		add_child(house)
		x += w * 0.5 + 3.0
		i += 1
	var cam := Camera3D.new()
	cam.fov = 50
	cam.position = Vector3(2, 9, 34)
	add_child(cam)
	cam.look_at(Vector3(2, 2.5, 0))
	for k in 5:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/house_lineup.png")
	cam.position = Vector3(-30, 6, 20)
	cam.look_at(Vector3(-8, 2.5, 0))
	for k in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/house_lineup_side.png")
	get_tree().quit()
