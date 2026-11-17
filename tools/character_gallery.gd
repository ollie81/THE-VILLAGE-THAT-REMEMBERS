extends Node3D
## Developer tool: renders every character side by side from several angles
## and in several animation poses, to review character art without playing.
##
## Run (needs a display or xvfb-run):
##   godot --path . res://tools/character_gallery.tscn -- --out=/some/dir
## Without --out it just shows the lineup and slowly orbits the camera.

const VILLAGER_PATHS: Array[String] = [
	"res://data/villagers/mara.tres",
	"res://data/villagers/elias.tres",
	"res://data/villagers/nia.tres",
	"res://data/villagers/tomas.tres",
	"res://data/villagers/sera.tres",
]
const SPACING := 1.3

## [file name, camera yaw (deg), camera pitch (deg), distance, animation]
const SHOTS := [
	["front", 0.0, -8.0, 6.2, &"idle"],
	["three_quarter", 35.0, -12.0, 6.2, &"idle"],
	["side", 90.0, -6.0, 6.8, &"idle"],
	["back", 180.0, -10.0, 6.2, &"idle"],
	["isometric", 45.0, -52.0, 13.0, &"idle"],
	["walk", 25.0, -10.0, 6.2, &"walk"],
	["run", 25.0, -10.0, 6.2, &"run"],
	["work", 25.0, -10.0, 6.2, &"work"],
	["gather", 25.0, -10.0, 6.2, &"gather"],
	["talk", 10.0, -8.0, 6.2, &"talk"],
	["closeup", 15.0, -4.0, 2.4, &"idle"],
]

var _camera: Camera3D
var _models: Array[CharacterModel] = []
var _orbit: float = 0.0
var _out_dir: String = ""


func _ready() -> void:
	SaveService.enabled = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.substr(6)
	_build_stage()
	var looks: Array[CharacterAppearance] = []
	for path in VILLAGER_PATHS:
		looks.append((load(path) as VillagerData).appearance)
	looks.append(PlayerController.create_default_appearance())
	for i in looks.size():
		var model := CharacterModel.new(looks[i])
		model.position = Vector3((i - (looks.size() - 1) * 0.5) * SPACING, 0, 0)
		add_child(model)
		_models.append(model)
	if _out_dir != "":
		_capture_all.call_deferred()


func _build_stage() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.05
	add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.74, 0.86)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.66, 0.72)
	env.ambient_light_energy = 0.62
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.45, 0.62, 0.35)
	plane.material = ground_material
	ground.mesh = plane
	add_child(ground)
	_camera = Camera3D.new()
	_camera.fov = 40.0
	add_child(_camera)
	_camera.make_current()
	_place_camera(20.0, -10.0, 7.5)


func _place_camera(yaw_deg: float, pitch_deg: float, distance: float) -> void:
	var focus := Vector3(0, 0.9 if distance > 3.0 else 1.45, 0)
	if distance <= 3.0:
		focus.x = _models[0].position.x if not _models.is_empty() else 0.0
	var offset := Basis(Vector3.UP, deg_to_rad(yaw_deg)) * Basis(Vector3.RIGHT, deg_to_rad(pitch_deg)) * Vector3(0, 0, distance)
	_camera.global_transform = Transform3D(Basis.looking_at(-offset, Vector3.UP), focus + offset)


func _process(delta: float) -> void:
	if _out_dir == "":
		_orbit += delta * 15.0
		_place_camera(_orbit, -12.0, 7.5)


func _capture_all() -> void:
	DirAccess.make_dir_recursive_absolute(_out_dir)
	for shot in SHOTS:
		for model in _models:
			model.set_animation(shot[4], 3.0 if shot[4] == &"run" else 1.6)
		_place_camera(shot[1], shot[2], shot[3])
		for i in 45:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path: String = _out_dir.path_join("%s.png" % shot[0])
		get_viewport().get_texture().get_image().save_png(path)
		print("saved ", path)
	get_tree().quit()
