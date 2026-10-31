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


func _ready() -> void:
	name = "GameplayPanels"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_resources()
	_build_objective()
	_build_build_menu()
	_build_placement_bar()
	GameState.inventory_changed.connect(func(_r, _a, _t): _refresh())
	GameState.objective_changed.connect(func(_i): _refresh())
	GameState.objective_completed.connect(_on_objective_completed)
	GameManager.camera_mode_changed.connect(func(_m): _refresh())
	GameManager.conversation_started.connect(func(_v, _c): _build_menu.visible = false)
	_refresh()


func _process(_delta: float) -> void:
	var build := BuildMode.instance
	_placement_bar.visible = build != null and build.active
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
	box.add_child(UiTheme.label("Build", 30, UiTheme.ACCENT))
	_build_list = VBoxContainer.new()
	_build_list.add_theme_constant_override("separation", 6)
	box.add_child(_build_list)
	var close := UiTheme.button("Close", 140)
	close.pressed.connect(func(): _build_menu.visible = false)
	box.add_child(close)


func _refresh_build_list() -> void:
	if _build_list == null:
		return
	for child in _build_list.get_children():
		child.queue_free()
	for type in StructureCatalog.ORDER:
		var info := StructureCatalog.info(type)
		var affordable := GameState.can_afford(info["cost"])
		var button := UiTheme.button("%s  —  %s\n%s" % [info["name"], GameState.cost_text(info["cost"]), info["description"]], 580)
		button.custom_minimum_size = Vector2(580, 64)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 19)
		if not affordable:
			button.add_theme_color_override("font_color", UiTheme.MUTED)
		button.pressed.connect(_choose_structure.bind(type))
		_build_list.add_child(button)


func _toggle_build_menu() -> void:
	_build_menu.visible = not _build_menu.visible
	if _build_menu.visible:
		_refresh_build_list()


func _choose_structure(type: StringName) -> void:
	var info := StructureCatalog.info(type)
	if not GameState.can_afford(info["cost"]):
		GameManager.notify("%s to build a %s." % [GameState.missing_text(info["cost"]), String(info["name"]).to_lower()])
		return
	_build_menu.visible = false
	if BuildMode.instance:
		BuildMode.instance.start(type)


# --- Placement controls ----------------------------------------------------------------

func _build_placement_bar() -> void:
	_placement_bar = PanelContainer.new()
	_placement_bar.visible = false
	_placement_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_placement_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_placement_bar.offset_top = 110
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
