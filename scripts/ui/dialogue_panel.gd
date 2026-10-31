class_name DialoguePanel
extends PanelContainer
## Shows a conversation line by line with a typewriter effect, then the
## player's possible answers. Tap, click, E, Space or Continue advances;
## answers are buttons (or keys 1-3).

const CHARACTERS_PER_SECOND := 55.0

var _name_label: Label
var _subtitle_label: Label
var _text_label: Label
var _continue_button: Button
var _conversation: Conversation
var _partner = null
var _typing: bool = false
var _choice_box: VBoxContainer
var _choice_buttons: Array[Button] = []
var _footer: HBoxContainer
var _show_choices_after_typing := false


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
	_choice_box = VBoxContainer.new()
	_choice_box.add_theme_constant_override("separation", 8)
	_choice_box.visible = false
	box.add_child(_choice_box)
	for i in 3:
		var choice := UiTheme.button("", 0)
		choice.alignment = HORIZONTAL_ALIGNMENT_LEFT
		choice.custom_minimum_size = Vector2(720, 58)
		choice.pressed.connect(_choose.bind(i))
		_choice_box.add_child(choice)
		_choice_buttons.append(choice)
	_footer = HBoxContainer.new()
	_footer.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(_footer)
	_continue_button = UiTheme.button("Continue", 180)
	_continue_button.pressed.connect(advance)
	_footer.add_child(_continue_button)

	GameManager.conversation_started.connect(_on_conversation_started)
	GameManager.conversation_ended.connect(func(_v): visible = false)


func _on_conversation_started(villager, conversation) -> void:
	var data: VillagerData = villager.data
	_partner = villager
	_name_label.text = data.display_name
	_subtitle_label.text = "%d · %s" % [data.age, data.role]
	_conversation = conversation
	visible = true
	_choice_box.visible = false
	_footer.visible = true
	advance()


## Lines may start with an expression tag such as "[laughing]".
static func split_expression(line: String) -> Array:
	if line.begins_with("[") and line.find("]") > 1:
		var close := line.find("]")
		return [StringName(line.substr(1, close - 1)), line.substr(close + 1).strip_edges()]
	return [&"", line]


func _show_line(line: String) -> void:
	var parts := split_expression(line)
	_text_label.text = parts[1]
	_text_label.visible_ratio = 0.0
	_typing = true
	if _partner and is_instance_valid(_partner):
		if parts[0] != &"":
			_partner.model.set_expression(parts[0])
		_partner.model.set_talking(true)
	var last := not _conversation.has_lines() and not _conversation.has_choices()
	_continue_button.text = "Goodbye" if last else "Continue"


func _process(delta: float) -> void:
	if not visible or not _typing:
		return
	var length := maxf(_text_label.text.length(), 1.0)
	_text_label.visible_ratio = minf(_text_label.visible_ratio + delta * CHARACTERS_PER_SECOND / length, 1.0)
	if _text_label.visible_ratio >= 1.0:
		_typing = false
		if _partner and is_instance_valid(_partner):
			_partner.model.set_talking(false)
		if _show_choices_after_typing:
			_show_choices()


func advance() -> void:
	if _typing:
		_text_label.visible_ratio = 1.0
		_typing = false
		if _partner and is_instance_valid(_partner):
			_partner.model.set_talking(false)
		if _show_choices_after_typing:
			_show_choices()
		return
	if _choice_box.visible:
		return
	if _conversation.has_lines():
		_show_line(_conversation.next_line())
		if _conversation.has_choices():
			_show_choices_after_typing = true
	elif _conversation.has_choices():
		_show_choices()
	else:
		visible = false
		GameManager.end_conversation()


func _show_choices() -> void:
	_show_choices_after_typing = false
	var texts := _conversation.choice_texts()
	for i in _choice_buttons.size():
		_choice_buttons[i].visible = i < texts.size()
		if i < texts.size():
			_choice_buttons[i].text = "%d.  %s" % [i + 1, texts[i]]
	_choice_box.visible = true
	_footer.visible = false


func _choose(index: int) -> void:
	if not _choice_box.visible or index >= _conversation.choices.size():
		return
	_conversation.choose(index)
	_choice_box.visible = false
	_footer.visible = true
	advance()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	if _choice_box.visible and key and key.pressed and not key.echo \
			and key.physical_keycode >= KEY_1 and key.physical_keycode <= KEY_3:
		_choose(key.physical_keycode - KEY_1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") or event.is_action_pressed("jump"):
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
