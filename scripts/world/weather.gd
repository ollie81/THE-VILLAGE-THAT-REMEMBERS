class_name Weather
extends Node3D
## The weather: clear, cloudy or rain, changing every few hours of the day.
## Rain falls round the camera, the sky greys and dims, the ground darkens
## and shines, the wind picks up in the grass and the trees, and you hear it.
## Animals shelter (see Animal). Saved with the game.

static var instance: Weather

## How grey the sky is for each kind of weather.
const OVERCAST: Array[float] = [0.0, 0.55, 0.9]

enum Kind { CLEAR, CLOUDY, RAIN }
const NAMES := ["clear", "cloudy", "rain"]
## Hours each spell lasts.
const MIN_SPELL := 2.0
const MAX_SPELL := 6.0
## Hours of fine weather a new world starts with.
const FIRST_SPELL := 12.0
## How often each kind comes up.
const CHANCES := [0.55, 0.27, 0.18]

var kind: int = Kind.CLEAR
## In-game hour (counting days) when the current weather changes.
var until: float = 0.0
## 0..1 how far the change toward the current weather has gone.
var _blend: float = 1.0
var _overcast: float = 0.0
var _wet: float = 0.0
var _rain: CPUParticles3D
var _sound: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	name = "Weather"
	instance = self
	_rng.seed = 911 + WorldClock.day
	_rain = CPUParticles3D.new()
	_rain.name = "Rain"
	_rain.amount = 500 if GameSettings.quality_name() != "Low" else 220
	_rain.lifetime = 1.0
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(14, 0.5, 14)
	_rain.direction = Vector3(0.15, -1, 0.05)
	_rain.spread = 4.0
	_rain.initial_velocity_min = 14.0
	_rain.initial_velocity_max = 17.0
	_rain.gravity = Vector3(0, -9.8, 0)
	var drop := QuadMesh.new()
	drop.size = Vector2(0.025, 0.45)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.75, 0.82, 0.92, 0.45)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	drop.material = material
	_rain.mesh = drop
	_rain.emitting = false
	add_child(_rain)
	_sound = AudioStreamPlayer.new()
	_sound.bus = Sounds.BUS_AMBIENCE
	_sound.stream = SoundBank.rain()
	_sound.volume_db = -60.0
	add_child(_sound)
	if until <= 0.0:
		# A new world starts on a fine day; saved weather replaces this.
		set_weather(Kind.CLEAR, FIRST_SPELL, true)


func _exit_tree() -> void:
	if instance == self:
		instance = null
	DayNightCycle.overcast = 0.0


func now_hours() -> float:
	return WorldClock.day * 24.0 + WorldClock.time_of_day


func is_raining() -> bool:
	return kind == Kind.RAIN


func describe() -> String:
	return NAMES[kind]


## Sets the weather now (tests, and the start of a new spell).
func set_weather(new_kind: int, hours: float = 4.0, instant: bool = false) -> void:
	kind = new_kind
	until = now_hours() + hours
	_blend = 1.0 if instant else 0.0
	if instant:
		_overcast = OVERCAST[kind]
		_wet = 1.0 if kind == Kind.RAIN else 0.0
		_apply(0.0, 1.0)


func _next_spell() -> void:
	var roll := _rng.randf()
	var pick := Kind.CLEAR
	if roll > CHANCES[0]:
		pick = Kind.CLOUDY if roll < CHANCES[0] + CHANCES[1] else Kind.RAIN
	set_weather(pick, _rng.randf_range(MIN_SPELL, MAX_SPELL))


func _process(delta: float) -> void:
	if now_hours() >= until:
		_next_spell()
	_blend = minf(_blend + delta / 6.0, 1.0)
	_apply(delta, _blend)
	var camera := get_viewport().get_camera_3d()
	if camera:
		_rain.global_position = camera.global_position + Vector3(0, 9, 0) - camera.global_transform.basis.z * 6.0


func _apply(delta: float, _progress: float) -> void:
	var want_overcast: float = OVERCAST[kind]
	var want_wet := 1.0 if kind == Kind.RAIN else 0.0
	var indoor := Interiors.instance != null and Interiors.instance.is_inside()
	_overcast = move_toward(_overcast, want_overcast, delta * 0.15)
	# Ground soaks quickly in rain and dries slowly after.
	_wet = move_toward(_wet, want_wet, delta * (0.12 if want_wet > _wet else 0.03))
	DayNightCycle.overcast = _overcast
	Materials.ground().set_shader_parameter("wetness", _wet)
	Materials.set_wind(1.0 + _overcast * 1.2)
	_rain.emitting = kind == Kind.RAIN and not indoor
	var volume := -60.0 if kind != Kind.RAIN else (-24.0 if indoor else -9.0)
	_sound.volume_db = move_toward(_sound.volume_db, volume, delta * 20.0)
	if _sound.volume_db > -55.0 and not _sound.playing:
		_sound.play()
	elif _sound.volume_db <= -59.0 and _sound.playing:
		_sound.stop()


func to_dict() -> Dictionary:
	return {"kind": kind, "until": until}


func from_dict(data: Dictionary) -> void:
	if data.is_empty():
		return
	kind = clampi(int(data.get("kind", 0)), 0, 2)
	until = float(data.get("until", 0.0))
	_blend = 1.0
	_overcast = OVERCAST[kind]
	_wet = 1.0 if kind == Kind.RAIN else 0.0
	_apply(0.0, 1.0)
