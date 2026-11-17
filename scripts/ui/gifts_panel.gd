class_name GiftsPanel
extends Control
## The Gifts button and panel: watch a short ad to receive a gift for the
## village. Always optional; the panel says how many are left today.

var _button: Button
var _panel: PanelContainer
var _list: VBoxContainer
var _status: Label
var _refresh_timer: float = 0.0


func _ready() -> void:
	name = "GiftsPanel"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_button = UiTheme.button("Gifts", 120)
	_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_button.offset_top = 152
	_button.offset_right = -152
	_button.offset_left = -272
	_button.pressed.connect(toggle)
	add_child(_button)

	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.custom_minimum_size = Vector2(700, 0)
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_panel.add_child(box)
	box.add_child(UiTheme.label("Gifts for the village", 30, UiTheme.ACCENT))
	var intro := UiTheme.label("Watch a short video ad to receive a gift. It's optional: the game is complete without it.", 17, UiTheme.MUTED)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(660, 0)
	box.add_child(intro)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	box.add_child(_list)
	_status = UiTheme.label("", 18)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(660, 0)
	box.add_child(_status)
	var close := UiTheme.button("Close", 140)
	close.pressed.connect(func(): _panel.visible = false)
	box.add_child(close)

	AdRewards.reward_granted.connect(func(_r):
		_panel.visible = false)
	AdRewards.ad_failed.connect(func(reason):
		_status.text = reason
		refresh())
	AdRewards.availability_changed.connect(refresh)


func is_open() -> bool:
	return _panel.visible


func toggle() -> void:
	_panel.visible = not _panel.visible
	if _panel.visible:
		_status.text = ""
		refresh()


func refresh() -> void:
	if not _panel.visible:
		return
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var reason := AdRewards.unavailable_reason()
	for id in AdRewards.REWARDS:
		var info: Dictionary = AdRewards.REWARDS[id]
		var blocked := VillageGifts.blocked_reason(id)
		var button := UiTheme.button("%s\n%s" % [info["title"], blocked if blocked != "" else info["text"]], 660)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(660, 64)
		button.add_theme_font_size_override("font_size", 19)
		button.disabled = reason != "" or blocked != ""
		button.pressed.connect(AdRewards.show_for.bind(id))
		_list.add_child(button)
	if reason != "":
		_status.text = reason
	elif _status.text == "":
		_status.text = "%d gift%s left today." % [AdRewards.remaining_today(), "" if AdRewards.remaining_today() == 1 else "s"]


func _process(delta: float) -> void:
	var exploring := GameManager.camera_mode == GameManager.CameraMode.EXPLORATION
	var placing := BuildMode.instance != null and BuildMode.instance.active
	_button.visible = exploring and not GameManager.is_in_conversation() and not placing and AdRewards.provider != AdRewards.Provider.NONE
	if not _button.visible:
		_panel.visible = false
	if _panel.visible:
		_refresh_timer -= delta
		if _refresh_timer <= 0.0:
			_refresh_timer = 1.0
			var keep := _status.text
			refresh()
			if AdRewards.is_available() and keep != "" and not keep.ends_with("left today."):
				_status.text = keep
