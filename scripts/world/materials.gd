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
		material.metallic_specular = 0.25
		_cache["vertex_color"] = material
	return _cache["vertex_color"]


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
