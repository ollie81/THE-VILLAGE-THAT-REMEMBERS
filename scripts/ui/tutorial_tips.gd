class_name TutorialTips
extends PanelContainer
## Teaches the game a step at a time: one tip card at a time, shown when it
## becomes useful (moving at the start, talking, chopping, building, the
## journal, sleeping, fighting). "Got it" (or doing the thing) moves on.
## Each tip is shown once, ever (saved).

## id -> {text, when: condition, done: condition that also dismisses it}
const TIPS := [
	{"id": "move", "text": "Move with the stick on the left. Drag the right side of the screen to look around."},
	{"id": "talk", "text": "The gold marker shows where to go next. Walk up to the person and tap Talk."},
	{"id": "chop", "text": "To get wood, walk up to any tree and tap Chop. You carry an axe and a pickaxe; rocks give stone."},
	{"id": "build", "text": "Tap Build (top right) to make things. Place it on green ground, then tap Build at the site."},
	{"id": "journal", "text": "Tap your goal card (top left) to open the Journal: what to do next, missions, and everything you can do."},
	{"id": "sleep", "text": "Night falls. Sleep in your bed at home, or choose Actions, then Sleep."},
	{"id": "fight", "text": "Creatures nearby! Attack, Block (hold) and Dodge appear on the right. Eat a stew to heal."},
]

static var instance: TutorialTips
var current: String = ""
var _label: Label
var _check: float = 0.0
var _start := Vector3.INF
var _wood_start: int = -1


func _ready() -> void:
	name = "TutorialTips"
	instance = self
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_bottom = -205
	custom_minimum_size = Vector2(640, 0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	var tag := UiTheme.label("Tip", 20, UiTheme.ACCENT)
	row.add_child(tag)
	_label = UiTheme.label("", 19)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(450, 0)
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_label)
	var ok := UiTheme.button("Got it", 110)
	ok.pressed.connect(dismiss)
	row.add_child(ok)


func _exit_tree() -> void:
	if instance == self:
		instance = null


static func seen(id: String) -> bool:
	return bool(GameState.get_flag(StringName("tip_" + id)))


func dismiss() -> void:
	if current != "":
		GameState.set_flag(StringName("tip_" + current))
	current = ""
	visible = false


## Whether tip `id` is useful right now.
func _wanted(id: String) -> bool:
	var player = GameManager.player
	match id:
		"move":
			return true
		"talk":
			return not GameState.is_week_complete() and String(GameState.current_objective()["id"]) == "meet"
		"chop":
			return GameState.objective_index >= 1 or WorldClock.day >= 2
		"build":
			return GameState.count(&"wood") >= 6
		"journal":
			return GameState.objective_index >= 1
		"sleep":
			return PlayerController.is_night()
		"fight":
			return player != null and player.combat != null and player.combat.in_fight()
	return false


## Whether the player has already done what tip `id` teaches.
func _done(id: String) -> bool:
	var player = GameManager.player
	match id:
		"move":
			return player != null and _start != Vector3.INF and player.global_position.distance_to(_start) > 6.0
		"talk":
			return GameState.villagers_met() >= 1
		"chop":
			return _wood_start >= 0 and int(GameState.collected[&"wood"]) > _wood_start
		"build":
			return not GameState.structures.is_empty()
		"journal":
			return JournalPanel.instance != null and JournalPanel.instance.visible
		"sleep":
			return not PlayerController.is_night()
	return false


func _process(delta: float) -> void:
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.5
	var player = GameManager.player
	if player == null:
		return
	if _start == Vector3.INF:
		_start = player.global_position
		_wood_start = int(GameState.collected[&"wood"])
	var busy: bool = GameManager.is_in_conversation() or GameManager.camera_mode != GameManager.CameraMode.EXPLORATION
	if current != "":
		if _done(current):
			dismiss()
		else:
			visible = not busy
		return
	for tip: Dictionary in TIPS:
		var id := String(tip["id"])
		if seen(id) or not _wanted(id):
			continue
		if _done(id):
			GameState.set_flag(StringName("tip_" + id))
			continue
		current = id
		_label.text = String(tip["text"])
		visible = not busy
		return
