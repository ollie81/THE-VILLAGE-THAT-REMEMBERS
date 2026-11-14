class_name Materials
extends RefCounted
## Shared material library. Re-using the same few materials lets the renderer
## batch state changes and keeps shader compilation (a big mobile stutter
## source) to a minimum.

static var _cache: Dictionary = {}
static var _ground: ShaderMaterial
static var _cobble: StandardMaterial3D


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


## The textured ground (grass, path dirt, cobblestones; Poly Haven, CC0).
static func ground() -> ShaderMaterial:
	if _ground == null:
		_ground = ShaderMaterial.new()
		_ground.shader = load("res://shaders/terrain.gdshader")
		var dir := "res://assets/polyhaven/"
		_ground.set_shader_parameter("grass_albedo", load(dir + "aerial_grass_rock_diff_1k.jpg"))
		_ground.set_shader_parameter("grass_normal", load(dir + "aerial_grass_rock_nor_gl_1k.jpg"))
		_ground.set_shader_parameter("dirt_albedo", load(dir + "brown_mud_leaves_01_diff_1k.jpg"))
		_ground.set_shader_parameter("dirt_normal", load(dir + "brown_mud_leaves_01_nor_gl_1k.jpg"))
		_ground.set_shader_parameter("cobble_albedo", load(dir + "cobblestone_floor_01_diff_1k.jpg"))
		_ground.set_shader_parameter("cobble_normal", load(dir + "cobblestone_floor_01_nor_gl_1k.jpg"))
	return _ground


## Cobblestones for raised paved surfaces (the meeting circle).
static func cobblestone() -> StandardMaterial3D:
	if _cobble == null:
		_cobble = StandardMaterial3D.new()
		var dir := "res://assets/polyhaven/"
		_cobble.albedo_texture = load(dir + "cobblestone_floor_01_diff_1k.jpg")
		_cobble.normal_enabled = true
		_cobble.normal_texture = load(dir + "cobblestone_floor_01_nor_gl_1k.jpg")
		_cobble.roughness_texture = load(dir + "cobblestone_floor_01_rough_1k.jpg")
		_cobble.uv1_triplanar = true
		_cobble.uv1_world_triplanar = true
		_cobble.uv1_scale = Vector3.ONE * 0.32
		_cobble.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return _cobble


## Swaying, cut-out leaves for a tree texture (shared per texture, so the
## weather can change the wind on all of them).
static var foliage_materials: Dictionary = {}

static func foliage(texture: Texture2D, tint: Color = Color.WHITE) -> ShaderMaterial:
	var key := "%s|%s" % [texture.resource_path if texture else "", tint.to_html()]
	if not foliage_materials.has(key):
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/foliage.gdshader")
		m.set_shader_parameter("albedo_tex", texture)
		m.set_shader_parameter("albedo_color", tint)
		foliage_materials[key] = m
	return foliage_materials[key]


## Sets the wind on grass and leaves (0 calm, 1 normal, 2+ stormy).
static func set_wind(amount: float) -> void:
	grass().set_shader_parameter("wind_strength", 0.12 * amount)
	grass().set_shader_parameter("wind_speed", 1.6 + 0.6 * maxf(amount - 1.0, 0.0))
	for m: ShaderMaterial in foliage_materials.values():
		m.set_shader_parameter("wind_strength", 0.012 * amount)
		m.set_shader_parameter("wind_speed", 1.3 + 0.5 * maxf(amount - 1.0, 0.0))


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
