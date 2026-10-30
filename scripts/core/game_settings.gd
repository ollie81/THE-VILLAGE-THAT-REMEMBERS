extends Node
## Persistent player settings (graphics quality, controls).
## Quality presets are tuned for affordable Android devices first.

signal settings_changed

enum Quality { LOW, MEDIUM, HIGH }
enum TouchMode { AUTO, ALWAYS, NEVER }

const SETTINGS_PATH := "user://settings.cfg"

var quality: int = Quality.MEDIUM
var touch_mode: int = TouchMode.AUTO
var camera_sensitivity: float = 1.0
var show_fps: bool = false


func _ready() -> void:
	if not _load():
		quality = Quality.MEDIUM if OS.has_feature("mobile") else Quality.HIGH
	apply()


# --- Quality-dependent values -------------------------------------------------

func shadows_enabled() -> bool:
	return quality != Quality.LOW


func shadow_distance() -> float:
	return [0.0, 45.0, 70.0][quality]


func shadow_atlas_size() -> int:
	return [1024, 2048, 4096][quality]


func grass_density() -> float:
	return [0.3, 0.65, 1.0][quality]


## Distance after which small details (grass, flowers, pebbles) are culled.
func detail_view_distance() -> float:
	return [30.0, 45.0, 65.0][quality]


func render_scale() -> float:
	return [0.75, 0.9, 1.0][quality]


func glow_enabled() -> bool:
	return quality == Quality.HIGH


func msaa() -> int:
	return [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][quality]


func touch_controls_visible() -> bool:
	match touch_mode:
		TouchMode.ALWAYS:
			return true
		TouchMode.NEVER:
			return false
	return DisplayServer.is_touchscreen_available()


func quality_name() -> String:
	return ["Low", "Medium", "High"][quality]


# --- Mutation -----------------------------------------------------------------

func set_quality(value: int) -> void:
	quality = clampi(value, Quality.LOW, Quality.HIGH)
	apply()
	save()


func set_touch_mode(value: int) -> void:
	touch_mode = clampi(value, TouchMode.AUTO, TouchMode.NEVER)
	settings_changed.emit()
	save()


func set_camera_sensitivity(value: float) -> void:
	camera_sensitivity = clampf(value, 0.25, 3.0)
	settings_changed.emit()
	save()


func set_show_fps(value: bool) -> void:
	show_fps = value
	settings_changed.emit()
	save()


## Applies viewport-level settings. Scene nodes (lights, grass, environment)
## listen to settings_changed and update themselves.
func apply() -> void:
	var viewport := get_viewport()
	if viewport:
		viewport.scaling_3d_scale = render_scale()
		viewport.msaa_3d = msaa()
	RenderingServer.directional_shadow_atlas_set_size(shadow_atlas_size(), true)
	Engine.max_fps = 60
	settings_changed.emit()


# --- Persistence --------------------------------------------------------------

func save() -> void:
	var config := ConfigFile.new()
	config.set_value("graphics", "quality", quality)
	config.set_value("graphics", "show_fps", show_fps)
	config.set_value("controls", "touch_mode", touch_mode)
	config.set_value("controls", "camera_sensitivity", camera_sensitivity)
	config.save(SETTINGS_PATH)


func _load() -> bool:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return false
	quality = int(config.get_value("graphics", "quality", Quality.MEDIUM))
	show_fps = bool(config.get_value("graphics", "show_fps", false))
	touch_mode = int(config.get_value("controls", "touch_mode", TouchMode.AUTO))
	camera_sensitivity = float(config.get_value("controls", "camera_sensitivity", 1.0))
	return true
