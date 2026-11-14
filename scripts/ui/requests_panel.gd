class_name RequestsPanel
extends Control
## "Today's requests" card (under the objective) and the "While you were
## away..." story shown when you come back to the village.

var _card: PanelContainer
var _list: VBoxContainer
var _title: Label
var _away: PanelContainer
var _away_title: Label
var _away_subtitle: Label
var _away_lines: VBoxContainer
var _marker_timer: float = 0.0


func _ready() -> void:
	name = "RequestsPanel"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_card = PanelContainer.new()
	_card.position = Vector2(20, 300)
	_card.custom_minimum_size = Vector2(340, 0)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	_card.add_child(box)
	_title = UiTheme.label("Today's requests", 20, UiTheme.ACCENT)
	box.add_child(_title)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 3)
	box.add_child(_list)

	_build_away_story()
	if RequestBoard.instance:
		RequestBoard.instance.changed.connect(refresh)
	if AwayTime.instance:
		AwayTime.instance.caught_up.connect(show_away)
	refresh()


func refresh() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var board := RequestBoard.instance
	if board == null:
		_card.visible = false
		return
	var open := board.open_requests()
	var done := board.requests.size() - open.size()
	_title.text = "Today's requests  %d / %d" % [done, board.requests.size()] if not board.requests.is_empty() else "Today's requests"
	for request: Dictionary in board.requests:
		var finished := bool(request["done"])
		var line := UiTheme.label(("✓ " if finished else "• ") + String(request["text"]), 16, UiTheme.MUTED if finished else UiTheme.TEXT)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size = Vector2(320, 0)
		_list.add_child(line)
	if board.requests.is_empty():
		_list.add_child(UiTheme.label("Nobody needs anything right now.", 16, UiTheme.MUTED))


func _process(delta: float) -> void:
	var exploring := GameManager.camera_mode == GameManager.CameraMode.EXPLORATION
	var placing := BuildMode.instance != null and BuildMode.instance.active
	_card.visible = exploring and not GameManager.is_in_conversation() and not placing and not _away.visible \
		and RequestBoard.instance != null and not RequestBoard.instance.requests.is_empty()
	# The objective card above grows and shrinks; sit just under it.
	var objective: Control = get_parent().find_child("GameplayPanels", false, false)
	if objective and objective.get("_objective_box"):
		var box: Control = objective._objective_box
		_card.position.y = (box.position.y + box.size.y + 10.0) if box.visible else 160.0
	_marker_timer -= delta
	if _marker_timer <= 0.0:
		_marker_timer = 0.5
		_update_markers()


## "!" over people who asked you for something; "…" over people you have a
## message or a visit for.
func _update_markers() -> void:
	var board := RequestBoard.instance
	var wanted := {}
	if board:
		# "!" wins: someone with their own request shows that first.
		for request: Dictionary in board.open_requests():
			if request.has("to") and String(request["kind"]) != "fetch":
				wanted[String(request["to"])] = "…"
		for request: Dictionary in board.open_requests():
			wanted[String(request["from"])] = "!"
	for villager in GameManager.villagers:
		villager.set_marker(String(wanted.get(String(villager.get_villager_id()), "")))


# --- While you were away ------------------------------------------------------------

func _build_away_story() -> void:
	_away = PanelContainer.new()
	_away.visible = false
	_away.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_away.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_away.grow_vertical = Control.GROW_DIRECTION_BOTH
	_away.custom_minimum_size = Vector2(760, 0)
	var background := UiTheme._box(Color(0.12, 0.09, 0.07, 0.97), 14)
	background.content_margin_left = 26
	background.content_margin_right = 26
	background.content_margin_top = 20
	background.content_margin_bottom = 20
	_away.add_theme_stylebox_override("panel", background)
	add_child(_away)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_away.add_child(box)
	_away_title = UiTheme.label("", 32, UiTheme.ACCENT)
	box.add_child(_away_title)
	_away_subtitle = UiTheme.label("", 18, UiTheme.MUTED)
	box.add_child(_away_subtitle)
	_away_lines = VBoxContainer.new()
	_away_lines.add_theme_constant_override("separation", 6)
	box.add_child(_away_lines)
	var go := UiTheme.button("Back to the village", 300)
	go.pressed.connect(func(): _away.visible = false)
	box.add_child(go)


func show_away(summary: Dictionary) -> void:
	_away_title.text = String(summary["title"])
	_away_subtitle.text = String(summary["subtitle"])
	for child in _away_lines.get_children():
		_away_lines.remove_child(child)
		child.queue_free()
	for line in summary["lines"]:
		var label := UiTheme.label("• " + String(line), 20)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(700, 0)
		_away_lines.add_child(label)
	_away.visible = true


func is_story_open() -> bool:
	return _away.visible
