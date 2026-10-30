class_name SettingsPanel
extends PanelContainer
## Graphics and control settings. Changes save immediately.

var _quality_buttons: Array[Button] = []
var _touch_buttons: Array[Button] = []
var _sensitivity: HSlider
var _fps_toggle: CheckButton


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	custom_minimum_size = Vector2(560, 0)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	box.add_child(UiTheme.label("Settings", 32, UiTheme.ACCENT))

	box.add_child(UiTheme.label("Graphics quality"))
	var quality_row := HBoxContainer.new()
	box.add_child(quality_row)
	for i in 3:
		var b := UiTheme.button(["Low", "Medium", "High"][i], 150)
		b.toggle_mode = true
		b.pressed.connect(GameSettings.set_quality.bind(i))
		quality_row.add_child(b)
		_quality_buttons.append(b)
	box.add_child(UiTheme.label("Shadows, resolution and glow apply now. Grass density applies on next launch.", 16, UiTheme.MUTED))

	box.add_child(UiTheme.label("On-screen touch controls"))
	var touch_row := HBoxContainer.new()
	box.add_child(touch_row)
	for i in 3:
		var b := UiTheme.button(["Auto", "On", "Off"][i], 150)
		b.toggle_mode = true
		b.pressed.connect(GameSettings.set_touch_mode.bind(i))
		touch_row.add_child(b)
		_touch_buttons.append(b)

	box.add_child(UiTheme.label("Camera sensitivity"))
	_sensitivity = HSlider.new()
	_sensitivity.min_value = 0.25
	_sensitivity.max_value = 3.0
	_sensitivity.step = 0.05
	_sensitivity.custom_minimum_size = Vector2(0, 40)
	_sensitivity.value_changed.connect(GameSettings.set_camera_sensitivity)
	box.add_child(_sensitivity)

	_fps_toggle = CheckButton.new()
	_fps_toggle.text = "Show FPS"
	_fps_toggle.focus_mode = Control.FOCUS_NONE
	_fps_toggle.toggled.connect(GameSettings.set_show_fps)
	box.add_child(_fps_toggle)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	box.add_child(actions)
	var save := UiTheme.button("Save now", 160)
	save.pressed.connect(SaveService.save_game)
	actions.add_child(save)
	var reset := UiTheme.button("Forget everything", 220)
	reset.tooltip_text = "Deletes the save: the villagers will forget you."
	reset.pressed.connect(_reset_world)
	actions.add_child(reset)
	var close := UiTheme.button("Close", 120)
	close.pressed.connect(func(): visible = false)
	actions.add_child(close)

	GameSettings.settings_changed.connect(_sync)
	_sync()


func _sync() -> void:
	for i in _quality_buttons.size():
		_quality_buttons[i].set_pressed_no_signal(i == GameSettings.quality)
	for i in _touch_buttons.size():
		_touch_buttons[i].set_pressed_no_signal(i == GameSettings.touch_mode)
	_sensitivity.set_value_no_signal(GameSettings.camera_sensitivity)
	_fps_toggle.set_pressed_no_signal(GameSettings.show_fps)


func _reset_world() -> void:
	SaveService.delete_save()
	WorldClock.day = 1
	WorldClock.set_time(7.5)
	GameManager.reset()
	get_tree().reload_current_scene()
