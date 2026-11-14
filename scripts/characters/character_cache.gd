class_name CharacterCache
extends RefCounted
## Offline cache of generated character meshes. Building a character (body,
## head and its expression blend shapes) takes a noticeable fraction of a
## second, so the result is saved to user:// and reused on later launches.
## The key covers every appearance property and the generator source code,
## so any change to either rebuilds automatically.

const DIRECTORY := "user://character_cache"
## Bump when the generator changes in a way the source hash can't see.
const FORMAT_VERSION := 3
const GENERATOR_SCRIPTS: Array[String] = [
	"res://scripts/characters/humanoid_mesh_builder.gd",
	"res://scripts/characters/skinned_mesh_tool.gd",
	"res://scripts/characters/face_expressions.gd",
	"res://scripts/characters/humanoid_rig.gd",
]

static var enabled: bool = true
static var _generator_hash: String = ""


static func key_for(look: CharacterAppearance) -> String:
	var parts := PackedStringArray([str(FORMAT_VERSION), _get_generator_hash()])
	for property in look.get_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			parts.append("%s=%s" % [property["name"], var_to_str(look.get(property["name"]))])
	return "%x" % hash("|".join(parts))


static func load_mesh(key: String, part: String, material: Material) -> ArrayMesh:
	if not enabled:
		return null
	var path := "%s/%s_%s.res" % [DIRECTORY, key, part]
	if not ResourceLoader.exists(path):
		return null
	var mesh := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ArrayMesh
	if mesh and mesh.get_surface_count() > 0:
		# Re-link the shared material instead of the saved copy.
		mesh.surface_set_material(0, material)
		return mesh
	return null


static func save_mesh(key: String, part: String, mesh: ArrayMesh) -> void:
	if not enabled or mesh == null:
		return
	DirAccess.make_dir_recursive_absolute(DIRECTORY)
	var error := ResourceSaver.save(mesh, "%s/%s_%s.res" % [DIRECTORY, key, part])
	if error != OK:
		push_warning("Could not cache character mesh (%s)" % error_string(error))


static func clear() -> void:
	var dir := DirAccess.open(DIRECTORY)
	if dir == null:
		return
	for file in dir.get_files():
		dir.remove(file)


static func _get_generator_hash() -> String:
	if _generator_hash == "":
		var sources := PackedStringArray()
		for path in GENERATOR_SCRIPTS:
			sources.append(FileAccess.get_file_as_string(path))
		_generator_hash = "%x" % hash("".join(sources))
	return _generator_hash
