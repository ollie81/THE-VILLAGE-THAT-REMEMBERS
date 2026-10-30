class_name DialoguePanel
extends PanelContainer
## Shows a conversation line by line with a typewriter effect.
## Tap, click, E, Space or the Continue button advances.

const CHARACTERS_PER_SECOND := 55.0

var _name_label: Label
var _subtitle_label: Label
var _text_label: Label
var _continue_button: Button
var _lines: Array[String] = []
var _partner = null
var _index: int = 0
var _typing: bool = false


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	custom_minimum_size = Vector2(760, 200)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_bottom = -24

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	box.add_child(header)
	_name_label = UiTheme.label("", 30, UiTheme.ACCENT)
	header.add_child(_name_label)
	_subtitle_label = UiTheme.label("", 20, UiTheme.MUTED)
	_subtitle_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_subtitle_label)
	_text_label = UiTheme.label("", 24)
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.custom_minimum_size = Vector2(720, 80)
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_text_label)
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(footer)
	_continue_button = UiTheme.button("Continue", 180)
	_continue_button.pressed.connect(advance)
	footer.add_child(_continue_button)

	GameManager.conversation_started.connect(_on_conversation_started)
	GameManager.conversation_ended.connect(func(_v): visible = false)


func _on_conversation_started(villager, lines: Array[String]) -> void:
	var data: VillagerData = villager.data
	_partner = villager
	_name_label.text = data.display_name
	_subtitle_label.text = "%d · %s" % [data.age, data.role]
	_lines = lines
	_index = 0
	visible = true
	_show_line()


## Lines may start with an expression tag such as "[laughing]".
static func split_expression(line: String) -> Array:
	if line.begins_with("[") and line.find("]") > 1:
		var close := line.find("]")
		return [StringName(line.substr(1, close - 1)), line.substr(close + 1).strip_edges()]
	return [&"", line]


func _show_line() -> void:
	var parts := split_expression(_lines[_index])
	_text_label.text = parts[1]
	_text_label.visible_ratio = 0.0
	_typing = true
	if _partner and is_instance_valid(_partner):
		if parts[0] != &"":
			_partner.model.set_expression(parts[0])
		_partner.model.set_talking(true)
	_continue_button.text = "Goodbye" if _index == _lines.size() - 1 else "Continue"


func _process(delta: float) -> void:
	if not visible or not _typing:
		return
	var length := maxf(_text_label.text.length(), 1.0)
	_text_label.visible_ratio = minf(_text_label.visible_ratio + delta * CHARACTERS_PER_SECOND / length, 1.0)
	if _text_label.visible_ratio >= 1.0:
		_typing = false
		if _partner and is_instance_valid(_partner):
			_partner.model.set_talking(false)


func advance() -> void:
	if _typing:
		_text_label.visible_ratio = 1.0
		_typing = false
		return
	_index += 1
	if _index >= _lines.size():
		visible = false
		GameManager.end_conversation()
	else:
		_show_line()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("jump"):
		advance()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu"):
		visible = false
		GameManager.end_conversation()
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		advance()
		accept_event()
