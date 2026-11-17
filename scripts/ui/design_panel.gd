class_name DesignPanel
extends Control
## Choosing how a house looks: style, walls, roof, door, windows and the floor
## inside, each with < and > to step through the choices. Shown beside the
## screen while you place a house (the preview changes as you choose), or for
## one of your finished houses through Build > Redecorate (it changes as you
## choose; Done when you're happy).

static var instance: DesignPanel

var structure: PlacedStructure = null
var _panel: PanelContainer
var _title: Label
var _rows: VBoxContainer
var _done: Button
var _values: Dictionary = {}


func _ready() -> void:
	name = "DesignPanel"
	instance = self
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.offset_top = 320
	_panel.offset_right = -20
	_panel.add_theme_stylebox_override("panel", UiTheme._box(UiTheme.PANEL_COLOR, 12))
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_panel.add_child(box)
	_title = UiTheme.label("Design", 22, UiTheme.ACCENT)
	box.add_child(_title)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 3)
	box.add_child(_rows)
	for option in HouseDesigns.options():
		var key := String(option[0])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var label := UiTheme.label(String(option[1]), 17, UiTheme.MUTED)
		label.custom_minimum_size = Vector2(108, 0)
		row.add_child(label)
		var back := UiTheme.button("<", 46)
		back.name = "Back_" + key
		back.pressed.connect(func(): _step(key, -1))
		row.add_child(back)
		var value := UiTheme.label("", 17)
		value.custom_minimum_size = Vector2(150, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(value)
		_values[key] = value
		var next := UiTheme.button(">", 46)
		next.name = "Next_" + key
		next.pressed.connect(func(): _step(key, 1))
		row.add_child(next)
		_rows.add_child(row)
	_done = UiTheme.button("Done", 140)
	_done.name = "DesignDone"
	_done.pressed.connect(close_panel)
	box.add_child(_done)


func _exit_tree() -> void:
	if instance == self:
		instance = null


## Redecorating one of your finished houses.
func open_for(target: PlacedStructure) -> void:
	structure = target
	_panel.visible = true
	_refresh()


func close_panel() -> void:
	if structure and is_instance_valid(structure):
		GameManager.notify("Your %s has its new look." % String(structure.get_info()["name"]).to_lower())
	structure = null


func is_open() -> bool:
	return _panel.visible


func current() -> Dictionary:
	if structure and is_instance_valid(structure):
		return HouseDesigns.of(structure.record)
	return BuildMode.instance.design if BuildMode.instance else HouseDesigns.default_design()


func _step(key: String, by: int) -> void:
	var d := HouseDesigns.step(current(), key, by)
	if structure and is_instance_valid(structure):
		structure.record["design"] = d
		structure._rebuild()
	elif BuildMode.instance:
		BuildMode.instance.set_design(d)
	_refresh()


func _process(_delta: float) -> void:
	var build := BuildMode.instance
	var placing := build != null and build.active and HouseDesigns.is_house(build.type) and build.moving == null
	if structure and (not is_instance_valid(structure) or GameManager.player == null \
			or GameManager.player.global_position.distance_to(structure.global_position) > 30.0):
		structure = null
	var show := placing or structure != null
	if show != _panel.visible:
		_panel.visible = show
		if show:
			_refresh()
	_done.visible = structure != null


func _refresh() -> void:
	var d := current()
	_title.text = "Redecorate" if structure else "Design your house"
	for key in _values:
		(_values[key] as Label).text = HouseDesigns.choice_label(d, key)
