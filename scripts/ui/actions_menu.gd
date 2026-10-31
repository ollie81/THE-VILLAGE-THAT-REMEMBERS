class_name ActionsMenu
extends Control
## Things the player can do anywhere: wave, bow, cheer, dance, sit down and
## lie down (at night: sleep until morning). Opened with the Actions button
## or F; villagers nearby react to what you do.

const ENTRIES := [
	["Wave", &"wave"], ["Bow", &"bow"], ["Cheer", &"cheer"],
	["Dance", &"dance"], ["Sit down", &"sit"], ["Lie down", &"sleep"],
]

var _button: Button
var _menu: PanelContainer
var _buttons: Array[Button] = []


func _ready() -> void:
	name = "ActionsMenu"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_button = UiTheme.button("Actions", 120)
	_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_button.offset_top = 152
	_button.offset_right = -20
	_button.offset_left = -140
	_button.pressed.connect(toggle)
	add_child(_button)

	_menu = PanelContainer.new()
	_menu.visible = false
	_menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	_menu.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_menu.grow_vertical = Control.GROW_DIRECTION_BOTH
	_menu.offset_right = -160
	add_child(_menu)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_menu.add_child(grid)
	for entry in ENTRIES:
		var b := UiTheme.button(String(entry[0]), 170)
		b.custom_minimum_size.y = 64
		b.pressed.connect(do.bind(StringName(entry[1])))
		grid.add_child(b)
		_buttons.append(b)


func is_open() -> bool:
	return _menu.visible


func toggle() -> void:
	_menu.visible = not _menu.visible
	if _menu.visible:
		_buttons[5].text = "Sleep" if PlayerController.is_night() else "Lie down"


## Does an action (also used by tests).
func do(action: StringName) -> void:
	_menu.visible = false
	var player = GameManager.player
	if player == null or GameManager.is_in_conversation():
		return
	match action:
		&"sit":
			player.sit()
		&"sleep":
			player.lie_down()
			if PlayerController.is_night():
				GameManager.notify("You lie down under the stars and close your eyes...")
		_:
			player.emote(action)


func _process(_delta: float) -> void:
	var exploring := GameManager.camera_mode == GameManager.CameraMode.EXPLORATION
	var placing := BuildMode.instance != null and BuildMode.instance.active
	_button.visible = exploring and not GameManager.is_in_conversation() and not placing
	if not _button.visible:
		_menu.visible = false


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.physical_keycode == KEY_F and _button.visible:
		toggle()
		get_viewport().set_input_as_handled()
