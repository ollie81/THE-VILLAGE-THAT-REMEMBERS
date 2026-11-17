extends Node
## Registers the game's input actions and merges keyboard, gamepad and
## on-screen touch input into one place so gameplay code never needs to know
## which device the player is using.

const DEADZONE := 0.2

## Set by the on-screen joystick (-1..1, y negative = forward).
var touch_move := Vector2.ZERO

var _look_delta := Vector2.ZERO
var _pan_delta := Vector2.ZERO
var _zoom_delta := 0.0


func _ready() -> void:
	_register_default_actions()


func _register_default_actions() -> void:
	_add_keys("move_forward", [KEY_W, KEY_UP])
	_add_keys("move_back", [KEY_S, KEY_DOWN])
	_add_keys("move_left", [KEY_A, KEY_LEFT])
	_add_keys("move_right", [KEY_D, KEY_RIGHT])
	_add_keys("run", [KEY_SHIFT])
	_add_keys("jump", [KEY_SPACE])
	_add_keys("interact", [KEY_E, KEY_ENTER])
	_add_keys("toggle_camera", [KEY_TAB, KEY_C])
	_add_keys("time_fast_forward", [KEY_T])
	_add_keys("menu", [KEY_ESCAPE])
	_add_keys("rotate_camera_left", [KEY_Q])
	_add_keys("rotate_camera_right", [KEY_R])

	_add_joy_axis("move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_add_joy_axis("move_back", JOY_AXIS_LEFT_Y, 1.0)
	_add_joy_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_add_joy_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_add_joy_axis("look_left", JOY_AXIS_RIGHT_X, -1.0)
	_add_joy_axis("look_right", JOY_AXIS_RIGHT_X, 1.0)
	_add_joy_axis("look_up", JOY_AXIS_RIGHT_Y, -1.0)
	_add_joy_axis("look_down", JOY_AXIS_RIGHT_Y, 1.0)
	_add_joy_button("jump", JOY_BUTTON_A)
	_add_joy_button("interact", JOY_BUTTON_X)
	_add_joy_button("run", JOY_BUTTON_LEFT_SHOULDER)
	_add_joy_button("toggle_camera", JOY_BUTTON_Y)
	_add_joy_button("menu", JOY_BUTTON_START)


func _ensure_action(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, DEADZONE)


func _add_keys(action: StringName, keys: Array) -> void:
	_ensure_action(action)
	for key in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(action, event)


func _add_joy_axis(action: StringName, axis: JoyAxis, direction: float) -> void:
	_ensure_action(action)
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = direction
	InputMap.action_add_event(action, event)


func _add_joy_button(action: StringName, button: JoyButton) -> void:
	_ensure_action(action)
	var event := InputEventJoypadButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)


# --- Queries used by gameplay code --------------------------------------------

## Movement intent, x = strafe, y = forward(-)/back(+). Length is 0..1.
func get_move_vector() -> Vector2:
	var keyboard := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if touch_move.length() > keyboard.length():
		return touch_move.limit_length(1.0)
	return keyboard


func is_run_requested(move: Vector2) -> bool:
	# Pushing the touch joystick to its rim also runs.
	return Input.is_action_pressed("run") or touch_move.length() > 0.92 and move.length() > 0.9


## Gamepad right-stick look, in "pixels" so it combines with touch/mouse deltas.
func get_stick_look(delta: float) -> Vector2:
	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	return stick * 700.0 * delta


func add_look(delta: Vector2) -> void:
	_look_delta += delta


func consume_look() -> Vector2:
	var value := _look_delta
	_look_delta = Vector2.ZERO
	return value


func add_pan(delta: Vector2) -> void:
	_pan_delta += delta


func consume_pan() -> Vector2:
	var value := _pan_delta
	_pan_delta = Vector2.ZERO
	return value


## Positive = zoom in.
func add_zoom(amount: float) -> void:
	_zoom_delta += amount


func consume_zoom() -> float:
	var value := _zoom_delta
	_zoom_delta = 0.0
	return value
