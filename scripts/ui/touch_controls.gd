class_name TouchControls
extends Control
## On-screen controls for phones and tablets, drawn in code (no textures).
## - Exploration: floating joystick on the left half, look by dragging the
##   right half, pinch to zoom, Jump and Talk buttons.
## - Management: drag anywhere to pan, pinch to zoom, tap to select.
## Handles real multi-touch, so you can walk and look at the same time.

const JOYSTICK_RADIUS := 95.0
const BUTTON_RADIUS := 62.0
const LOOK_SCALE := 1.0

var interact_available: bool = false

var _joystick_touch: int = -1
var _joystick_origin: Vector2 = Vector2.ZERO
var _joystick_position: Vector2 = Vector2.ZERO
var _look_touches: Dictionary = {} # index -> position
var _button_touches: Dictionary = {} # index -> action
var _pinch_distance: float = 0.0


func _ready() -> void:
	name = "TouchControls"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameSettings.settings_changed.connect(_update_visibility)
	GameManager.camera_mode_changed.connect(func(_m): _release_all())
	GameManager.interaction_focus_changed.connect(_on_focus_changed)
	GameManager.conversation_started.connect(func(_v, _l): queue_redraw())
	GameManager.conversation_ended.connect(func(_v): queue_redraw())
	_update_visibility()


func _on_focus_changed(target) -> void:
	interact_available = target != null
	queue_redraw()


func _update_visibility() -> void:
	visible = GameSettings.touch_controls_visible()
	if not visible:
		_release_all()


func _exploring() -> bool:
	return GameManager.camera_mode == GameManager.CameraMode.EXPLORATION


func _jump_center() -> Vector2:
	return size - Vector2(120, 130)


func _interact_center() -> Vector2:
	return size - Vector2(270, 110)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		_handle_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_handle_drag(event as InputEventScreenDrag)


func _handle_touch(touch: InputEventScreenTouch) -> void:
	if touch.pressed:
		if _exploring():
			if touch.position.distance_to(_jump_center()) < BUTTON_RADIUS * 1.15:
				_press_button(touch.index, "jump")
				return
			if interact_available and touch.position.distance_to(_interact_center()) < BUTTON_RADIUS * 1.15:
				_press_button(touch.index, "interact")
				return
			if touch.position.x < size.x * 0.42 and _joystick_touch == -1:
				_joystick_touch = touch.index
				_joystick_origin = touch.position
				_joystick_position = touch.position
				queue_redraw()
				return
		_look_touches[touch.index] = touch.position
		_pinch_distance = _current_pinch_distance()
	else:
		if _button_touches.has(touch.index):
			Input.action_release(_button_touches[touch.index])
			_button_touches.erase(touch.index)
			queue_redraw()
		elif touch.index == _joystick_touch:
			_joystick_touch = -1
			InputRouter.touch_move = Vector2.ZERO
			queue_redraw()
		else:
			_look_touches.erase(touch.index)
			_pinch_distance = _current_pinch_distance()


func _handle_drag(drag: InputEventScreenDrag) -> void:
	if drag.index == _joystick_touch:
		_joystick_position = drag.position
		var offset := (_joystick_position - _joystick_origin).limit_length(JOYSTICK_RADIUS)
		InputRouter.touch_move = offset / JOYSTICK_RADIUS
		queue_redraw()
		return
	if not _look_touches.has(drag.index):
		return
	_look_touches[drag.index] = drag.position
	if _look_touches.size() >= 2:
		var distance := _current_pinch_distance()
		InputRouter.add_zoom((distance - _pinch_distance) * 0.02)
		_pinch_distance = distance
	elif _exploring():
		InputRouter.add_look(drag.relative * LOOK_SCALE)
	else:
		InputRouter.add_pan(drag.relative)


func _current_pinch_distance() -> float:
	var points: Array = _look_touches.values()
	if points.size() < 2:
		return 0.0
	var a: Vector2 = points[0]
	var b: Vector2 = points[1]
	return a.distance_to(b)


func _press_button(index: int, action: String) -> void:
	_button_touches[index] = action
	Input.action_press(action)
	queue_redraw()


func _release_all() -> void:
	for index in _button_touches:
		Input.action_release(_button_touches[index])
	_button_touches.clear()
	_look_touches.clear()
	_joystick_touch = -1
	InputRouter.touch_move = Vector2.ZERO
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	if not _exploring() or GameManager.is_in_conversation():
		return
	var base_color := Color(1, 1, 1, 0.12)
	var ring_color := Color(1, 1, 1, 0.35)
	var joystick_center := _joystick_origin if _joystick_touch != -1 else Vector2(170, size.y - 170)
	draw_circle(joystick_center, JOYSTICK_RADIUS, base_color)
	draw_arc(joystick_center, JOYSTICK_RADIUS, 0, TAU, 40, ring_color, 3.0, true)
	var knob := joystick_center
	if _joystick_touch != -1:
		knob = _joystick_origin + (_joystick_position - _joystick_origin).limit_length(JOYSTICK_RADIUS)
	draw_circle(knob, 38, Color(1, 0.95, 0.85, 0.45))

	_draw_button(_jump_center(), "Jump", _button_touches.values().has("jump"))
	if interact_available:
		_draw_button(_interact_center(), "Talk", _button_touches.values().has("interact"))


func _draw_button(center: Vector2, text: String, pressed: bool) -> void:
	draw_circle(center, BUTTON_RADIUS, Color(0.96, 0.78, 0.42, 0.55 if pressed else 0.3))
	draw_arc(center, BUTTON_RADIUS, 0, TAU, 40, Color(1, 1, 1, 0.5), 3.0, true)
	var font := get_theme_default_font()
	var font_size := 24
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	draw_string(font, center + Vector2(-text_size.x * 0.5, font_size * 0.35), text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color(1, 1, 1, 0.9))
