extends Node
## Developer tool: every body animation side by side (three-quarter view),
## with a bench under the sitter, to check poses.
## Run: godot --path . --resolution 1612x720 res://tools/pose_gallery.tscn -- --out=/some/dir

const POSES: Array[StringName] = [&"idle", &"wave", &"bow", &"cheer", &"dance", &"sit", &"sit_ground", &"sleep"]
var _out_dir := "user://screenshots"


func _ready() -> void:
	SaveService.enabled = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


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
	var look := PlayerController.create_default_appearance()
	var child_look := AgeLook.for_age(look, 7, 25)
	for row in 2:
		for i in POSES.size():
			var model := CharacterModel.new(look if row == 0 else child_look)
			add_child(model)
			model.position = Vector3((i - (POSES.size() - 1) * 0.5) * 1.35, 0, -row * 2.4)
			model.rotation.y = 0.5 if row == 1 else 0.0
			model.set_animation(POSES[i])
			if POSES[i] == &"sit":
				var bench := CSGBox3D.new()
				bench.size = Vector3(0.9, 0.45 * (1.0 if row == 0 else 0.62), 0.45)
				bench.position = model.position + Vector3(0, bench.size.y * 0.5, -0.05).rotated(Vector3.UP, model.rotation.y)
				bench.rotation.y = model.rotation.y
				add_child(bench)
	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true
	camera.fov = 45.0
	camera.position = Vector3(0, 2.6, 7.6)
	camera.look_at(Vector3(0, 0.55, -1.0), Vector3.UP)
	await _wait(90)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out_dir.path_join("poses.png"))
	print("saved poses")
	# Side views of each pose, adult row.
	var strip := Image.create(1612, 720, false, Image.FORMAT_RGBA8)
	var cell := 1612 / 4
	var picks: Array[int] = [2, 5, 6, 7]
	for k in picks.size():
		var i := picks[k]
		var at := Vector3((i - (POSES.size() - 1) * 0.5) * 1.35, 0, 0)
		camera.fov = 40.0
		camera.position = at + Vector3(2.6, 0.9, 0.9)
		camera.look_at(at + Vector3(0, 0.55, -0.2), Vector3.UP)
		await _wait(40)
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var crop := image.get_region(Rect2i(806 - 300, 0, 600, 720))
		crop.resize(cell, 720)
		strip.blit_rect(crop, Rect2i(0, 0, cell, 720), Vector2i(k * cell, 0))
	strip.save_png(_out_dir.path_join("poses_side.png"))
	print("saved side")
	get_tree().quit()
