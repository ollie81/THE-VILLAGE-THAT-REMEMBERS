extends SceneTree
## Build tool: removes models the game never loads (and textures only they
## used) from the working copy before an export, so the APK only carries
## what the game uses. CI runs it on its own checkout (the repository keeps
## every asset), before the tests too, so the tests run on what ships.
##
## A model is kept when its name appears in the code as a quoted name or
## path ("Pine_2", "anim/AL_Standard.fbx"), or it's in a folder whose files
## are chosen by building names (the outfits). A texture is kept when a kept
## model uses it or the code names it.
##
## Run:  godot --headless --path . -s res://tools/strip_unused_assets.gd -- [--apply]
## Without --apply it only lists what it would remove.

## Folders whose models are picked by names built at runtime: keep them all.
const KEEP_DIRS := ["res://assets/quaternius/characters/outfits/", "res://assets/quaternius/animals/"]
const CODE_DIRS := ["res://scripts", "res://scenes", "res://data"]
const MODEL_EXT := ["gltf", "glb", "fbx"]
const IMAGE_EXT := ["png", "jpg", "jpeg", "webp"]

var _code := ""
var _apply := false
var _removed_bytes := 0
var _removed: Array = []


func _init() -> void:
	_apply = "--apply" in OS.get_cmdline_user_args()
	for dir in CODE_DIRS:
		_read_code(dir)
	_code += FileAccess.get_file_as_string("res://project.godot")
	var models := _files("res://assets", MODEL_EXT)
	var kept_models: Array = []
	for path in models:
		if _keep_model(path):
			kept_models.append(path)
		else:
			_remove(path)
	# Textures and buffers the kept models use.
	var used := {}
	for path in kept_models:
		if String(path).get_extension() == "gltf":
			for uri in _gltf_uris(path):
				used[String(path).get_base_dir().path_join(uri).simplify_path()] = true
	for path in _files("res://assets", IMAGE_EXT):
		if used.has(path) or _named_in_code(String(path).get_file().get_basename()) or _named_prefix(String(path).get_file().get_basename()):
			continue
		if _in_keep_dir(path):
			continue
		_remove(path)
	for path in _files("res://assets", ["bin"]):
		if not used.has(path) and not _in_keep_dir(path):
			_remove(path)
	print("%s %d unused files, %.1f MB" % ["Removed" if _apply else "Would remove", _removed.size(), _removed_bytes / 1.0e6])
	quit()


func _read_code(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.get_extension() in ["gd", "tscn", "tres", "cfg"]:
			_code += FileAccess.get_file_as_string(dir.path_join(f)) + "\n"
	for sub in d.get_directories():
		_read_code(dir.path_join(sub))


func _files(dir: String, exts: Array) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.get_extension().to_lower() in exts:
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		out.append_array(_files(dir.path_join(sub), exts))
	return out


func _in_keep_dir(path: String) -> bool:
	for k in KEEP_DIRS:
		if path.begins_with(k):
			return true
	return false


## Named in the code: "Name" or "dir/Name.ext" or "Name.ext".
func _named_in_code(stem: String) -> bool:
	var re := RegEx.create_from_string("[\"/]" + _escape(stem) + "[\".]")
	return re.search(_code) != null


## Textures loaded by building names: "T_Plaster" + "_BaseColor.png".
func _named_prefix(stem: String) -> bool:
	for suffix in ["_BaseColor", "_Normal", "_ORM", "_Roughness", "_Metallic", "_Emissive"]:
		if stem.ends_with(suffix) and _named_in_code(stem.trim_suffix(suffix)):
			return true
	return false


func _keep_model(path: String) -> bool:
	return _in_keep_dir(path) or _named_in_code(String(path).get_file().get_basename())


func _gltf_uris(path: String) -> Array:
	var out: Array = []
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		return out
	for key in ["images", "buffers"]:
		for item in data.get(key, []):
			if item is Dictionary and item.has("uri") and not String(item["uri"]).begins_with("data:"):
				out.append(String(item["uri"]).uri_decode())
	return out


func _remove(path: String) -> void:
	var size := FileAccess.get_file_as_bytes(path).size()
	_removed_bytes += size
	_removed.append(path)
	print("  %s  (%d KB)" % [path, size / 1024])
	if _apply:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if FileAccess.file_exists(path + ".import"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".import"))


static func _escape(s: String) -> String:
	var out := ""
	for c in s:
		out += ("\\" + c) if c in ".^$*+?()[]{}|\\-" else c
	return out
