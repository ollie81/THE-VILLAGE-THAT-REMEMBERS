class_name Hud
extends CanvasLayer
## Builds and owns all on-screen UI.

var _root: Control
var _clock_label: Label
var _period_label: Label
var _camera_button: Button
var _time_button: Button
var _prompt_panel: PanelContainer
var _prompt_label: Label
var _hint_label: Label
var _fps_label: Label
var _settings: SettingsPanel
var _touch: TouchControls
var _hint_time: float = 14.0
var _notice_panel: PanelContainer
var _notice_label: Label
var _notice_time: float = 0.0

## Overheard gossip shows only when the player is close enough to hear.
const GOSSIP_HEARING_DISTANCE := 16.0


func _ready() -> void:
	name = "Hud"
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiTheme.create()
	add_child(_root)

	_touch = TouchControls.new()
	_root.add_child(_touch)
	_build_top_bar()
	_build_prompt()
	_build_hint()
	_build_notice()

	_root.add_child(GameplayPanels.new())
	_root.add_child(PopulationPanel.new())
	var dialogue := DialoguePanel.new()
	dialogue.name = "DialoguePanel"
	_root.add_child(dialogue)
	_root.add_child(VillagerInfoPanel.new())
	_settings = SettingsPanel.new()
	_root.add_child(_settings)

	GameManager.camera_mode_changed.connect(func(_m): _refresh_buttons())
	GameManager.camera_mode_changed.connect(func(_m): _refresh_prompt())
	GameManager.conversation_ended.connect(func(_v): _refresh_prompt())
	GameManager.interaction_focus_changed.connect(_on_focus_changed)
	GameManager.conversation_started.connect(func(_v, _l): _prompt_panel.visible = false)
	WorldClock.time_scale_changed.connect(func(_s): _refresh_buttons())
	GameManager.opinion_changed.connect(_on_opinion_changed)
	GameManager.gossip_shared.connect(_on_gossip_shared)
	GameManager.notice.connect(show_notice)
	_refresh_buttons()


func _build_top_bar() -> void:
	var clock_panel := PanelContainer.new()
	clock_panel.position = Vector2(20, 20)
	clock_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(clock_panel)
	var clock_box := VBoxContainer.new()
	clock_box.add_theme_constant_override("separation", 0)
	clock_panel.add_child(clock_box)
	_clock_label = UiTheme.label("", 28, UiTheme.ACCENT)
	clock_box.add_child(_clock_label)
	_period_label = UiTheme.label("", 18, UiTheme.MUTED)
	clock_box.add_child(_period_label)

	_fps_label = UiTheme.label("", 18, UiTheme.MUTED)
	_fps_label.position = Vector2(380, 24)
	_root.add_child(_fps_label)

	var buttons := HBoxContainer.new()
	buttons.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	buttons.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	buttons.offset_top = 20
	buttons.offset_right = -20
	buttons.add_theme_constant_override("separation", 10)
	_root.add_child(buttons)
	_camera_button = UiTheme.button("", 190)
	_camera_button.pressed.connect(GameManager.toggle_camera_mode)
	buttons.add_child(_camera_button)
	_time_button = UiTheme.button("", 120)
	_time_button.pressed.connect(WorldClock.cycle_time_scale)
	buttons.add_child(_time_button)
	var settings_button := UiTheme.button("Menu", 110)
	settings_button.pressed.connect(_toggle_settings)
	buttons.add_child(settings_button)


func _build_prompt() -> void:
	_prompt_panel = PanelContainer.new()
	_prompt_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_prompt_panel.offset_bottom = -150
	_prompt_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_panel.visible = false
	_root.add_child(_prompt_panel)
	_prompt_label = UiTheme.label("", 24)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_panel.add_child(_prompt_label)


func _build_hint() -> void:
	_hint_label = UiTheme.label("", 18, UiTheme.TEXT)
	_hint_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_hint_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint_label.offset_top = 100
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_hint_label.add_theme_constant_override("outline_size", 6)
	if GameSettings.touch_controls_visible():
		_hint_label.text = "Left stick to walk (push fully to run) · drag right side to look · walk up to a villager and tap Talk"
	else:
		_hint_label.text = "WASD walk · Shift run · Space jump · Right-drag look · E talk · Tab village view · T speed up time"
	_root.add_child(_hint_label)


func _build_notice() -> void:
	_notice_panel = PanelContainer.new()
	_notice_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_notice_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_notice_panel.offset_top = 130
	_notice_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice_panel.visible = false
	_root.add_child(_notice_panel)
	_notice_label = UiTheme.label("", 22, UiTheme.ACCENT)
	_notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice_panel.add_child(_notice_label)


## Small message near the top of the screen that fades after a few seconds.
func show_notice(text: String) -> void:
	_notice_label.text = text
	_notice_panel.visible = true
	_notice_panel.modulate.a = 1.0
	_notice_time = 4.0 + text.length() * 0.03


func _on_opinion_changed(villager, affection: float, _trust: float) -> void:
	var villager_name: String = villager.data.display_name
	if affection >= 8.0:
		show_notice("%s will remember that kindly." % villager_name)
	elif affection <= -8.0:
		show_notice("%s will remember that." % villager_name)


func _on_gossip_shared(speaker, listener, _story: String) -> void:
	var player = GameManager.player
	if player == null or speaker.global_position.distance_to(player.global_position) > GOSSIP_HEARING_DISTANCE:
		return
	show_notice("%s is telling %s about you..." % [speaker.data.display_name, listener.data.display_name])


func _process(delta: float) -> void:
	# Keep live prompts ("Build house (2/6)") up to date.
	if _prompt_panel.visible and GameManager.player:
		var focused = GameManager.player.detector.focused
		if focused and is_instance_valid(focused):
			var key_hint := "" if GameSettings.touch_controls_visible() else "  [E]"
			_prompt_label.text = focused.get_prompt() + key_hint
	if _notice_time > 0.0:
		_notice_time -= delta
		_notice_panel.modulate.a = clampf(_notice_time, 0.0, 1.0)
		_notice_panel.visible = _notice_time > 0.0
	_clock_label.text = "Day %d  %s" % [WorldClock.day, WorldClock.get_time_string()]
	_period_label.text = WorldClock.get_period_name()
	_fps_label.visible = GameSettings.show_fps
	if _fps_label.visible:
		_fps_label.text = "%d FPS · %s" % [Engine.get_frames_per_second(), GameSettings.quality_name()]
	if _hint_time > 0.0:
		_hint_time -= delta
		_hint_label.modulate.a = clampf(_hint_time / 2.0, 0.0, 1.0)
		_hint_label.visible = _hint_time > 0.0


func _refresh_buttons() -> void:
	var exploring := GameManager.camera_mode == GameManager.CameraMode.EXPLORATION
	_camera_button.text = "Village View" if exploring else "Explore"
	_time_button.text = "Time x%d" % int(WorldClock.time_scale)
	if not exploring:
		_prompt_panel.visible = false
	_touch.queue_redraw()


func _on_focus_changed(target) -> void:
	var exploring := GameManager.camera_mode == GameManager.CameraMode.EXPLORATION
	if target == null or not exploring or GameManager.is_in_conversation():
		_prompt_panel.visible = false
		return
	var key_hint := "" if GameSettings.touch_controls_visible() else "  [E]"
	_prompt_label.text = target.get_prompt() + key_hint
	_prompt_panel.visible = true


## Re-shows the prompt for whatever the player is standing next to.
func _refresh_prompt() -> void:
	var player = GameManager.player
	if player and is_instance_valid(player):
		_on_focus_changed(player.detector.focused)


func _toggle_settings() -> void:
	_settings.visible = not _settings.visible


func _unhandled_input(event: InputEvent) -> void:
	var building := BuildMode.instance != null and BuildMode.instance.active
	if event.is_action_pressed("menu") and not GameManager.is_in_conversation() and not building:
		_toggle_settings()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("time_fast_forward"):
		WorldClock.cycle_time_scale()
		get_viewport().set_input_as_handled()
