class_name DayNightCycle
extends Node3D
## Drives sun/moon light, the sky shader, ambient light, fog, window glow and
## night lamps from WorldClock.time_of_day.
## Only one directional light exists: it is the sun by day and the moon by
## night, which keeps the shadow cost constant on mobile.

## Colour keyframes: [hour, sky_top, sky_horizon, light_color, ambient, fog].
const KEYFRAMES := [
	[0.0, Color(0.02, 0.03, 0.08), Color(0.06, 0.08, 0.16), Color(0.55, 0.65, 0.95), Color(0.2, 0.25, 0.42), Color(0.05, 0.07, 0.12)],
	[4.8, Color(0.04, 0.05, 0.13), Color(0.12, 0.12, 0.22), Color(0.55, 0.65, 0.95), Color(0.22, 0.25, 0.4), Color(0.08, 0.09, 0.15)],
	[6.0, Color(0.22, 0.32, 0.55), Color(0.95, 0.58, 0.4), Color(1.0, 0.6, 0.38), Color(0.5, 0.42, 0.45), Color(0.62, 0.5, 0.48)],
	[8.0, Color(0.24, 0.47, 0.82), Color(0.72, 0.82, 0.9), Color(1.0, 0.92, 0.8), Color(0.55, 0.6, 0.68), Color(0.68, 0.76, 0.84)],
	[13.0, Color(0.2, 0.45, 0.85), Color(0.66, 0.8, 0.94), Color(1.0, 0.97, 0.9), Color(0.58, 0.63, 0.7), Color(0.68, 0.78, 0.88)],
	[17.0, Color(0.24, 0.43, 0.78), Color(0.88, 0.8, 0.68), Color(1.0, 0.86, 0.66), Color(0.56, 0.55, 0.58), Color(0.78, 0.72, 0.66)],
	[18.9, Color(0.24, 0.27, 0.52), Color(1.0, 0.5, 0.3), Color(1.0, 0.5, 0.28), Color(0.5, 0.38, 0.4), Color(0.7, 0.45, 0.38)],
	[20.2, Color(0.06, 0.07, 0.18), Color(0.28, 0.16, 0.24), Color(0.55, 0.65, 0.95), Color(0.25, 0.24, 0.38), Color(0.12, 0.1, 0.16)],
	[21.5, Color(0.02, 0.03, 0.08), Color(0.06, 0.08, 0.16), Color(0.55, 0.65, 0.95), Color(0.2, 0.25, 0.42), Color(0.05, 0.07, 0.12)],
	[24.0, Color(0.02, 0.03, 0.08), Color(0.06, 0.08, 0.16), Color(0.55, 0.65, 0.95), Color(0.2, 0.25, 0.42), Color(0.05, 0.07, 0.12)],
]

const SUNRISE := 6.0
const SUNSET := 18.8
const ENVIRONMENT_UPDATE_INTERVAL := 0.1

var sun: DirectionalLight3D
var environment: Environment
var sky_material: ShaderMaterial

## 0 in full daylight, 1 in deep night. Other systems may read this.
var night_factor: float = 0.0

var _env_timer: float = 0.0


func _ready() -> void:
	name = "DayNightCycle"
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_blend_splits = false
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.light_angular_distance = 0.5
	add_child(sun)

	sky_material = ShaderMaterial.new()
	sky_material.shader = load("res://shaders/sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_32

	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	# Flat ambient colour + no sky reflections: cheap and predictable on mobile.
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.0
	environment.fog_enabled = true
	environment.fog_density = 0.006
	environment.fog_sky_affect = 0.25
	environment.fog_aerial_perspective = 0.0
	environment.glow_intensity = 0.5
	environment.glow_bloom = 0.04
	environment.glow_hdr_threshold = 1.1
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.08
	environment.adjustment_contrast = 1.04

	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment
	add_child(world_environment)

	GameSettings.settings_changed.connect(_apply_quality)
	_apply_quality()
	_update_light()
	_update_environment()


func _process(delta: float) -> void:
	_update_light()
	_env_timer += delta
	if _env_timer >= ENVIRONMENT_UPDATE_INTERVAL:
		_env_timer = 0.0
		_update_environment()


func _apply_quality() -> void:
	sun.shadow_enabled = GameSettings.shadows_enabled()
	sun.directional_shadow_max_distance = GameSettings.shadow_distance()
	environment.glow_enabled = GameSettings.glow_enabled()


## Direction pointing from the ground toward the sun.
static func sun_direction_for(hour: float) -> Vector3:
	var day_progress := (hour - SUNRISE) / (SUNSET - SUNRISE)
	var angle := day_progress * PI
	return Vector3(cos(angle), sin(angle), 0.35).normalized()


func _update_light() -> void:
	var hour := WorldClock.time_of_day
	var sun_dir := sun_direction_for(hour)
	var moon_dir := -sun_dir
	var sun_strength := smoothstep(-0.04, 0.22, sun_dir.y)
	var moon_strength := smoothstep(0.02, 0.3, moon_dir.y)
	night_factor = 1.0 - smoothstep(-0.12, 0.12, sun_dir.y)

	var light_dir := sun_dir if sun_dir.y > -0.02 else moon_dir
	sun.transform = Transform3D(Basis.looking_at(-light_dir, Vector3.UP), Vector3.ZERO)
	var colors := _sample_keyframes(hour)
	sun.light_color = colors[2]
	if sun_dir.y > -0.02:
		sun.light_energy = sun_strength * 1.25
		_set_shadows(GameSettings.shadows_enabled() and sun_strength > 0.05)
	else:
		sun.light_energy = moon_strength * 0.3
		# Moonlight is dim; skipping its shadows saves a full shadow pass.
		_set_shadows(false)


func _set_shadows(enabled: bool) -> void:
	if sun.shadow_enabled != enabled:
		sun.shadow_enabled = enabled


func _update_environment() -> void:
	var hour := WorldClock.time_of_day
	var colors := _sample_keyframes(hour)
	var sun_dir := sun_direction_for(hour)
	sky_material.set_shader_parameter("top_color", colors[0])
	sky_material.set_shader_parameter("horizon_color", colors[1])
	sky_material.set_shader_parameter("ground_color", (colors[4] as Color).darkened(0.4))
	sky_material.set_shader_parameter("sun_color", colors[2])
	sky_material.set_shader_parameter("sun_direction", sun_dir)
	sky_material.set_shader_parameter("moon_direction", -sun_dir)
	sky_material.set_shader_parameter("star_intensity", night_factor)

	environment.ambient_light_color = colors[3]
	environment.ambient_light_energy = lerpf(1.0, 0.55, night_factor)
	environment.fog_light_color = colors[4]
	environment.fog_density = lerpf(0.0055, 0.009, night_factor)

	var glow := Materials.window_glow()
	glow.emission_energy_multiplier = night_factor * 2.4 + smoothstep(16.5, 19.0, hour) * (1.0 - night_factor) * 0.4
	Materials.water().set_shader_parameter("night_factor", night_factor)

	for node in get_tree().get_nodes_in_group("night_lights"):
		var light := node as OmniLight3D
		if light == null:
			continue
		var base := float(light.get_meta("base_energy", 1.0))
		var energy := base * night_factor
		if light.has_meta("always_on"):
			energy = base * (0.3 + 0.7 * night_factor)
		light.set_meta("current_energy", energy)
		light.light_energy = energy
		light.visible = energy > 0.02


## Returns [sky_top, sky_horizon, light_color, ambient, fog] for `hour`.
func _sample_keyframes(hour: float) -> Array[Color]:
	for i in KEYFRAMES.size() - 1:
		var a: Array = KEYFRAMES[i]
		var b: Array = KEYFRAMES[i + 1]
		var ha: float = a[0]
		var hb: float = b[0]
		if hour >= ha and hour <= hb:
			var t := smoothstep(0.0, 1.0, (hour - ha) / maxf(hb - ha, 0.001))
			var result: Array[Color] = []
			for k in range(1, 6):
				var ca: Color = a[k]
				var cb: Color = b[k]
				result.append(ca.lerp(cb, t))
			return result
	var fallback: Array[Color] = []
	for k in range(1, 6):
		fallback.append(KEYFRAMES[0][k])
	return fallback
