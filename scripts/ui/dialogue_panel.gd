class_name DialoguePanel
extends PanelContainer
## A conversation, line by line (typewriter), then the player's turn: pick an
## answer, or type your own message (simple sentences work best: the game
## recognises common kinds of message, see TalkBrain, and says when it
## doesn't understand). Tap, E, Space or Continue advances; End chat leaves
## at any time.
##
## Who's speaking is always clear: the villager's name in gold, "You" in blue
## for what you say, and what you do written as an action in grey. Only the
## speaker's mouth moves; the other one listens.

const CHARACTERS_PER_SECOND := 55.0
## Answers that fit on a landscape phone (more than 5 are drawn smaller).
const MAX_CHOICES := 7
const PLAYER_COLOUR := Color(0.62, 0.82, 1.0)
const ACTION_COLOUR := Color(0.78, 0.76, 0.72)

var _name_label: Label
var _subtitle_label: Label
var _text_label: Label
var _continue_button: Button
var _end_button: Button
var _conversation: Conversation
var _partner = null
var _typing: bool = false
var _choice_box: VBoxContainer
var _choice_buttons: Array[Button] = []
var _footer: HBoxContainer
var _input_row: HBoxContainer
var _input: LineEdit
var _send: Button
var _hint: Label
var _show_choices_after_typing := false
## True while the player's own line (words or an action) is on screen.
var _player_speaking := false
## Who is speaking right now: "villager", "player", "action" or "".
var speaker_role: String = ""
## For tests: pretend the on-screen keyboard is this tall (UI pixels); -1 = ask the system.
var keyboard_height_override: float = -1.0


func _ready() -> void:
	name = "DialoguePanel"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	custom_minimum_size = Vector2(800, 200)
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
	_name_label.name = "Speaker"
	header.add_child(_name_label)
	_subtitle_label = UiTheme.label("", 20, UiTheme.MUTED)
	_subtitle_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_subtitle_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_subtitle_label)
	_end_button = UiTheme.button("End chat", 150)
	_end_button.name = "EndChat"
	_end_button.pressed.connect(end_chat)
	header.add_child(_end_button)
	_text_label = UiTheme.label("", 24)
	_text_label.name = "Line"
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.custom_minimum_size = Vector2(760, 70)
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_text_label)
	_choice_box = VBoxContainer.new()
	_choice_box.add_theme_constant_override("separation", 6)
	_choice_box.visible = false
	box.add_child(_choice_box)
	for i in MAX_CHOICES:
		var choice := UiTheme.button("", 0)
		choice.alignment = HORIZONTAL_ALIGNMENT_LEFT
		choice.custom_minimum_size = Vector2(760, 50)
		choice.pressed.connect(_choose.bind(i))
		_choice_box.add_child(choice)
		_choice_buttons.append(choice)
	# Your own words.
	_input_row = HBoxContainer.new()
	_input_row.name = "TypeRow"
	_input_row.add_theme_constant_override("separation", 8)
	_input_row.visible = false
	box.add_child(_input_row)
	_input = LineEdit.new()
	_input.name = "Message"
	_input.max_length = TalkBrain.MAX_LENGTH
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.custom_minimum_size = Vector2(0, 52)
	_input.add_theme_font_size_override("font_size", 22)
	_input.clear_button_enabled = true
	_input.text_submitted.connect(func(_t): send_typed())
	_input.focus_entered.connect(_layout)
	_input.focus_exited.connect(_layout)
	_input_row.add_child(_input)
	_send = UiTheme.button("Send", 120)
	_send.name = "Send"
	_send.pressed.connect(send_typed)
	_input_row.add_child(_send)
	_hint = UiTheme.label("", 16, UiTheme.MUTED)
	_hint.name = "Hint"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(760, 0)
	_hint.visible = false
	box.add_child(_hint)
	_footer = HBoxContainer.new()
	_footer.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(_footer)
	_continue_button = UiTheme.button("Continue", 180)
	_continue_button.pressed.connect(advance)
	_footer.add_child(_continue_button)

	GameManager.conversation_started.connect(_on_conversation_started)
	GameManager.conversation_ended.connect(func(_v):
		_stop_mouths()
		visible = false
		_input.release_focus()
		Voices.stop())


func _on_conversation_started(villager, conversation) -> void:
	_set_speaker(villager)
	_conversation = conversation
	visible = true
	_choice_box.visible = false
	_input_row.visible = false
	_hint.visible = false
	_input.text = ""
	_footer.visible = true
	_input.placeholder_text = "Type to %s... (simple sentences work best)" % villager.data.display_name
	advance()


## Lines may start with an expression tag such as "[laughing]".
static func split_expression(line: String) -> Array:
	if line.begins_with("[") and line.find("]") > 1:
		var close := line.find("]")
		return [StringName(line.substr(1, close - 1)), line.substr(close + 1).strip_edges()]
	return [&"", line]


func _set_speaker(villager) -> void:
	if _partner and is_instance_valid(_partner) and _partner != villager:
		_partner.model.set_talking(false)
	_partner = villager
	GameManager.speaker = villager
	_show_partner_name()


func _show_partner_name() -> void:
	if _partner == null or not is_instance_valid(_partner):
		return
	var data: VillagerData = _partner.data
	_name_label.text = data.display_name
	_name_label.add_theme_color_override("font_color", UiTheme.ACCENT)
	_subtitle_label.text = "%d · %s" % [data.age, data.role]


func _show_line(line: String) -> void:
	# "@id " switches speaker (used by the village meeting).
	if line.begins_with("@") and line.find(" ") > 1:
		var speaker = GameManager.get_villager(StringName(line.substr(1, line.find(" ") - 1)))
		if speaker:
			_set_speaker(speaker)
		line = line.substr(line.find(" ") + 1)
	_end_player_line()
	_show_partner_name()
	var parts := split_expression(line)
	_text_label.text = parts[1]
	_text_label.add_theme_color_override("font_color", UiTheme.TEXT)
	speaker_role = "villager"
	if _partner and is_instance_valid(_partner):
		Voices.speak(_partner, parts[1], true)
	_text_label.visible_ratio = 0.0
	_typing = true
	if _partner and is_instance_valid(_partner):
		if parts[0] != &"":
			_partner.model.set_expression(parts[0])
		_partner.model.set_talking(true)
	var last := not _conversation.has_lines() and not _conversation.has_choices()
	_continue_button.text = "Goodbye" if last else "Continue"


func _process(delta: float) -> void:
	if not visible:
		return
	_layout()
	if not _typing:
		return
	var length := maxf(_text_label.text.length(), 1.0)
	_text_label.visible_ratio = minf(_text_label.visible_ratio + delta * CHARACTERS_PER_SECOND / length, 1.0)
	if _text_label.visible_ratio >= 1.0:
		_finish_typing()


func _finish_typing() -> void:
	_text_label.visible_ratio = 1.0
	_typing = false
	_stop_mouths()
	if _show_choices_after_typing:
		_show_choices()


func advance() -> void:
	if _typing:
		_finish_typing()
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
		end_chat()


## Leaves the conversation (End chat, Goodbye, or Escape).
func end_chat() -> void:
	_stop_mouths()
	visible = false
	_input.release_focus()
	if GameManager.is_in_conversation():
		GameManager.end_conversation()


func _show_choices() -> void:
	_show_choices_after_typing = false
	var texts := _conversation.choice_texts()
	if texts.size() > MAX_CHOICES:
		push_warning("%d answers offered, only %d fit" % [texts.size(), MAX_CHOICES])
	var compact := texts.size() > 4
	for i in _choice_buttons.size():
		_choice_buttons[i].visible = i < texts.size()
		_choice_buttons[i].custom_minimum_size.y = 44 if compact else 50
		_choice_buttons[i].add_theme_font_size_override("font_size", 19 if compact else 22)
		if i < texts.size():
			_choice_buttons[i].text = "%d.  %s" % [i + 1, texts[i]]
	_choice_box.visible = true
	_input_row.visible = true
	_footer.visible = false
	speaker_role = ""


func _choose(index: int) -> void:
	if not _choice_box.visible or index >= _conversation.choices.size():
		return
	var choice: Dictionary = _conversation.choices[index]
	var kind := Conversation.kind_of(choice)
	var said := String(choice.get("text", ""))
	_conversation.choose(index)
	_hide_turn()
	match kind:
		"say":
			_show_player_line(said)
		"do":
			_show_action_line(Conversation.narration(choice, _partner.data.display_name if _partner else "them"))
		_:
			advance()


## Sends what the player typed. Returns whether it was said.
func send_typed() -> bool:
	if _conversation == null or _typing:
		return false
	var result := _conversation.say_typed(_input.text)
	if not bool(result["ok"]):
		_hint.text = String(result["error"])
		_hint.visible = true
		return false
	_input.text = ""
	_input.release_focus()
	_hint.visible = false
	_hide_turn()
	_show_player_line(String(result["said"]))
	return true


func _hide_turn() -> void:
	_choice_box.visible = false
	_input_row.visible = false
	_hint.visible = false
	_footer.visible = true


## The player says their words before the villager replies.
func _show_player_line(text: String) -> void:
	_player_speaking = true
	speaker_role = "player"
	_name_label.text = "You"
	_name_label.add_theme_color_override("font_color", PLAYER_COLOUR)
	_subtitle_label.text = ""
	_text_label.text = text
	_text_label.add_theme_color_override("font_color", UiTheme.TEXT)
	_text_label.visible_ratio = 0.0
	_typing = true
	if _partner and is_instance_valid(_partner):
		_partner.model.set_talking(false)
	Voices.speak(GameManager.player, text, true)
	if GameManager.player and GameManager.player.get("model"):
		GameManager.player.model.set_talking(true)
	_continue_button.text = "Continue" if _conversation.has_lines() or _conversation.has_choices() else "Goodbye"


## Something the player does (not words): narrated, nobody's mouth moves.
func _show_action_line(text: String) -> void:
	_player_speaking = true
	speaker_role = "action"
	_name_label.text = "You"
	_name_label.add_theme_color_override("font_color", PLAYER_COLOUR)
	_subtitle_label.text = ""
	_text_label.text = text
	_text_label.add_theme_color_override("font_color", ACTION_COLOUR)
	_text_label.visible_ratio = 0.0
	_typing = true
	_stop_mouths()
	_continue_button.text = "Continue" if _conversation.has_lines() or _conversation.has_choices() else "Goodbye"


func _end_player_line() -> void:
	if not _player_speaking:
		return
	_player_speaking = false
	if GameManager.player and GameManager.player.get("model"):
		GameManager.player.model.set_talking(false)


func _stop_mouths() -> void:
	if _partner and is_instance_valid(_partner):
		_partner.model.set_talking(false)
	if GameManager.player and GameManager.player.get("model"):
		GameManager.player.model.set_talking(false)
	_player_speaking = false


## Keeps the panel above the on-screen keyboard while you type (Android),
## and leaves room by hiding the answer buttons meanwhile.
func _layout() -> void:
	var typing := _input.has_focus()
	var keyboard := 0.0
	if typing:
		if keyboard_height_override >= 0.0:
			keyboard = keyboard_height_override
		elif DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
			var px := float(DisplayServer.virtual_keyboard_get_height())
			var window := float(DisplayServer.window_get_size().y)
			keyboard = px * get_viewport_rect().size.y / maxf(window, 1.0)
	if _choice_box.visible == typing and _input_row.visible:
		_choice_box.visible = not typing
	offset_bottom = -24.0 - keyboard
	reset_size()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	if _choice_box.visible and key and key.pressed and not key.echo \
			and key.physical_keycode >= KEY_1 and key.physical_keycode < KEY_1 + MAX_CHOICES:
		_choose(key.physical_keycode - KEY_1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") or event.is_action_pressed("jump"):
		advance()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu"):
		end_chat()
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click and click.pressed and click.button_index == MOUSE_BUTTON_LEFT and not _input_row.visible:
		advance()
		accept_event()
