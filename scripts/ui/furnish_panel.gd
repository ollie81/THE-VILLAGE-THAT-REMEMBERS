class_name FurnishPanel
extends Control
## The Furnish button (top right, under Shop) and its menu: furniture you can
## make for where you are (everything indoors in your house, outdoor pieces
## outside), with costs; pieces you've put away, to place again; and Arrange,
## to pick up and move what you've placed. While placing, a bar at the bottom
## has Rotate, Place, Put away and Cancel, and says why a spot won't do.

static var instance: FurnishPanel

var _button: Button
var _panel: PanelContainer
var _list: GridContainer
var _stored: GridContainer
var _stored_title: Label
var _arrange: Button
var _note: Label
var _bar: PanelContainer
var _bar_text: Label
var _place: Button
var _away: Button
var _arrange_bar: PanelContainer


func _ready() -> void:
	name = "FurnishPanel"
	instance = self
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_button = UiTheme.button("Furnish", 120)
	_button.name = "FurnishButton"
	_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_button.offset_top = 284
	_button.offset_right = -20
	_button.offset_left = -140
	_button.pressed.connect(toggle)
	add_child(_button)
	_build_menu()
	_build_bars()
	if FurnishMode.instance:
		FurnishMode.instance.changed.connect(_on_mode_changed)


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _build_menu() -> void:
	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.custom_minimum_size = Vector2(780, 0)
	_panel.add_theme_stylebox_override("panel", UiTheme._box(Color(0.13, 0.1, 0.08, 0.98), 14))
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	var title := UiTheme.label("Furnish", 30, UiTheme.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_arrange = UiTheme.button("Arrange: move what's placed", 330)
	_arrange.name = "ArrangeButton"
	_arrange.pressed.connect(func():
		_panel.visible = false
		FurnishMode.instance.set_arranging(true))
	header.add_child(_arrange)
	_note = UiTheme.label("", 17, UiTheme.MUTED)
	box.add_child(_note)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(760, 360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 8)
	scroll.add_child(inner)
	_list = GridContainer.new()
	_list.columns = 2
	_list.add_theme_constant_override("h_separation", 8)
	_list.add_theme_constant_override("v_separation", 6)
	inner.add_child(_list)
	_stored_title = UiTheme.label("Put away  (tap to place again, free)", 20)
	inner.add_child(_stored_title)
	_stored = GridContainer.new()
	_stored.columns = 3
	_stored.add_theme_constant_override("h_separation", 8)
	_stored.add_theme_constant_override("v_separation", 6)
	inner.add_child(_stored)
	var close := UiTheme.button("Close", 160)
	close.pressed.connect(func(): _panel.visible = false)
	box.add_child(close)


func _build_bars() -> void:
	_bar = PanelContainer.new()
	_bar.name = "PlacingBar"
	_bar.visible = false
	_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_bar.offset_bottom = -235
	_bar.add_theme_stylebox_override("panel", UiTheme._box(UiTheme.PANEL_COLOR, 12))
	add_child(_bar)
	var v := VBoxContainer.new()
	_bar.add_child(v)
	_bar_text = UiTheme.label("", 19)
	_bar_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_bar_text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	var rotate := UiTheme.button("Rotate", 130)
	rotate.name = "Rotate"
	rotate.pressed.connect(func(): FurnishMode.instance.turn())
	row.add_child(rotate)
	_place = UiTheme.button("Place", 150)
	_place.name = "Place"
	_place.pressed.connect(func(): FurnishMode.instance.confirm())
	row.add_child(_place)
	_away = UiTheme.button("Put away", 150)
	_away.name = "PutAway"
	_away.pressed.connect(func(): FurnishMode.instance.put_away())
	row.add_child(_away)
	var cancel := UiTheme.button("Cancel", 130)
	cancel.name = "Cancel"
	cancel.pressed.connect(func(): FurnishMode.instance.cancel())
	row.add_child(cancel)
	_arrange_bar = PanelContainer.new()
	_arrange_bar.name = "ArrangingBar"
	_arrange_bar.visible = false
	_arrange_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_arrange_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_arrange_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_arrange_bar.offset_bottom = -235
	_arrange_bar.add_theme_stylebox_override("panel", UiTheme._box(UiTheme.PANEL_COLOR, 12))
	add_child(_arrange_bar)
	var arow := HBoxContainer.new()
	arow.add_theme_constant_override("separation", 12)
	_arrange_bar.add_child(arow)
	arow.add_child(UiTheme.label("Arranging: walk up to a piece and tap Pick up / Move.", 19))
	var done := UiTheme.button("Done", 120)
	done.name = "DoneArranging"
	done.pressed.connect(func(): FurnishMode.instance.set_arranging(false))
	arow.add_child(done)


## Where furnishing makes sense: in your own house, or out in the village.
func _usable_here() -> bool:
	var exploring := GameManager.camera_mode == GameManager.CameraMode.EXPLORATION
	if not exploring or GameManager.is_in_conversation() or (BuildMode.instance and BuildMode.instance.active):
		return false
	var place := FurnishMode.current_place()
	return place == "outside" or (Furnishings.instance and Furnishings.instance.is_players_place(place))


func _process(_delta: float) -> void:
	var mode := FurnishMode.instance
	var ok := _usable_here() and mode != null
	_button.visible = ok and not mode.active and not mode.arranging
	if not ok or mode.active:
		_panel.visible = false
	_bar.visible = mode != null and mode.active
	_arrange_bar.visible = mode != null and mode.arranging and not mode.active
	if _bar.visible:
		var info := FurnitureCatalog.info(mode.type)
		var cost := "" if not mode.moving.is_empty() else "  (%s)" % GameState.cost_text(info.get("cost", {}))
		_bar_text.text = ("%s%s: %s" % [info.get("name", ""), cost, "fits here" if mode.reason == "" else mode.reason])
		_place.text = "Put down" if mode.is_carrying() else "Place"
		_place.disabled = mode.reason != ""
		_away.visible = not mode.moving.is_empty()


func toggle() -> void:
	_panel.visible = not _panel.visible
	if _panel.visible:
		_panel.move_to_front()
		_refresh()


func _on_mode_changed() -> void:
	if _panel.visible:
		_refresh()


func _refresh() -> void:
	var place := FurnishMode.current_place()
	var outdoors := place == "outside"
	_note.text = "Outdoor pieces for the village." if outdoors else "For your house. Pieces fit inside one room, clear of walls, doorways and the hearth."
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	for type in FurnitureCatalog.ORDER:
		var info := FurnitureCatalog.info(type)
		if outdoors and not bool(info.get("outdoor", false)):
			continue
		var missing := GameState.missing_text(info["cost"])
		var b := UiTheme.button("%s  ·  %s" % [info["name"], GameState.cost_text(info["cost"])] + ("" if missing == "" else "\n%s" % missing), 375)
		b.name = "Make_" + String(type)
		b.add_theme_font_size_override("font_size", 17)
		b.disabled = missing != ""
		var t: StringName = type
		b.pressed.connect(func():
			_panel.visible = false
			FurnishMode.instance.start_new(t))
		_list.add_child(b)
	for child in _stored.get_children():
		_stored.remove_child(child)
		child.queue_free()
	var stored := Furnishings.stored()
	_stored_title.visible = not stored.is_empty()
	for record in stored:
		var type := StringName(String(record["type"]))
		var info := FurnitureCatalog.info(type)
		var b := UiTheme.button(String(info.get("name", "Piece")), 245)
		b.name = "Stored_%d" % int(record["id"])
		b.add_theme_font_size_override("font_size", 17)
		b.disabled = outdoors and not bool(info.get("outdoor", false))
		var r: Dictionary = record
		b.pressed.connect(func():
			_panel.visible = false
			FurnishMode.instance.start_new(StringName(String(r["type"])), r))
		_stored.add_child(b)
