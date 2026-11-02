class_name GameplayPanels
extends Control
## HUD pieces for the gameplay loop: resource counts, the current objective,
## the Build button and menu, and the controls shown while placing.

var _resource_label: Label
var _objective_title: Label
var _objective_hint: Label
var _objective_progress: Label
var _objective_box: PanelContainer
var _build_menu: PanelContainer
var _build_list: VBoxContainer
var _placement_bar: PanelContainer
var _placement_reason: Label
var _place_button: Button
var _build_button: Button
var _category: String = "Homes"
var _tab_buttons: Dictionary = {}
var _edit_bar: PanelContainer
var _edit_label: Label
## A line at the top of the Build menu: what you have, or what's missing.
var _menu_message: Label


func _ready() -> void:
	name = "GameplayPanels"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_resources()
	_build_objective()
	_build_build_menu()
	_build_placement_bar()
	_build_edit_bar()
	GameState.inventory_changed.connect(func(_r, _a, _t): _refresh())
	GameState.objective_changed.connect(func(_i): _refresh())
	GameState.objective_completed.connect(_on_objective_completed)
	GameManager.camera_mode_changed.connect(func(_m): _refresh())
	GameManager.conversation_started.connect(func(_v, _c): _build_menu.visible = false)
	_refresh()


func _process(_delta: float) -> void:
	var build := BuildMode.instance
	_placement_bar.visible = build != null and build.active
	_edit_bar.visible = build != null and build.edit_mode != "" and not build.active
	if _edit_bar.visible:
		_edit_label.text = "Walk up to something you built and tap %s." % ("Move" if build.edit_mode == "move" else "Remove (you get half back)")
	if _placement_bar.visible:
		var info := StructureCatalog.info(build.type)
		_placement_reason.text = "%s  ·  %s" % [info["name"], "Ready to place" if build.reason == "" else build.reason]
		_placement_reason.add_theme_color_override("font_color", Color(0.6, 0.95, 0.6) if build.reason == "" else Color(1.0, 0.6, 0.5))
		_place_button.disabled = build.reason != ""
	var exploring := GameManager.camera_mode == GameManager.CameraMode.EXPLORATION
	_build_button.visible = exploring and not GameManager.is_in_conversation()
	_objective_box.visible = not GameManager.is_in_conversation() and not _placement_bar.visible


# --- Resources and objective -----------------------------------------------------------

func _build_resources() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(20, 108)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	_resource_label = UiTheme.label("", 21)
	panel.add_child(_resource_label)


func _build_objective() -> void:
	_objective_box = PanelContainer.new()
	_objective_box.position = Vector2(20, 160)
	_objective_box.custom_minimum_size = Vector2(340, 0)
	_objective_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_objective_box)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_objective_box.add_child(box)
	_objective_title = UiTheme.label("", 21, UiTheme.ACCENT)
	box.add_child(_objective_title)
	_objective_progress = UiTheme.label("", 18)
	box.add_child(_objective_progress)
	_objective_hint = UiTheme.label("", 16, UiTheme.MUTED)
	_objective_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective_hint.custom_minimum_size = Vector2(320, 0)
	box.add_child(_objective_hint)


func _refresh() -> void:
	var parts := PackedStringArray()
	for resource in GameState.RESOURCES:
		parts.append("%s %d" % [GameState.RESOURCE_NAMES[resource], GameState.count(resource)])
	_resource_label.text = "   ".join(parts)
	if GameState.is_week_complete():
		_objective_title.text = "Your first week is complete"
		_objective_progress.text = "The village is yours to shape."
		_objective_hint.text = "Keep building, helping and getting to know everyone."
	else:
		var objective := GameState.current_objective()
		_objective_title.text = "Day %d · %s" % [int(objective["day"]), objective["title"]]
		_objective_progress.text = GameState.objective_progress()
		_objective_hint.text = String(objective["hint"])
	_refresh_build_list()


func _on_objective_completed(_index: int, title: String) -> void:
	GameManager.notify("Objective complete: %s" % title)


# --- Build menu -------------------------------------------------------------------------

func _build_build_menu() -> void:
	_build_button = UiTheme.button("Build", 120)
	_build_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_build_button.offset_top = 86
	_build_button.offset_right = -20
	_build_button.offset_left = -140
	_build_button.pressed.connect(_toggle_build_menu)
	add_child(_build_button)

	_build_menu = PanelContainer.new()
	_build_menu.visible = false
	_build_menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_build_menu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_build_menu.grow_vertical = Control.GROW_DIRECTION_BOTH
	_build_menu.custom_minimum_size = Vector2(620, 0)
	add_child(_build_menu)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_build_menu.add_child(box)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	box.add_child(header)
	var title := UiTheme.label("Build", 30, UiTheme.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	for tab in StructureCatalog.CATEGORIES:
		var tab_button := UiTheme.button(String(tab), 120)
		tab_button.toggle_mode = true
		tab_button.pressed.connect(func():
			_category = String(tab)
			_refresh_build_list())
		header.add_child(tab_button)
		_tab_buttons[String(tab)] = tab_button
	_menu_message = UiTheme.label("", 19, UiTheme.MUTED)
	_menu_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_menu_message.custom_minimum_size = Vector2(700, 0)
	box.add_child(_menu_message)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(700, 340)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_build_list = VBoxContainer.new()
	_build_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_build_list)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	box.add_child(footer)
	var move := UiTheme.button("Move something", 220)
	move.pressed.connect(func():
		_build_menu.visible = false
		BuildMode.instance.set_edit_mode("move"))
	footer.add_child(move)
	var remove := UiTheme.button("Remove something", 240)
	remove.pressed.connect(func():
		_build_menu.visible = false
		BuildMode.instance.set_edit_mode("remove"))
	footer.add_child(remove)
	var close := UiTheme.button("Close", 140)
	close.pressed.connect(func(): _build_menu.visible = false)
	footer.add_child(close)


func _refresh_build_list() -> void:
	if _build_list == null:
		return
	for child in _build_list.get_children():
		child.queue_free()
	for tab in _tab_buttons:
		_tab_buttons[tab].set_pressed_no_signal(tab == _category)
	for type in StructureCatalog.CATEGORIES[_category]:
		var info := StructureCatalog.info(type)
		var affordable := GameState.can_afford(info["cost"])
		var built := GameState.completed_structures(type)
		var name_text := String(info["name"]) + ("  (built: %d)" % built if built > 0 else "")
		var price := GameState.cost_text(info["cost"])
		if not affordable:
			price += "   (%s)" % GameState.missing_text(info["cost"]).to_lower()
		var button := UiTheme.button("%s  —  %s\n%s" % [name_text, price, info["description"]], 680)
		button.custom_minimum_size = Vector2(680, 64)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 19)
		if not affordable:
			button.add_theme_color_override("font_color", UiTheme.MUTED)
		button.pressed.connect(_choose_structure.bind(type))
		_build_list.add_child(button)


func _toggle_build_menu() -> void:
	_build_menu.visible = not _build_menu.visible
	if _build_menu.visible:
		_show_menu_message("")
		# Open where there's something you can build now.
		if not _can_afford_any(_category):
			for tab in StructureCatalog.CATEGORIES:
				if _can_afford_any(tab):
					_category = tab
					break
		_refresh_build_list()


func _can_afford_any(tab: String) -> bool:
	for type in StructureCatalog.CATEGORIES[tab]:
		if GameState.can_afford(StructureCatalog.info(type)["cost"]):
			return true
	return false


## `text` in red, or (when empty) a reminder of what you have to build with.
func _show_menu_message(text: String) -> void:
	if _menu_message == null:
		return
	if text == "":
		_menu_message.text = "Tap something to build it. Grey things need more materials: chop trees, mine rocks, pick herbs."
		_menu_message.add_theme_color_override("font_color", UiTheme.MUTED)
	else:
		_menu_message.text = text
		_menu_message.add_theme_color_override("font_color", Color(1.0, 0.62, 0.5))


## B opens and closes the Build menu on a keyboard.
func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.physical_keycode == KEY_B and _build_button.visible \
			and not (BuildMode.instance and BuildMode.instance.active):
		_toggle_build_menu()
		get_viewport().set_input_as_handled()


func _choose_structure(type: StringName) -> void:
	var info := StructureCatalog.info(type)
	if not GameState.can_afford(info["cost"]):
		var message := "%s to build a %s. Chop trees for wood, mine rocks for stone and pick herbs." % [GameState.missing_text(info["cost"]), String(info["name"]).to_lower()]
		_show_menu_message(message)
		GameManager.notify(message)
		Sounds.play("click", null, -2.0)
		return
	_build_menu.visible = false
	if BuildMode.instance:
		BuildMode.instance.start(type)


# --- Placement controls ----------------------------------------------------------------

## Shown while choosing something to move or remove.
func _build_edit_bar() -> void:
	_edit_bar = PanelContainer.new()
	_edit_bar.visible = false
	# Bottom middle: clear of messages, and where thumbs are.
	_edit_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_edit_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_edit_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_edit_bar.offset_bottom = -24
	add_child(_edit_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_edit_bar.add_child(row)
	_edit_label = UiTheme.label("", 20)
	row.add_child(_edit_label)
	var done := UiTheme.button("Done", 120)
	done.pressed.connect(func(): BuildMode.instance.set_edit_mode(""))
	row.add_child(done)


func _build_placement_bar() -> void:
	_placement_bar = PanelContainer.new()
	_placement_bar.visible = false
	# Bottom middle: clear of messages, and where thumbs are.
	_placement_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_placement_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_placement_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_placement_bar.offset_bottom = -24
	add_child(_placement_bar)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_placement_bar.add_child(box)
	_placement_reason = UiTheme.label("", 21)
	_placement_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_placement_reason)
	box.add_child(UiTheme.label("Walk to move the preview", 16, UiTheme.MUTED))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var rotate := UiTheme.button("Rotate", 130)
	rotate.pressed.connect(func(): BuildMode.instance.rotate_preview())
	row.add_child(rotate)
	_place_button = UiTheme.button("Place", 130)
	_place_button.pressed.connect(func(): BuildMode.instance.confirm())
	row.add_child(_place_button)
	var cancel := UiTheme.button("Cancel", 130)
	cancel.pressed.connect(func(): BuildMode.instance.cancel())
	row.add_child(cancel)
