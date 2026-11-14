class_name CombatHud
extends Control
## A health bar (when hurt or in a fight) and the current mission card.

var _bar_back: Panel
var _bar: ColorRect
var _bar_label: Label
var _mission: PanelContainer
var _mission_title: Label
var _mission_text: Label

const BAR_WIDTH := 300.0


func _ready() -> void:
	name = "CombatHud"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_back = Panel.new()
	_bar_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_back.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_bar_back.offset_left = -BAR_WIDTH * 0.5 - 6
	_bar_back.offset_right = BAR_WIDTH * 0.5 + 6
	_bar_back.offset_top = 188
	_bar_back.offset_bottom = 220
	add_child(_bar_back)
	_bar = ColorRect.new()
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.position = Vector2(6, 6)
	_bar.size = Vector2(BAR_WIDTH, 20)
	_bar.color = Color(0.85, 0.25, 0.22)
	_bar_back.add_child(_bar)
	_bar_label = UiTheme.label("", 16)
	_bar_label.position = Vector2(10, 4)
	_bar_back.add_child(_bar_label)
	_mission = PanelContainer.new()
	_mission.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mission.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_mission.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_mission.offset_right = -20
	_mission.custom_minimum_size = Vector2(320, 0)
	add_child(_mission)
	var box := VBoxContainer.new()
	_mission.add_child(box)
	_mission_title = UiTheme.label("", 20, UiTheme.ACCENT)
	box.add_child(_mission_title)
	_mission_text = UiTheme.label("", 17)
	_mission_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mission_text.custom_minimum_size = Vector2(300, 0)
	box.add_child(_mission_text)


func _process(_delta: float) -> void:
	var player = GameManager.player
	var exploring := GameManager.camera_mode == GameManager.CameraMode.EXPLORATION and not GameManager.is_in_conversation()
	var combat = player.combat if player and player.get("combat") else null
	_bar_back.visible = exploring and combat != null and (combat.health < PlayerCombat.MAX_HEALTH or combat.in_fight())
	if _bar_back.visible:
		_bar.size.x = BAR_WIDTH * combat.health / PlayerCombat.MAX_HEALTH
		_bar_label.text = "Health %d / %d   Stew: %d" % [int(ceil(combat.health)), int(PlayerCombat.MAX_HEALTH), PlayerCombat.stews()]
	var woods := Thornwood.instance
	_mission.visible = exploring and woods != null and woods.mission_active() and not (Interiors.instance and Interiors.instance.is_inside())
	if _mission.visible:
		_mission_title.text = "Mission: Thornlings"
		var left := woods.remaining()
		_mission_text.text = "Chase the thornlings out of the west woods." + ("  (%d left)" % left if left > 0 else "")
		# Sit under the festival card when there is one.
		var festival := get_parent().find_child("FestivalPanel", false, false) as Control
		_mission.offset_top = 222 + (festival.size.y + 8 if festival and festival.visible else 0)
