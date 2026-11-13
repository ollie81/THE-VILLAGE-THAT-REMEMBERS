class_name FestivalPanel
extends PanelContainer
## A small card on the right during a festival: its name and the optional
## goals with progress. The day before, it says what's coming tomorrow.

var _title: Label
var _goals: Label


func _ready() -> void:
	name = "FestivalPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	offset_top = 222
	offset_right = -20
	custom_minimum_size = Vector2(320, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	add_child(box)
	_title = UiTheme.label("", 20, UiTheme.ACCENT)
	box.add_child(_title)
	_goals = UiTheme.label("", 17)
	_goals.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_goals.custom_minimum_size = Vector2(300, 0)
	box.add_child(_goals)
	visible = false


func _process(_delta: float) -> void:
	var festival := Festival.instance
	var exploring := GameManager.camera_mode == GameManager.CameraMode.EXPLORATION and not GameManager.is_in_conversation()
	if festival == null or not exploring:
		visible = false
		return
	var now := festival.current()
	if now.is_empty():
		var tomorrow := Festival.festival_tomorrow(WorldClock.day)
		visible = not tomorrow.is_empty()
		if visible:
			_title.text = "Tomorrow: %s" % tomorrow["name"]
			_goals.text = "A festival with gifts to earn. Come back for it!"
		return
	visible = true
	var last_day := Festival.day_in_week(WorldClock.day) == Festival.FIRST_DAY_OF_WEEK + Festival.LENGTH_DAYS - 1
	_title.text = "%s  (%s)" % [now["name"], "last day" if last_day else "today and tomorrow"]
	var lines := PackedStringArray()
	for goal: Dictionary in now["goals"]:
		var id := String(goal["id"])
		if festival.done.has(id):
			lines.append("✓ %s" % goal["text"])
		else:
			lines.append("• %s  (%d / %d)" % [goal["text"], festival.goal_progress(id), int(goal["goal"])])
	if festival.bonus_given:
		lines.append("Everything done. What a festival!")
	_goals.text = "\n".join(lines)
