class_name SettingsPanel
extends PanelContainer
## Graphics and control settings. Changes save immediately.

var _quality_buttons: Array[Button] = []
var _touch_buttons: Array[Button] = []
var _year_buttons: Array[Button] = []
var _voice_buttons: Array[Button] = []
## Game days per village year for the "Years pass" choices.
const YEAR_CHOICES: Array[int] = [30, 10, 4]
var _sensitivity: HSlider
var _fps_toggle: CheckButton


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	custom_minimum_size = Vector2(640, 0)

	# Scrolls on short (landscape phone) screens; the buttons stay at the bottom.
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(620, 520)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 12)
	scroll.add_child(box)
	add_child(outer)
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

	for bus in [Sounds.BUS_MUSIC, Sounds.BUS_EFFECTS, Sounds.BUS_AMBIENCE]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		box.add_child(row)
		var name_label := UiTheme.label({Sounds.BUS_MUSIC: "Music", Sounds.BUS_EFFECTS: "Sound effects", Sounds.BUS_AMBIENCE: "Birds, wind and fire"}[bus])
		name_label.custom_minimum_size = Vector2(240, 0)
		row.add_child(name_label)
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.value = float(Sounds.volumes[bus])
		slider.custom_minimum_size = Vector2(330, 40)
		slider.value_changed.connect(func(v): Sounds.set_volume(bus, v))
		row.add_child(slider)

	box.add_child(UiTheme.label("Voices"))
	var voice_row := HBoxContainer.new()
	box.add_child(voice_row)
	for i in Voices.MODE_NAMES.size():
		var b := UiTheme.button(Voices.MODE_NAMES[i], 150)
		b.toggle_mode = true
		b.pressed.connect(func():
			Voices.set_mode(i)
			_sync())
		voice_row.add_child(b)
		_voice_buttons.append(b)
	var voice_hint := Voices.voices_summary() + " More voices: phone Settings → Text-to-speech → Install voice data." \
		if Voices.has_speech() else "This device has no text-to-speech voices installed, so Spoken falls back to Babble."
	var hint_label := UiTheme.label(voice_hint, 16, UiTheme.MUTED)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.custom_minimum_size = Vector2(600, 0)
	box.add_child(hint_label)
	var test := UiTheme.button("Test voices", 220)
	test.pressed.connect(Voices.test_voices)
	box.add_child(test)

	box.add_child(UiTheme.label("Years pass"))
	var year_row := HBoxContainer.new()
	box.add_child(year_row)
	for i in YEAR_CHOICES.size():
		var b := UiTheme.button(["Slowly", "Normally", "Quickly"][i], 150)
		b.toggle_mode = true
		b.pressed.connect(func():
			Population.set_year_days(YEAR_CHOICES[i])
			_sync())
		year_row.add_child(b)
		_year_buttons.append(b)
	box.add_child(UiTheme.label("A village year is 30, 10 or 4 days. Faster means more generations.", 16, UiTheme.MUTED))

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
	outer.add_child(actions)
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
	for i in _voice_buttons.size():
		_voice_buttons[i].set_pressed_no_signal(i == Voices.mode)
	for i in _year_buttons.size():
		_year_buttons[i].set_pressed_no_signal(YEAR_CHOICES[i] == Person.year_days)
	_sensitivity.set_value_no_signal(GameSettings.camera_sensitivity)
	_fps_toggle.set_pressed_no_signal(GameSettings.show_fps)


func _reset_world() -> void:
	SaveService.delete_save()
	WorldClock.day = 1
	WorldClock.set_time(7.5)
	GameManager.reset()
	get_tree().reload_current_scene()
