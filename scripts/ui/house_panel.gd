class_name HousePanel
extends Control
## The House button (top right, under Furnish) inside a house you built, and
## its panel:
## - who lives here and how many beds there are;
## - give the house to a villager: everyone who could move in, where they
##   live now and whether this house suits them (a bed each, room for their
##   household); choosing one asks for confirmation first;
## - a house you gave away: ask the household to move out (they go back to
##   where they lived before);
## - your own house: invite a friend over.

static var instance: HousePanel

var _button: Button
var _panel: PanelContainer
var _title: Label
var _info: Label
var _list: VBoxContainer
var _confirm: PanelContainer
var _confirm_text: Label
var _confirm_yes: Button
var _status: Label
## The house this panel is about (its structure record).
var record: Dictionary = {}
var _pending: Callable = Callable()


func _ready() -> void:
	name = "HousePanel"
	instance = self
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_button = UiTheme.button("House", 120)
	_button.name = "HouseButton"
	_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_button.offset_top = 350
	_button.offset_right = -20
	_button.offset_left = -140
	_button.pressed.connect(toggle)
	add_child(_button)

	_panel = PanelContainer.new()
	_panel.name = "HouseWindow"
	_panel.visible = false
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.custom_minimum_size = Vector2(820, 0)
	_panel.add_theme_stylebox_override("panel", UiTheme._box(Color(0.13, 0.1, 0.08, 0.98), 14))
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	_title = UiTheme.label("House", 28, UiTheme.ACCENT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	var close := UiTheme.button("Close", 120)
	close.name = "CloseHouse"
	close.pressed.connect(close_panel)
	header.add_child(close)
	_info = UiTheme.label("", 18)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(790, 0)
	box.add_child(_info)
	var scroll := ScrollContainer.new()
	scroll.name = "HouseScroll"
	scroll.custom_minimum_size = Vector2(800, 330)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.name = "People"
	_list.add_theme_constant_override("separation", 6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	_status = UiTheme.label("", 17, UiTheme.MUTED)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(790, 0)
	box.add_child(_status)

	# Confirmation, over the panel.
	_confirm = PanelContainer.new()
	_confirm.name = "Confirm"
	_confirm.visible = false
	_confirm.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_confirm.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_confirm.grow_vertical = Control.GROW_DIRECTION_BOTH
	_confirm.custom_minimum_size = Vector2(620, 0)
	_confirm.add_theme_stylebox_override("panel", UiTheme._box(Color(0.2, 0.15, 0.1, 1.0), 14))
	add_child(_confirm)
	var cbox := VBoxContainer.new()
	cbox.add_theme_constant_override("separation", 12)
	_confirm.add_child(cbox)
	_confirm_text = UiTheme.label("", 21)
	_confirm_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_text.custom_minimum_size = Vector2(590, 0)
	cbox.add_child(_confirm_text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	cbox.add_child(row)
	_confirm_yes = UiTheme.button("Yes", 290)
	_confirm_yes.name = "ConfirmYes"
	_confirm_yes.pressed.connect(func():
		_confirm.visible = false
		if _pending.is_valid():
			_pending.call()
		_pending = Callable()
		_refresh())
	row.add_child(_confirm_yes)
	var no := UiTheme.button("Cancel", 290)
	no.name = "ConfirmNo"
	no.pressed.connect(func():
		_confirm.visible = false
		_pending = Callable())
	row.add_child(no)


func _exit_tree() -> void:
	if instance == self:
		instance = null


## The house you're standing in, if it's one you built ({} otherwise).
static func current_house() -> Dictionary:
	if Interiors.instance == null or not Interiors.instance.is_inside():
		return {}
	var place: String = Interiors.instance.current
	if not place.begins_with("house_"):
		return {}
	return Furnishings.house_of(place)


func is_open() -> bool:
	return _panel.visible


func toggle() -> void:
	if is_open():
		close_panel()
	else:
		open_for(current_house())


func open_for(house: Dictionary) -> void:
	if house.is_empty():
		return
	record = house
	_status.text = ""
	_panel.visible = true
	_panel.move_to_front()
	_refresh()


func close_panel() -> void:
	_panel.visible = false
	_confirm.visible = false
	_pending = Callable()


func _process(_delta: float) -> void:
	var house := current_house()
	var mode := FurnishMode.instance
	_button.visible = not house.is_empty() and (mode == null or (not mode.active and not mode.arranging)) \
		and not GameManager.is_in_conversation()
	if not _button.visible and is_open():
		close_panel()


func _ask(text: String, yes: String, action: Callable) -> void:
	_confirm_text.text = text
	_confirm_yes.text = yes
	_pending = action
	_confirm.visible = true
	_confirm.move_to_front()


static func _home_name(home_id: String) -> String:
	if home_id == "" or home_id == Population.CAMP_ID:
		return "a tent at the camp"
	var house := Population.house_record(home_id)
	if not house.is_empty() and HouseDesigns.is_house(StringName(String(house.get("type", "")))):
		return Population.house_label(house)
	var label := VillageLayout.get_location_label(home_id)
	return label if label != "" else home_id


func _refresh() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	if record.is_empty():
		return
	Furnishings.ensure_furnished(Furnishings.place_of(record))
	var home_id := Population.cottage_home_id(record)
	var type := StringName(String(record["type"]))
	var name_ := String(StructureCatalog.info(type)["name"])
	var given := Population.is_given_house(record)
	var residents := Population.residents_of(home_id).map(func(id): return Population.get_person(String(id)))
	_title.text = Population.house_label(record).capitalize() if given else "Your %s" % name_.to_lower()
	var beds := Population.beds_in(record)
	var cap := int(Population.HOUSE_SIZE_CAPACITY.get(String(type), 2))
	_info.text = "%s · %d bed%s (a double bed sleeps two) · room for up to %d people." % [name_, beds, "" if beds == 1 else "s", cap]
	if given:
		_info.text += "\nLives here: %s." % ", ".join(residents.map(func(p): return p.first_name)) if not residents.is_empty() else "\nNobody lives here right now."
		var back := UiTheme.button("Ask them to move out (the house becomes yours again)", 780)
		back.name = "TakeBack"
		back.pressed.connect(func():
			_ask("Ask %s to move out? They'll go back to where they lived before, and the house will be yours again." % (" and ".join(residents.map(func(p): return p.first_name)) if not residents.is_empty() else "the household"),
				"Yes, ask them", func():
					var moved := Population.take_back_house(record)
					_status.text = "The house is yours again." if moved.is_empty() else "%s moved out." % ", ".join(moved.map(func(p): return p.first_name))))
		_list.add_child(back)
	else:
		_info.text += "\nThis is your house. Give it to a villager, or invite a friend over."
		_list.add_child(UiTheme.label("Invite a friend over", 21, UiTheme.ACCENT))
		var friends := GameManager.villagers.filter(func(v): return is_instance_valid(v) and v.person and v.person.is_resident() and not v.is_leaving())
		friends.sort_custom(func(a, b): return a.mind.get_affection(GameManager.PLAYER_ID) > b.mind.get_affection(GameManager.PLAYER_ID))
		var grid := GridContainer.new()
		grid.name = "Invites"
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		_list.add_child(grid)
		for v in friends.slice(0, 9):
			var why: String = HomeLife.instance.invite_reason(v, home_id) if HomeLife.instance else "Not available"
			var b := UiTheme.button("Invite %s\n%s" % [v.data.display_name, v.mind.opinion_label(GameManager.PLAYER_ID)], 255)
			b.name = "Invite_" + String(v.data.id)
			b.add_theme_font_size_override("font_size", 16)
			b.disabled = why != ""
			b.tooltip_text = why
			b.pressed.connect(func():
				var err: String = HomeLife.instance.invite(v, home_id)
				_status.text = err if err != "" else "%s is coming over. They'll walk here and knock." % v.data.display_name
				_refresh())
			grid.add_child(b)
	_list.add_child(UiTheme.label("Give this house to a villager", 21, UiTheme.ACCENT))
	var perks := UiTheme.label("They'll be close friends with you (+%d), happier at home, thank you with %d Village Credits and something from their trade when they move in, and leave you a gift every %d days." % [
		int(HomeLife.GIVE_AFFECTION), HomeLife.THANKS_CREDITS, HomeLife.GIFT_EVERY_DAYS], 16, UiTheme.MUTED)
	perks.name = "Perks"
	perks.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	perks.custom_minimum_size = Vector2(780, 0)
	_list.add_child(perks)
	for person: Person in Population.eligible_for_house():
		if residents.has(person):
			continue
		var why := Population.house_unsuitable_reason(record, person)
		var household := Population.household_of(person)
		var who := person.first_name if household.size() == 1 else "%s (with %s)" % [person.first_name, ", ".join(household.slice(1).map(func(p): return p.first_name))]
		var text := "%s · %s · lives at %s\n%s" % [who, Professions.label(person.profession), _home_name(person.home),
			"Suitable: a bed for everyone" if why == "" else "Not suitable: " + why]
		var b := UiTheme.button(text, 780)
		b.name = "Give_" + person.id
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", 17)
		b.disabled = why != ""
		b.pressed.connect(func():
			var names: String = " and ".join(household.map(func(p): return p.first_name))
			var own_home := not given and Interiors.resolve("player") == Furnishings.place_of(record)
			_ask("Give this %s to %s?%s They'll move in and walk over to it.%s" % [name_.to_lower(), names,
				"" if household.size() == 1 else " The household moves together.",
				"\nThis is the house you sleep in: you'll need another one of your own." if own_home else ""],
				"Give the house", func():
					var err := Population.give_house(record, person)
					_status.text = err if err != "" else "%s will move in. Watch them walk over!" % names))
		_list.add_child(b)
