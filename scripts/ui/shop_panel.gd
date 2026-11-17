class_name ShopPanel
extends Control
## The Village Shop: the Shop button (top right, under Actions) opens it.
## Your Village Credits are always shown at the top; tabs hold what credits
## buy (supplies, missing building materials, furniture, animals, unlocks)
## and every way to earn more (daily challenges, achievements, places to
## discover, coming back each day, and an optional short ad: its reward is
## shown before you choose, and it's paid only once the ad has been watched).
##
## While the Shop is open a small banner ad may show at the very bottom of
## the screen; the panel moves up so the banner never covers it.

static var instance: ShopPanel

const TABS := [["supplies", "Supplies"], ["building", "Building"], ["furniture", "Furniture"],
	["animals", "Animals"], ["unlocks", "Unlocks"], ["earn", "Earn"]]
const BANNER_OWNER := "shop"
const PANEL_WIDTH := 900.0

var _button: Button
var _panel: PanelContainer
var _balance: Label
var _scroll: ScrollContainer
var _pages: Dictionary = {}
var _tab_buttons: Dictionary = {}
var tab: String = "supplies"
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
	_panel.name = "ShopWindow"
	_panel.visible = false
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	_panel.size = Vector2(PANEL_WIDTH, 0)
	_panel.add_theme_stylebox_override("panel", UiTheme._box(Color(0.13, 0.1, 0.08, 0.98), 14))
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	box.add_child(header)
	var title := UiTheme.label("Village Shop", 30, UiTheme.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_balance = UiTheme.label("", 26, UiTheme.ACCENT)
	_balance.name = "Balance"
	header.add_child(_balance)
	var close := UiTheme.button("Close", 120)
	close.name = "CloseShop"
	close.pressed.connect(close_shop)
	header.add_child(close)

	var tabs := HBoxContainer.new()
	tabs.name = "Tabs"
	tabs.add_theme_constant_override("separation", 6)
	box.add_child(tabs)
	for t in TABS:
		var b := UiTheme.button(t[1], 140)
		b.name = "Tab_" + t[0]
		b.toggle_mode = true
		b.pressed.connect(show_tab.bind(t[0]))
		tabs.add_child(b)
		_tab_buttons[t[0]] = b

	_scroll = ScrollContainer.new()
	_scroll.name = "ShopScroll"
	_scroll.custom_minimum_size = Vector2(PANEL_WIDTH - 20, 360)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_scroll)
	var pages := VBoxContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(pages)
	for t in TABS:
		var page := VBoxContainer.new()
		page.name = "Page_" + t[0]
		page.add_theme_constant_override("separation", 6)
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pages.add_child(page)
		_pages[t[0]] = page

	# Supplies (a fixed list of bundles).
	var supplies: VBoxContainer = _pages["supplies"]
	supplies.add_child(_note("Bundles of materials, delivered straight to your stores."))
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	supplies.add_child(_list)
	var wardrobe := UiTheme.button("Wardrobe: clothes and hair", 420)
	wardrobe.name = "WardrobeButton"
	wardrobe.pressed.connect(func():
		close_shop()
		if WardrobePanel.instance:
			WardrobePanel.instance.open())
	supplies.add_child(wardrobe)

	# Animals.
	var animals: VBoxContainer = _pages["animals"]
	animals.add_child(_note("Each animal is bought on its own; pens and stables are built empty."))
	_animals = GridContainer.new()
	_animals.name = "Animals"
	_animals.columns = 2
	_animals.add_theme_constant_override("h_separation", 8)
	_animals.add_theme_constant_override("v_separation", 6)
	animals.add_child(_animals)

	# Earn: the ad button lives here (its text says what it gives).
	_ad_button = UiTheme.button("", 600)
	_ad_button.name = "AdButton"
	_ad_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ad_button.pressed.connect(func(): AdRewards.show_for(&"credits"))

	_status = UiTheme.label("", 17)
	_status.name = "Status"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(PANEL_WIDTH - 40, 0)
	box.add_child(_status)

	AdRewards.ad_failed.connect(func(reason: String):
		if is_open():
			_status.text = reason)
	AdRewards.reward_granted.connect(func(_r):
		if is_open():
			_refresh())
	AdRewards.banner_changed.connect(func(_v): _layout())
	get_viewport().size_changed.connect(_layout)


func _exit_tree() -> void:
	if instance == self:
		instance = null
	AdRewards.hide_banner(BANNER_OWNER)


func _note(text: String) -> Label:
	var label := UiTheme.label(text, 17, UiTheme.MUTED)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(PANEL_WIDTH - 60, 0)
	return label


func _heading(text: String) -> Label:
	return UiTheme.label(text, 21, UiTheme.ACCENT)


func is_open() -> bool:
	return _panel.visible


func toggle() -> void:
	if is_open():
		close_shop()
	else:
		open_shop()


func open_shop(start_tab: String = "") -> void:
	_panel.visible = true
	_status.text = ""
	if start_tab != "":
		tab = start_tab
	_panel.move_to_front()
	AdRewards.show_banner(BANNER_OWNER)
	show_tab(tab)


func close_shop() -> void:
	_panel.visible = false
	AdRewards.hide_banner(BANNER_OWNER)


func show_tab(id: String) -> void:
	tab = id
	for key in _pages:
		(_pages[key] as Control).visible = key == id
		(_tab_buttons[key] as Button).button_pressed = key == id
	_scroll.scroll_vertical = 0
	_refresh()


## Keeps the window centred in the space above the banner (if one shows).
func _layout() -> void:
	if not is_instance_valid(_panel):
		return
	var screen := get_viewport_rect().size
	var banner := AdRewards.banner_height()
	var room := screen.y - banner - 16.0
	_scroll.custom_minimum_size.y = clampf(room - 250.0, 180.0, 380.0)
	_panel.reset_size()
	var size := _panel.get_combined_minimum_size()
	_panel.size = size
	_panel.position = Vector2((screen.x - size.x) * 0.5, maxf(8.0, (room - size.y) * 0.5))


func _process(delta: float) -> void:
	var exploring := GameManager.camera_mode == GameManager.CameraMode.EXPLORATION
	var placing := BuildMode.instance != null and BuildMode.instance.active
	_button.visible = exploring and not GameManager.is_in_conversation() and not placing
	if not _button.visible and is_open():
		close_shop()
	if is_open():
		_layout()
		_refresh_timer -= delta
		if _refresh_timer <= 0.0:
			_refresh_timer = 1.0
			_update_balance()
			if tab == "earn":
				_refresh_ad()


func _update_balance() -> void:
	var credits := VillageCredits.instance
	_balance.text = "%d Village Credits" % (credits.balance if credits else 0)


func _balance_now() -> int:
	return VillageCredits.instance.balance if VillageCredits.instance else 0


static func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _refresh() -> void:
	_update_balance()
	_refresh_supplies()
	match tab:
		"building":
			_refresh_building()
		"furniture":
			_refresh_furniture()
		"animals":
			_refresh_animals()
		"unlocks":
			_refresh_unlocks()
		"earn":
			_refresh_earn()


func _refresh_supplies() -> void:
	_clear(_list)
	var credits := VillageCredits.instance
	var balance := _balance_now()
	for item: Dictionary in EconomyConfig.SHOP:
		var b := UiTheme.button("%s  (+%s)  ·  %d credits" % [item["name"], GameState.cost_text(item["items"]), int(item["price"])], PANEL_WIDTH - 60)
		b.name = "Buy_" + String(item["id"])
		b.disabled = balance < int(item["price"])
		b.pressed.connect(func():
			if credits and credits.buy_supplies(String(item["id"])):
				_status.text = "Bought %s." % String(item["name"]).to_lower()
			_refresh())
		_list.add_child(b)


## Things to build: buy just the materials you're missing.
const BUILD_KITS := [&"house", &"house_medium", &"house_large", &"manor", &"animal_pen", &"stable", &"chicken_coop", &"well", &"market_stall"]


func _refresh_building() -> void:
	var page: VBoxContainer = _pages["building"]
	_clear(page)
	var credits := VillageCredits.instance
	page.add_child(_note("Short of materials? Buy exactly what's missing for a building or an expansion, then build it as usual."))
	var rows: Array = []
	# Expanding your houses (the next size up).
	var seen := {}
	if StructureManager.instance:
		for structure in StructureManager.instance.structures():
			if not (structure is PlacedStructure) or not structure.is_complete():
				continue
			var type: StringName = structure.get_type()
			var next := HouseDesigns.next_size(type)
			if next == &"" or seen.has(type):
				continue
			seen[type] = true
			rows.append(["Expand_" + String(type), "Expand a %s to a %s" % [String(StructureCatalog.info(type)["name"]).to_lower(),
				String(StructureCatalog.info(next)["name"]).to_lower()], BuildMode.upgrade_cost(structure)])
	for type in BUILD_KITS:
		var info := StructureCatalog.info(type)
		rows.append(["Kit_" + String(type), "A %s" % String(info["name"]).to_lower(), info["cost"]])
	for row in rows:
		var cost: Dictionary = row[2]
		var need := VillageCredits.missing(cost)
		var price := EconomyConfig.credits_for(need)
		var text := "%s  (needs %s)" % [row[1], GameState.cost_text(cost)]
		text += "\n" + ("You have everything for this." if need.is_empty() else "Missing %s  ·  %d credits" % [GameState.cost_text(need), price])
		var b := UiTheme.button(text, PANEL_WIDTH - 60)
		b.name = row[0]
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", 17)
		b.disabled = need.is_empty() or _balance_now() < price
		var what := String(row[1]).to_lower()
		b.pressed.connect(func():
			if credits and credits.buy_missing(cost, what):
				_status.text = "Bought the materials for %s." % what
			_refresh())
		page.add_child(b)


func _refresh_furniture() -> void:
	var page: VBoxContainer = _pages["furniture"]
	_clear(page)
	var credits := VillageCredits.instance
	page.add_child(_note("Furniture and decorations, ready made. They wait in storage: place them from Furnish > Put away. (You can still make them from materials in Furnish.)"))
	var grid := GridContainer.new()
	grid.name = "Furniture"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	page.add_child(grid)
	for type in FurnitureCatalog.ORDER:
		var info := FurnitureCatalog.info(type)
		var price := VillageCredits.furniture_price(type)
		var b := UiTheme.button("%s\n%d credits" % [info["name"], price], 280)
		b.name = "BuyFurniture_" + String(type)
		b.add_theme_font_size_override("font_size", 17)
		b.disabled = _balance_now() < price
		b.pressed.connect(func():
			if credits and not credits.buy_furniture(type).is_empty():
				_status.text = "%s bought: place it from Furnish > Put away." % info["name"]
			_refresh())
		grid.add_child(b)


func _refresh_animals() -> void:
	_clear(_animals)
	var manager := AnimalManager.instance
	for species in AnimalSpecies.SHOP_ORDER:
		var info := AnimalSpecies.info(species)
		var reason := manager.cannot_buy(species) if manager else "Not available here"
		var text := "%s  ·  %d credits" % [info["name"], int(info["price"])]
		text += "\n" + (String(info["about"]) if reason == "" else reason)
		var b := UiTheme.button(text, (PANEL_WIDTH - 70) * 0.5)
		b.name = "BuyAnimal_" + String(species)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", 17)
		b.disabled = reason != ""
		b.pressed.connect(func():
			if manager and not manager.buy(species).is_empty():
				_status.text = "%s is on the way to their new home." % String(info["name"])
			_refresh())
		_animals.add_child(b)


func _refresh_unlocks() -> void:
	var page: VBoxContainer = _pages["unlocks"]
	_clear(page)
	var credits := VillageCredits.instance
	page.add_child(_note("Extra paints for your houses, unlocked for good. Once unlocked they appear in Design and Redecorate. Everything the game always had stays free."))
	for u in HouseDesigns.PAINT_UNLOCKS:
		var id := String(u["id"])
		var owned := credits != null and credits.owns(id)
		var b := UiTheme.button("%s  ·  %s" % [u["name"], "Unlocked" if owned else "%d credits" % int(u["price"])], PANEL_WIDTH - 60)
		b.name = "Unlock_" + id
		b.disabled = owned or _balance_now() < int(u["price"])
		b.pressed.connect(func():
			if credits and credits.buy_unlock(id, int(u["price"]), String(u["name"])):
				_status.text = "%s unlocked: find it in Design." % u["name"]
			_refresh())
		page.add_child(b)
	page.add_child(_note("Clothes and hairstyles are in the Wardrobe (Supplies tab)."))


func _refresh_earn() -> void:
	var page: VBoxContainer = _pages["earn"]
	if _ad_button.get_parent():
		_ad_button.get_parent().remove_child(_ad_button)  # kept, not freed with the page
	_clear(page)
	var rewards := CreditRewards.instance
	page.add_child(_heading("Today's challenges  (+%d each, +%d for all three)" % [int(EconomyConfig.EARN["challenge"]), int(EconomyConfig.EARN["challenges_all"])]))
	if rewards:
		for c in rewards.todays_challenges():
			var id := String(c["id"])
			var done := rewards.challenge_done(id)
			var have := int(c["target"]) if done else int(rewards.progress.get(id, 0))
			var line := UiTheme.label("%s  %s   %d / %d" % ["[done]" if done else "[    ]", String(c["text"]) % int(c["target"]), have, int(c["target"])], 18,
				UiTheme.ACCENT if done else Color(0.92, 0.9, 0.86))
			line.name = "Challenge_" + id
			page.add_child(line)
	page.add_child(_heading("Optional: watch a short ad  (up to %d a day)" % AdRewards.MAX_PER_DAY))
	page.add_child(_ad_button)
	var gift := DailyGift.instance
	page.add_child(_heading("Coming back"))
	page.add_child(_note("A gift and +%d credits every day you visit. Days in a row add a bonus (+3 on day 3, +10 on day 7, then +10 each week), and some days are lucky (+%d). Missing a day never takes anything away.%s" % [
		int(EconomyConfig.EARN["daily_gift"]), EconomyConfig.LUCKY_CREDITS,
		"  Your streak: %d day%s." % [gift.streak, "" if gift.streak == 1 else "s"] if gift else ""]))
	if rewards:
		page.add_child(_heading("Places discovered: %d of %d  (+%d each)" % [rewards.discovered_count(), CreditRewards.PLACES.size(), int(EconomyConfig.EARN["discovery"])]))
		var names := PackedStringArray()
		for place in CreditRewards.PLACES:
			names.append(String(place["name"]) if rewards.is_discovered(String(place["id"])) else "???")
		page.add_child(_note(", ".join(names)))
		page.add_child(_heading("Achievements"))
		var grid := GridContainer.new()
		grid.name = "Achievements"
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 16)
		page.add_child(grid)
		for a in CreditRewards.ACHIEVEMENTS:
			var got := rewards.is_achieved(String(a["id"]))
			var have := mini(rewards.stat(String(a["stat"])), int(a["target"]))
			var label := UiTheme.label("%s %s: %s (%s)  +%d" % ["[done]" if got else "", a["name"], a["text"],
				"done" if got else "%d/%d" % [have, int(a["target"])], int(a["credits"])], 16, UiTheme.ACCENT if got else UiTheme.MUTED)
			label.custom_minimum_size = Vector2((PANEL_WIDTH - 80) * 0.5, 0)
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			grid.add_child(label)
	page.add_child(_heading("Also"))
	page.add_child(_note("Reaching goals (+%d), helping villagers (+%d), clearing the woods (+%d), finding chests (+%d) and festival goals (+%d)." % [
		int(EconomyConfig.EARN["objective"]), int(EconomyConfig.EARN["request"]), int(EconomyConfig.EARN["woods"]),
		int(EconomyConfig.EARN["chest"]), int(EconomyConfig.EARN["festival_goal"])]))
	_refresh_ad()


func _refresh_ad() -> void:
	var reason := AdRewards.unavailable_reason()
	_ad_button.disabled = reason != ""
	if reason == "":
		_ad_button.text = "Watch a short ad: +%d credits  (%d of %d left today)" % [EconomyConfig.AD_CREDITS, AdRewards.remaining_today(), AdRewards.MAX_PER_DAY]
	else:
		_ad_button.text = "Ad (+%d credits): %s" % [EconomyConfig.AD_CREDITS, reason.trim_suffix(".")]
