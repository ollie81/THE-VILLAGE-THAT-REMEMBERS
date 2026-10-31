class_name PopulationPanel
extends Control
## The village at a glance: how many people live here and their ages, what
## they do, where they sleep, how happy they are, and who has come, gone,
## been born or died. Opened with the People button or P.

var _button: Button
var _panel: PanelContainer
var _summary: VBoxContainer
var _jobs: VBoxContainer
var _people: VBoxContainer
var _history: VBoxContainer
var _refresh_timer: float = 0.0


func _ready() -> void:
	name = "PopulationPanel"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_button = UiTheme.button("People", 120)
	_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_button.offset_top = 86
	_button.offset_right = -152
	_button.offset_left = -272
	_button.pressed.connect(toggle)
	add_child(_button)

	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.custom_minimum_size = Vector2(1180, 600)
	add_child(_panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	_panel.add_child(outer)
	var header := HBoxContainer.new()
	outer.add_child(header)
	var title := UiTheme.label("The village", 30, UiTheme.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := UiTheme.button("Close", 130)
	close.pressed.connect(func(): _panel.visible = false)
	header.add_child(close)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 22)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(columns)
	_summary = _column(columns, 250)
	_jobs = _column(columns, 230)
	_people = _scroll_column(columns, 380)
	_history = _scroll_column(columns, 260)

	Population.event_logged.connect(func(_e): _refresh_soon())
	Population.housing_changed.connect(_refresh_soon)
	GameManager.conversation_started.connect(func(_v, _c): _panel.visible = false)


func _column(parent: Control, width: float) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(width, 0)
	box.add_theme_constant_override("separation", 4)
	parent.add_child(box)
	return box


func _scroll_column(parent: Control, width: float) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(width, 500)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	return box


func is_open() -> bool:
	return _panel.visible


func toggle() -> void:
	_panel.visible = not _panel.visible
	if _panel.visible:
		refresh()


func _refresh_soon() -> void:
	_refresh_timer = 0.0


func _process(delta: float) -> void:
	var exploring := GameManager.camera_mode == GameManager.CameraMode.EXPLORATION
	_button.visible = not GameManager.is_in_conversation() and not (BuildMode.instance and BuildMode.instance.active)
	_button.offset_right = -152 if exploring else -20
	_button.offset_left = _button.offset_right - 120
	if not _panel.visible:
		return
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = 1.0
		refresh()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.physical_keycode == KEY_P and not GameManager.is_in_conversation():
		toggle()
		get_viewport().set_input_as_handled()


func refresh() -> void:
	var stats := Population.stats()
	var housing: Dictionary = stats["housing"]
	var counters: Dictionary = stats["counters"]
	_clear(_summary)
	_summary.add_child(UiTheme.label("Population", 22, UiTheme.ACCENT))
	_summary.add_child(UiTheme.label("%d villagers" % int(stats["total"]), 28))
	if int(stats["visitors"]) > 0:
		_summary.add_child(UiTheme.label("+ %d traveller waiting" % int(stats["visitors"]), 18, UiTheme.MUTED))
	_summary.add_child(_row("Adults", stats["adults"]))
	_summary.add_child(_row("Teenagers", stats["teens"]))
	_summary.add_child(_row("Children", stats["children"]))
	_summary.add_child(_row("Elders", stats["elders"]))
	_summary.add_child(_row("Couples", stats["couples"]))
	_summary.add_child(_row("Happiness", "%d%%" % int(stats["happiness"])))
	_summary.add_child(UiTheme.label("Housing", 22, UiTheme.ACCENT))
	_summary.add_child(_row("Beds in homes", "%d / %d" % [int(housing["used"]), int(housing["capacity"])]))
	_summary.add_child(_row("Free beds", housing["free"]))
	_summary.add_child(_row("Sleeping at the camp", housing["camping"]))
	if int(housing["free"]) <= 0:
		var hint := UiTheme.label("Build a cottage to house more people.", 16, UiTheme.MUTED)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_summary.add_child(hint)

	_clear(_jobs)
	_jobs.add_child(UiTheme.label("Occupations", 22, UiTheme.ACCENT))
	var jobs: Dictionary = stats["occupations"]
	var names := jobs.keys()
	names.sort_custom(func(a, b): return int(jobs[a]) > int(jobs[b]))
	for job in names:
		_jobs.add_child(_row(String(job), jobs[job]))
	_jobs.add_child(UiTheme.label("Life and migration", 22, UiTheme.ACCENT))
	_jobs.add_child(_row("Arrivals", counters["arrivals"]))
	_jobs.add_child(_row("Departures", counters["departures"]))
	_jobs.add_child(_row("Turned away", counters["rejected"]))
	_jobs.add_child(_row("Births", counters["births"]))
	_jobs.add_child(_row("Deaths", counters["deaths"]))
	_jobs.add_child(_row("Partnerships", counters["partnerships"]))
	_jobs.add_child(_row("Marriages", counters["marriages"]))

	_clear(_people)
	_people.add_child(UiTheme.label("Villagers", 22, UiTheme.ACCENT))
	var living := Population.residents(true)
	living.sort_custom(func(a: Person, b: Person): return a.arrived_day < b.arrived_day or (a.arrived_day == b.arrived_day and a.id < b.id))
	for person: Person in living:
		_people.add_child(_person_row(person))

	_clear(_history)
	_history.add_child(UiTheme.label("Recent events", 22, UiTheme.ACCENT))
	var recent: Array = Population.events.slice(maxi(Population.events.size() - 14, 0))
	recent.reverse()
	if recent.is_empty():
		_history.add_child(UiTheme.label("Nothing yet. Travellers may come by the bridge.", 16, UiTheme.MUTED))
	for event: Dictionary in recent:
		var line := UiTheme.label("Day %d  %s" % [int(event["day"]), String(event["text"])], 16)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size = Vector2(240, 0)
		_history.add_child(line)


func _person_row(person: Person) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var name := person.full_name() + ("  (founder)" if person.founder else "")
	if person.status == Person.STATUS_VISITOR:
		name += "  (traveller)"
	box.add_child(UiTheme.label(name, 18, UiTheme.TEXT))
	var home := "the camp" if person.home == Population.CAMP_ID else VillageLayout.get_location_label(person.home)
	var mood := "happy" if person.happiness >= 70.0 else "unhappy" if person.happiness < 30.0 else "content"
	var partner := Population.get_person(person.partner)
	var detail := "%d, %s, %s" % [person.age(), Professions.label(person.profession).to_lower(), mood]
	if partner:
		detail += ", %s %s" % ["married to" if person.married else "with", partner.first_name]
	if person.status == Person.STATUS_RESIDENT:
		detail += "\nLives at %s" % home
	var info := UiTheme.label(detail, 15, UiTheme.MUTED)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(360, 0)
	box.add_child(info)
	return box


func _row(title: String, value: Variant) -> Control:
	var row := HBoxContainer.new()
	var left := UiTheme.label(title, 18, UiTheme.MUTED)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	row.add_child(UiTheme.label(str(value), 18))
	return row


static func _clear(box: Container) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
