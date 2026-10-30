class_name VillagerInfoPanel
extends PanelContainer
## Management-mode card for the selected villager: who they are and what
## they're doing right now.

var _villager = null
var _title: Label
var _role: Label
var _traits: Label
var _activity: Label
var _bio: Label
var _memory: Label
var _refresh_timer: float = 0.0


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BOTH
	offset_right = -20
	custom_minimum_size = Vector2(380, 0)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	_title = UiTheme.label("", 30, UiTheme.ACCENT)
	box.add_child(_title)
	_role = UiTheme.label("", 21, UiTheme.MUTED)
	box.add_child(_role)
	_traits = UiTheme.label("", 20)
	_traits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_traits)
	box.add_child(HSeparator.new())
	_activity = UiTheme.label("", 22)
	_activity.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_activity)
	_bio = UiTheme.label("", 18, UiTheme.MUTED)
	_bio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bio.custom_minimum_size = Vector2(340, 0)
	box.add_child(_bio)
	_memory = UiTheme.label("", 18, UiTheme.ACCENT.darkened(0.15))
	_memory.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_memory)
	var close := UiTheme.button("Close")
	close.pressed.connect(func(): GameManager.select_villager(null))
	box.add_child(close)

	GameManager.villager_selected.connect(_on_villager_selected)


func _on_villager_selected(villager) -> void:
	_villager = villager
	visible = villager != null
	if visible:
		_refresh()


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = 0.5
		_refresh()


func _refresh() -> void:
	if _villager == null or not is_instance_valid(_villager):
		visible = false
		return
	var data: VillagerData = _villager.data
	_title.text = data.display_name
	_role.text = "%s · age %d" % [data.role, data.age]
	_traits.text = ", ".join(data.traits)
	_activity.text = "Now: %s" % _villager.get_activity_description()
	_bio.text = data.biography
	var times: int = _villager.mind.get_familiarity(GameManager.PLAYER_ID)
	if times == 0:
		_memory.text = "You haven't spoken yet."
	else:
		_memory.text = "Remembers %d conversation%s with you." % [times, "" if times == 1 else "s"]
