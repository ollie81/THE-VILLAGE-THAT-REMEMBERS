extends Node3D
## Developer tool: renders close-ups of every character's face using the
## game's real day/night lighting, to judge facial art.
##
## For each character it saves:
##   <id>_angles.png       front, three-quarter and profile, head-and-shoulders
##   <id>_expressions.png  every facial expression side by side (if supported)
## Plus lineup_gameplay.png at the third-person camera distance.
##
## Run (needs a display or xvfb-run):
##   godot --path . res://tools/face_gallery.tscn -- --out=/some/dir [--time=10.5]

const VILLAGERS: Array[String] = [
	"res://data/villagers/mara.tres",
	"res://data/villagers/elias.tres",
	"res://data/villagers/nia.tres",
	"res://data/villagers/tomas.tres",
	"res://data/villagers/sera.tres",
]
const EXPRESSIONS: Array[StringName] = [&"neutral", &"happy", &"laughing", &"sad", &"angry", &"surprised", &"worried"]

var _out_dir := ""
var _camera: Camera3D
var _stage: Node3D
var _only_first := false


func _ready() -> void:
	SaveService.enabled = false
	var hour := 10.5
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.substr(6)
		elif arg.begins_with("--time="):
			hour = float(arg.substr(7))
		elif arg.begins_with("--quality="):
			GameSettings.set_quality(int(arg.substr(10)))
		elif arg == "--only-first":
			_only_first = true
	WorldClock.set_time(hour)
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
	_camera = Camera3D.new()
	add_child(_camera)
	_camera.make_current()
	_run.call_deferred()


func _looks() -> Array:
	var looks: Array = []
	for path in VILLAGERS:
		var data := load(path) as VillagerData
		looks.append([String(data.id), data.appearance])
	looks.append(["player", PlayerController.create_default_appearance()])
	return looks


func _clear_stage() -> void:
	if _stage:
		_stage.queue_free()
	_stage = Node3D.new()
	add_child(_stage)


func _spawn(look: CharacterAppearance, position: Vector3, yaw: float) -> CharacterModel:
	var model := CharacterModel.new(look)
	model.position = position
	model.rotation.y = yaw
	_stage.add_child(model)
	return model


func _frame(focus: Vector3, distance: float, fov: float, yaw_deg: float = 0.0, pitch_deg: float = 0.0) -> void:
	_camera.fov = fov
	var offset := Basis(Vector3.UP, deg_to_rad(yaw_deg)) * Basis(Vector3.RIGHT, deg_to_rad(pitch_deg)) * Vector3(0, 0, distance)
	_camera.global_transform = Transform3D(Basis.looking_at(-offset, Vector3.UP), focus + offset)


func _capture(file_name: String) -> void:
	for i in 40:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := _out_dir.path_join(file_name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_out_dir)
	for entry in _looks():
		var id: String = entry[0]
		var look: CharacterAppearance = entry[1]
		var head_y := 1.7 * look.height_scale

		# Front, three-quarter, profile.
		_clear_stage()
		for i in 3:
			var model := _spawn(look, Vector3((i - 1) * 0.62, 0, 0), [0.0, 0.62, PI * 0.5][i])
			model.set_animation(&"idle")
		_frame(Vector3(0, head_y - 0.06, 0), 3.6, 24.0)
		await _capture(id + "_angles")

		# Face close-up, front and profile, about a metre away.
		_clear_stage()
		_spawn(look, Vector3(-0.3, 0, 0), 0.0)
		_spawn(look, Vector3(0.3, 0, 0), PI * 0.5)
		_frame(Vector3(0, head_y + 0.02, 0), 1.75, 24.0)
		await _capture(id + "_closeup")
		if _only_first and id != "mara":
			continue

		# Expressions.
		_clear_stage()
		var models: Array[CharacterModel] = []
		for i in EXPRESSIONS.size():
			var model := _spawn(look, Vector3((i - 3) * 0.42, 0, 0), 0.0)
			models.append(model)
		await get_tree().process_frame
		var supported := models[0].has_method("set_expression")
		if supported:
			for i in models.size():
				models[i].call("set_expression", EXPRESSIONS[i], 1.0, 0.0)
			_frame(Vector3(0, head_y - 0.08, 0), 8.6, 20.0)
			await _capture(id + "_expressions")

	# Everyone at third-person gameplay distance.
	_clear_stage()
	var looks := _looks()
	for i in looks.size():
		_spawn(looks[i][1], Vector3((i - 2.5) * 0.9, 0, 0), 0.0)
	_frame(Vector3(0, 1.45, 0), 6.0, 68.0, 0.0, -14.0)
	await _capture("lineup_gameplay")
	get_tree().quit()
