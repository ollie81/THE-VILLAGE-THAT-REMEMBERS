class_name ShopPanel
extends Control
## The Shop button (top right, under Actions) and its panel: your Village
## Credits, the Wardrobe, supplies to buy, and how to earn more, including an
## optional short ad (credits are added only once the ad has been watched).

static var instance: ShopPanel

var _button: Button
var _panel: PanelContainer
var _balance: Label
var _list: VBoxContainer
var _animals: GridContainer
var _ad_button: Button
var _status: Label
var _refresh_timer: float = 0.0


func _ready() -> void:
	name = "ShopPanel"
	instance = self
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_button = UiTheme.button("Shop", 120)
	_button.name = "ShopButton"
	_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_button.offset_top = 218
	_button.offset_right = -20
	_button.offset_left = -140
	_button.pressed.connect(toggle)
	add_child(_button)

	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.custom_minimum_size = Vector2(760, 0)
	_panel.add_theme_stylebox_override("panel", UiTheme._box(Color(0.13, 0.1, 0.08, 0.98), 14))
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_panel.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	var title := UiTheme.label("Shop", 30, UiTheme.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_balance = UiTheme.label("", 22, UiTheme.ACCENT)
	header.add_child(_balance)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	box.add_child(top)
	var wardrobe := UiTheme.button("Wardrobe: clothes and hair", 360)
	wardrobe.name = "WardrobeButton"
	wardrobe.pressed.connect(func():
		_panel.visible = false
		if WardrobePanel.instance:
			WardrobePanel.instance.open())
	top.add_child(wardrobe)
	_ad_button = UiTheme.button("", 360)
	_ad_button.name = "AdButton"
	_ad_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ad_button.pressed.connect(func(): AdRewards.show_for(&"credits"))
	top.add_child(_ad_button)
	# Supplies and animals scroll, so the panel fits a phone screen.
	var scroll := ScrollContainer.new()
	scroll.name = "ShopScroll"
	scroll.custom_minimum_size = Vector2(740, 330)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inner)
	inner.add_child(UiTheme.label("Animals  (each one is bought on its own; pens and stables are built empty)", 20))
	_animals = GridContainer.new()
	_animals.name = "Animals"
	_animals.columns = 2
	_animals.add_theme_constant_override("h_separation", 8)
	_animals.add_theme_constant_override("v_separation", 6)
	inner.add_child(_animals)
	inner.add_child(UiTheme.label("Supplies", 20))
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	inner.add_child(_list)
	var earn := UiTheme.label("Earn credits by reaching goals (+%d), helping villagers (+%d), clearing the woods (+%d), finding chests (+%d), festival goals (+%d) and coming back each day (+%d)." % [
		int(EconomyConfig.EARN["objective"]), int(EconomyConfig.EARN["request"]), int(EconomyConfig.EARN["woods"]),
		int(EconomyConfig.EARN["chest"]), int(EconomyConfig.EARN["festival_goal"]), int(EconomyConfig.EARN["daily_gift"])], 16, UiTheme.MUTED)
	earn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	earn.custom_minimum_size = Vector2(720, 0)
	box.add_child(earn)
	_status = UiTheme.label("", 17)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(720, 0)
	box.add_child(_status)
	var close := UiTheme.button("Close", 140)
	close.pressed.connect(func(): _panel.visible = false)
	box.add_child(close)
	AdRewards.ad_failed.connect(func(reason: String):
		if _panel.visible:
			_status.text = reason)
	AdRewards.reward_granted.connect(func(_r):
		if _panel.visible:
			_refresh())


func _exit_tree() -> void:
	if instance == self:
		instance = null


func is_open() -> bool:
	return _panel.visible


func toggle() -> void:
	_panel.visible = not _panel.visible
	if _panel.visible:
		_status.text = ""
		_panel.move_to_front()
		_refresh()


func _process(delta: float) -> void:
	var exploring := GameManager.camera_mode == GameManager.CameraMode.EXPLORATION
	var placing := BuildMode.instance != null and BuildMode.instance.active
	_button.visible = exploring and not GameManager.is_in_conversation() and not placing
	if not _button.visible:
		_panel.visible = false
	if _panel.visible:
		_refresh_timer -= delta
		if _refresh_timer <= 0.0:
			_refresh_timer = 1.0
			_refresh_ad()


func _refresh() -> void:
	var credits := VillageCredits.instance
	var balance := credits.balance if credits else 0
	_balance.text = "%d Village Credits" % balance
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	for item: Dictionary in EconomyConfig.SHOP:
		var b := UiTheme.button("%s  (+%s)  ·  %d credits" % [item["name"], GameState.cost_text(item["items"]), int(item["price"])], 720)
		b.name = "Buy_" + String(item["id"])
		b.disabled = balance < int(item["price"])
		b.pressed.connect(func():
			if credits and credits.buy_supplies(String(item["id"])):
				_status.text = "Bought %s." % String(item["name"]).to_lower()
			_refresh())
		_list.add_child(b)
	_refresh_animals()
	_refresh_ad()


func _refresh_animals() -> void:
	for child in _animals.get_children():
		_animals.remove_child(child)
		child.queue_free()
	var manager := AnimalManager.instance
	for species in AnimalSpecies.SHOP_ORDER:
		var info := AnimalSpecies.info(species)
		var reason := manager.cannot_buy(species) if manager else "Not available here"
		var text := "%s  ·  %d credits" % [info["name"], int(info["price"])]
		text += "\n" + (String(info["about"]) if reason == "" else reason)
		var b := UiTheme.button(text, 360)
		b.name = "BuyAnimal_" + String(species)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", 17)
		b.disabled = reason != ""
		b.pressed.connect(func():
			if manager and not manager.buy(species).is_empty():
				_status.text = "%s is on the way to their new home." % String(info["name"])
			_refresh())
		_animals.add_child(b)


func _refresh_ad() -> void:
	var reason := AdRewards.unavailable_reason()
	_ad_button.disabled = reason != ""
	_ad_button.text = "Watch a short ad: +%d credits" % EconomyConfig.AD_CREDITS if reason == "" else "Ad: %s" % reason.trim_suffix(".")
