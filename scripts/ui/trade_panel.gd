class_name TradePanel
extends PanelContainer
## The market stalls' trader: swap what you have plenty of for what you need.
## Opens from day 3 (when the traders start coming).

const OPENS_DAY := 3
const OFFERS := [
	{"give": {&"wood": 4}, "get": {&"stone": 2}},
	{"give": {&"stone": 3}, "get": {&"food": 3}},
	{"give": {&"food": 3}, "get": {&"herbs": 2}},
	{"give": {&"herbs": 2}, "get": {&"wood": 4}},
]

static var instance: TradePanel
var _list: VBoxContainer
var _note: Label


func _ready() -> void:
	name = "TradePanel"
	instance = self
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	custom_minimum_size = Vector2(560, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	box.add_child(UiTheme.label("Market", 30, UiTheme.ACCENT))
	_note = UiTheme.label("Swap what you have plenty of for what you need.", 18, UiTheme.MUTED)
	box.add_child(_note)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	box.add_child(_list)
	var close := UiTheme.button("Close", 140)
	close.pressed.connect(func(): visible = false)
	box.add_child(close)


func _exit_tree() -> void:
	if instance == self:
		instance = null


static func is_open_today() -> bool:
	return WorldClock.day >= OPENS_DAY


func open() -> void:
	visible = true
	_refresh()


func _refresh() -> void:
	for child in _list.get_children():
		child.queue_free()
	for i in OFFERS.size():
		var offer: Dictionary = OFFERS[i]
		var can := GameState.can_afford(offer["give"])
		var button := UiTheme.button("Give %s  →  get %s%s" % [GameState.cost_text(offer["give"]), GameState.cost_text(offer["get"]),
			"" if can else "   (%s)" % GameState.missing_text(offer["give"]).to_lower()], 520)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if not can:
			button.add_theme_color_override("font_color", UiTheme.MUTED)
		button.pressed.connect(trade.bind(i))
		_list.add_child(button)


## Makes trade `index`. Returns true if it happened.
func trade(index: int) -> bool:
	var offer: Dictionary = OFFERS[index]
	if not GameState.spend(offer["give"]):
		_note.text = "%s for that trade." % GameState.missing_text(offer["give"])
		return false
	for resource in offer["get"]:
		GameState.add(resource, int(offer["get"][resource]))
	GameState.increment(&"trades")
	Sounds.play("pickup", null, -4.0)
	_note.text = "Traded %s for %s." % [GameState.cost_text(offer["give"]), GameState.cost_text(offer["get"])]
	_refresh()
	return true
