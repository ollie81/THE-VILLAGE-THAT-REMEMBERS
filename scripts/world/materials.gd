class_name Materials
extends RefCounted
## Shared material library. Re-using the same few materials lets the renderer
## batch state changes and keeps shader compilation (a big mobile stutter
## source) to a minimum.

static var _cache: Dictionary = {}


## The main material for all merged low-poly geometry.
static func vertex_color() -> StandardMaterial3D:
	if not _cache.has("vertex_color"):
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		# Vertex colours are authored as sRGB Color values.
		material.vertex_color_is_srgb = true
		material.roughness = 0.9
		material.metallic_specular = 0.08
		_cache["vertex_color"] = material
	return _cache["vertex_color"]


## Stylised character shading (see shaders/character_common.gdshaderinc):
## per-surface cloth weave, leather grain, hair strands and skin, with an
## outline pass that GameSettings switches off on Low quality.
static func character_body() -> ShaderMaterial:
	if not _cache.has("character_body"):
		var material := ShaderMaterial.new()
		material.shader = load("res://shaders/character.gdshader")
		material.next_pass = character_outline()
		_cache["character_body"] = material
	return _cache["character_body"]


static func character_face() -> ShaderMaterial:
	if not _cache.has("character_face"):
		var material := ShaderMaterial.new()
		material.shader = load("res://shaders/character_face.gdshader")
		material.next_pass = character_outline()
		_cache["character_face"] = material
	return _cache["character_face"]


static func character_outline() -> ShaderMaterial:
	if not _cache.has("character_outline"):
		var material := ShaderMaterial.new()
		material.shader = load("res://shaders/character_outline.gdshader")
		_cache["character_outline"] = material
	return _cache["character_outline"]


static func set_character_outlines(enabled: bool) -> void:
	var outline: Material = character_outline() if enabled else null
	character_body().next_pass = outline
	character_face().next_pass = outline


## Faces and hair: softer than the world material. Wrapped diffuse lighting
## keeps the shadow side of faces from going muddy, a faint rim light
## separates heads from the background, and low specular avoids plastic skin.
static func skin() -> StandardMaterial3D:
	if not _cache.has("skin"):
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.vertex_color_is_srgb = true
		material.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
		material.roughness = 0.72
		material.metallic_specular = 0.28
		material.rim_enabled = true
		material.rim = 0.22
		material.rim_tint = 0.65
		# Faces never fall into (self-)shadow: no shadow acne on curved skin
		# and expressions stay readable under hat brims and roofs.
		material.disable_receive_shadows = true
		_cache["skin"] = material
	return _cache["skin"]


## Warm glowing windows and lanterns. DayNightCycle drives emission at night.
static func window_glow() -> StandardMaterial3D:
	if not _cache.has("window_glow"):
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.32, 0.27, 0.2)
		material.emission_enabled = true
		material.emission = Color(1.0, 0.72, 0.38)
		material.emission_energy_multiplier = 0.0
		material.roughness = 0.4
		_cache["window_glow"] = material
	return _cache["window_glow"]


static func flame() -> StandardMaterial3D:
	if not _cache.has("flame"):
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(1.0, 0.55, 0.15)
		material.emission_enabled = true
		material.emission = Color(1.0, 0.5, 0.12)
		material.emission_energy_multiplier = 2.0
		_cache["flame"] = material
	return _cache["flame"]


static func grass() -> ShaderMaterial:
	if not _cache.has("grass"):
		var material := ShaderMaterial.new()
		material.shader = load("res://shaders/grass.gdshader")
		_cache["grass"] = material
	return _cache["grass"]


static func water() -> ShaderMaterial:
	if not _cache.has("water"):
		var material := ShaderMaterial.new()
		material.shader = load("res://shaders/water.gdshader")
		_cache["water"] = material
	return _cache["water"]
