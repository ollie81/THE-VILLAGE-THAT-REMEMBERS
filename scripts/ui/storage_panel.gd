class_name StoragePanel
extends Control
## What's inside a chest, wardrobe or crate, and buttons to put resources in
## from the village stores or take them out again. Stored things are saved
## with the piece of furniture (and stay in it if you move or put it away).

static var instance: StoragePanel

var piece: FurniturePiece
var _panel: PanelContainer
var _title: Label
var _rows: VBoxContainer
var _status: Label


func _ready() -> void:
	name = "StoragePanel"
	instance = self
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.custom_minimum_size = Vector2(720, 0)
	_panel.add_theme_stylebox_override("panel", UiTheme._box(Color(0.13, 0.1, 0.08, 0.98), 14))
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_panel.add_child(box)
	_title = UiTheme.label("", 28, UiTheme.ACCENT)
	box.add_child(_title)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 8)
	box.add_child(_rows)
	_status = UiTheme.label("", 18, UiTheme.MUTED)
	box.add_child(_status)
	var close := UiTheme.button("Close", 160)
	close.name = "Close"
	close.pressed.connect(close_panel)
	box.add_child(close)


func _exit_tree() -> void:
	if instance == self:
		instance = null


func is_open() -> bool:
	return _panel.visible


func open(target: FurniturePiece) -> void:
	piece = target
	_panel.visible = true
	_panel.move_to_front()
	_refresh()


func close_panel() -> void:
	_panel.visible = false
	piece = null


func _process(_delta: float) -> void:
	# Walk away and it closes.
	if _panel.visible and (piece == null or not is_instance_valid(piece) or GameManager.player == null \
			or GameManager.player.global_position.distance_to(piece.global_position) > 4.0):
		close_panel()


func _refresh() -> void:
	if piece == null:
		return
	var holds := int(piece.info.get("holds", 0))
	_title.text = "%s  ·  %d / %d stored" % [piece.info["name"], Furnishings.stored_total(piece.record), holds]
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var storage: Dictionary = piece.record.get("storage", {})
	for resource in GameState.RESOURCES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var text := UiTheme.label("%s:  %d inside  ·  %d in your stores" % [GameState.RESOURCE_NAMES[resource], int(storage.get(String(resource), 0)), GameState.count(resource)], 19)
		text.custom_minimum_size = Vector2(330, 0)
		row.add_child(text)
		for spec in [["Put in 5", 5, true], ["Take 5", 5, false], ["Take all", 9999, false]]:
			var b := UiTheme.button(spec[0], 118)
			b.name = "%s_%s" % [String(resource), String(spec[0]).replace(" ", "")]
			b.add_theme_font_size_override("font_size", 17)
			var r: StringName = resource
			var amount: int = spec[1]
			var putting: bool = spec[2]
			b.pressed.connect(func(): _move(r, amount, putting))
			row.add_child(b)
		_rows.add_child(row)


func _move(resource: StringName, amount: int, putting: bool) -> void:
	if piece == null:
		return
	var n := Furnishings.instance.deposit(piece.record, resource, amount) if putting else Furnishings.instance.withdraw(piece.record, resource, amount)
	var name_text := String(GameState.RESOURCE_NAMES[resource]).to_lower()
	if n == 0:
		_status.text = ("It's full, or you have no %s to put in." % name_text) if putting else ("There's no %s in here." % name_text)
	else:
		_status.text = "%s %d %s." % ["Put in" if putting else "Took out", n, name_text]
	Sounds.play("pickup", null, -10.0)
	_refresh()
