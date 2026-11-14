class_name StructureIcons
extends Node
## Little pictures of each buildable for the Build menu, rendered once from
## the real 3D models (each in its own tiny world with its own light and
## camera), then kept. Rendering happens only when the menu first opens.

const SIZE := 96

static var instance: StructureIcons
var _icons: Dictionary = {}  # type -> ViewportTexture


func _ready() -> void:
	name = "StructureIcons"
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


## The picture of `type` (made the first time it's asked for).
func icon(type: StringName) -> Texture2D:
	if not _icons.has(type):
		_icons[type] = _render(type)
	return _icons[type]


func _render(type: StringName) -> Texture2D:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(SIZE, SIZE)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	var model: Node3D = StructureCatalog.create_fruit_tree(1.0, true) if type == &"fruit_tree" else StructureCatalog.create_finished(type)
	viewport.add_child(model)
	var radius := maxf(StructureCatalog.radius(type), 0.8)
	var camera := Camera3D.new()
	camera.fov = 40.0
	viewport.add_child(camera)
	camera.position = Vector3(radius * 1.7, radius * 1.4 + 0.6, radius * 2.2)
	camera.look_at(Vector3(0, radius * 0.35, 0), Vector3.UP)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0)
	sun.light_energy = 1.2
	viewport.add_child(sun)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.75, 0.8)
	env.ambient_light_energy = 0.8
	environment.environment = env
	viewport.add_child(environment)
	return viewport.get_texture()
