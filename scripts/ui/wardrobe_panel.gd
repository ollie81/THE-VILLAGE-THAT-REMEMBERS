class_name WardrobePanel
extends PanelContainer
## The Wardrobe: change your outfit, hair, hat and extras, and dye your
## clothes, with a live 3D preview that turns (drag it to turn it yourself).
## You can try on anything; items you don't own yet are bought with Village
## Credits when you tap Wear, and items earned by play say how to earn them.

static var instance: WardrobePanel

const PREVIEW_SIZE := Vector2i(340, 500)
const REBUILD_DELAY := 0.25

var look: CharacterAppearance
## Rare dyes chosen this time: field -> dye id (they're bought on Wear).
var dyes_used: Dictionary = {}
var tab: String = "Outfit"
var colour_target: String = "shirt_color"

var _viewport: SubViewport
var _stage: Node3D
var _preview: CharacterModel
var _rebuild_timer: float = -1.0
var _spin: float = 0.0
var _dragging: bool = false
var _tabs: HBoxContainer
var _content: VBoxContainer
var _credits_label: Label
var _status: Label
var _wear: Button


func _ready() -> void:
	name = "WardrobePanel"
	instance = self
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	custom_minimum_size = Vector2(1180, 650)
	add_theme_stylebox_override("panel", UiTheme._box(Color(0.13, 0.1, 0.08, 0.98), 14))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	add_child(row)
	row.add_child(_build_preview())
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	row.add_child(right)
	var header := HBoxContainer.new()
	right.add_child(header)
	var title := UiTheme.label("Wardrobe", 30, UiTheme.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_credits_label = UiTheme.label("", 20, UiTheme.ACCENT)
	header.add_child(_credits_label)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 6)
	right.add_child(_tabs)
	for t in WardrobeCatalog.TABS:
		var b := UiTheme.button(t, 140)
		b.name = "Tab" + t
		b.pressed.connect(func():
			tab = t
			_refresh())
		_tabs.add_child(b)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 8)
	scroll.add_child(_content)
	_status = UiTheme.label("", 17, UiTheme.MUTED)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_status)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	right.add_child(footer)
	_wear = UiTheme.button("Wear it", 300)
	_wear.name = "WearButton"
	_wear.pressed.connect(wear)
	footer.add_child(_wear)
	var undo := UiTheme.button("Start again", 180)
	undo.pressed.connect(func(): open())
	footer.add_child(undo)
	var close := UiTheme.button("Close", 140)
	close.pressed.connect(func(): visible = false)
	footer.add_child(close)


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _build_preview() -> Control:
	var frame := SubViewportContainer.new()
	frame.stretch = true
	frame.custom_minimum_size = Vector2(PREVIEW_SIZE)
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.gui_input.connect(_on_preview_input)
	_viewport = SubViewport.new()
	_viewport.size = PREVIEW_SIZE
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	frame.add_child(_viewport)
	_stage = Node3D.new()
	_viewport.add_child(_stage)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.32, 0.27, 0.22)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.95, 0.9, 0.85)
	environment.ambient_light_energy = 0.55
	var world_env := WorldEnvironment.new()
	world_env.environment = environment
	_viewport.add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.7, 0.5, 0.0)
	sun.light_energy = 1.1
	_viewport.add_child(sun)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 1.0, 3.3)
	camera.fov = 38.0
	_viewport.add_child(camera)
	camera.look_at_from_position(camera.position, Vector3(0, 0.88, 0))
	var floor_mesh := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.75
	disc.bottom_radius = 0.75
	disc.height = 0.04
	floor_mesh.mesh = disc
	floor_mesh.position.y = -0.02
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.5, 0.42, 0.32)
	floor_mesh.material_override = floor_material
	_viewport.add_child(floor_mesh)
	return frame


## Opens with what the player is wearing now.
func open() -> void:
	var player = GameManager.player
	if player == null:
		return
	look = AppearanceCodec.from_dict(AppearanceCodec.to_dict(player.model.appearance))
	dyes_used.clear()
	_spin = 0.0
	visible = true
	move_to_front()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_rebuild_preview()
	_refresh()


func _process(delta: float) -> void:
	if not visible:
		if _viewport and _viewport.render_target_update_mode != SubViewport.UPDATE_DISABLED:
			_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	if GameManager.is_in_conversation():
		visible = false
		return
	if _rebuild_timer >= 0.0:
		_rebuild_timer -= delta
		if _rebuild_timer < 0.0:
			_rebuild_preview()
	if not _dragging:
		_spin += delta * 0.45
	if _preview:
		_preview.rotation.y = _spin


func _on_preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_dragging = (event as InputEventMouseButton).pressed
	elif event is InputEventScreenTouch:
		_dragging = (event as InputEventScreenTouch).pressed
	elif event is InputEventMouseMotion and _dragging:
		_spin += (event as InputEventMouseMotion).relative.x * 0.012
	elif event is InputEventScreenDrag:
		_spin += (event as InputEventScreenDrag).relative.x * 0.012


func _rebuild_preview() -> void:
	if _preview:
		_preview.queue_free()
	_preview = CharacterModel.new(AppearanceCodec.from_dict(AppearanceCodec.to_dict(look)))
	_preview.name = "Preview"
	_stage.add_child(_preview)
	_preview.rotation.y = _spin


func _changed() -> void:
	_rebuild_timer = REBUILD_DELAY
	_refresh()


## Tries item `id` on (also used by tests).
func try_on(id: String) -> void:
	WardrobeCatalog.apply(look, id)
	_changed()


## Dyes the current colour target with dye `id` (also used by tests).
func dye(id: String) -> void:
	var entry := WardrobeCatalog.item(id)
	if entry.is_empty():
		return
	look.set(colour_target, entry["color"])
	if WardrobeCatalog.is_owned(id):
		dyes_used.erase(colour_target)
	else:
		dyes_used[colour_target] = id
	_changed()


func _set_hair_colour(color: Color) -> void:
	look.hair_color = color
	_changed()


## What wearing this look would need: credits, and anything play-only.
func shopping() -> Dictionary:
	var unowned := WardrobeCatalog.unowned_in(look, dyes_used.values())
	var locked := unowned.filter(func(id): return int(WardrobeCatalog.item(String(id)).get("price", 0)) == 0)
	return {"buy": unowned.filter(func(id): return not locked.has(id)), "locked": locked,
		"cost": WardrobeCatalog.cost_of(unowned.filter(func(id): return not locked.has(id)))}


## Buys what's needed and dresses the player (also used by tests).
func wear() -> bool:
	var need := shopping()
	var credits := VillageCredits.instance
	if not need["locked"].is_empty():
		_status.text = "Not unlocked yet: %s." % _unlock_hint(String(need["locked"][0]))
		return false
	if int(need["cost"]) > 0:
		if credits == null or not credits.spend(int(need["cost"])):
			_status.text = "You need %d Village Credits for this outfit (you have %d)." % [int(need["cost"]), credits.balance if credits else 0]
			return false
		for id in need["buy"]:
			credits.unlock(String(id))
	var player = GameManager.player
	if player:
		player.set_appearance(AppearanceCodec.from_dict(AppearanceCodec.to_dict(look)))
	GameManager.notify("New look!" if int(need["cost"]) == 0 else "New look! (%d Village Credits)" % int(need["cost"]))
	Sounds.play("built", null, -6.0)
	SaveService.save_game()
	visible = false
	return true


func _unlock_hint(id: String) -> String:
	var entry := WardrobeCatalog.item(id)
	return "%s (%s)" % [entry.get("name", id), entry.get("unlock", {}).get("hint", "earned by play")]


# --- The lists ---------------------------------------------------------------------------

func _refresh() -> void:
	var credits := VillageCredits.instance
	_credits_label.text = "%d Village Credits" % (credits.balance if credits else 0)
	for b in _tabs.get_children():
		(b as Button).modulate = Color(1.25, 1.15, 0.9) if b.name == "Tab" + tab else Color.WHITE
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	match tab:
		"Colours":
			_colour_page()
		_:
			_item_grid(WardrobeCatalog.items_in(tab))
			if tab == "Hair":
				_content.add_child(UiTheme.label("Hair colour", 20))
				var swatches := _swatch_row()
				for c in WardrobeCatalog.HAIR_COLOURS:
					swatches.add_child(_swatch(c, "", look.hair_color.is_equal_approx(c), _set_hair_colour.bind(c)))
	var need := shopping()
	if not need["locked"].is_empty():
		_wear.text = "Locked"
		_wear.disabled = true
		_status.text = "Not unlocked yet: %s." % _unlock_hint(String(need["locked"][0]))
	elif int(need["cost"]) > 0:
		_wear.text = "Buy and wear (%d credits)" % int(need["cost"])
		_wear.disabled = credits == null or not credits.can_afford(int(need["cost"]))
		_status.text = "New: %s." % ", ".join(need["buy"].map(func(id): return String(WardrobeCatalog.item(String(id)).get("name", id))))
		if _wear.disabled:
			_status.text += "  You have %d credits: earn more by helping villagers, or in Shop." % (credits.balance if credits else 0)
	else:
		_wear.text = "Wear it"
		_wear.disabled = false
		_status.text = "Tap anything to try it on. Drag the picture to turn around."


func _item_grid(items: Array) -> void:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_content.add_child(grid)
	for entry: Dictionary in items:
		var id := String(entry["id"])
		var status := ""
		if WardrobeCatalog.is_worn(look, id):
			status = "Wearing"
		elif not WardrobeCatalog.is_owned(id):
			if int(entry.get("price", 0)) > 0:
				status = "%d credits" % int(entry["price"])
			if entry.has("unlock"):
				status += (" or earn" if status != "" else "Earn by play")
		var b := UiTheme.button("%s\n%s" % [entry["name"], status], 250)
		b.name = "Item_" + id
		b.custom_minimum_size.y = 70
		b.add_theme_font_size_override("font_size", 18)
		if status == "Wearing":
			b.modulate = Color(1.3, 1.2, 0.85)
		b.pressed.connect(try_on.bind(id))
		grid.add_child(b)


func _colour_page() -> void:
	_content.add_child(UiTheme.label("Dye which part?", 20))
	var targets := HFlowContainer.new()
	targets.add_theme_constant_override("h_separation", 6)
	targets.add_theme_constant_override("v_separation", 6)
	_content.add_child(targets)
	for target: Dictionary in WardrobeCatalog.COLOUR_TARGETS:
		var field := String(target["field"])
		if field == "skirt_color" and look.tunic_length < 0.7:
			continue
		if field == "hat_color" and not WardrobeCatalog.ITEMS.any(func(e): return String(e.get("group", "")) == "hat" and e.has("accessory") and look.has_accessory(String(e["accessory"]))):
			continue
		var b := UiTheme.button(String(target["name"]), 170)
		b.name = "Target_" + field
		if field == colour_target:
			b.modulate = Color(1.3, 1.2, 0.85)
		b.pressed.connect(func():
			colour_target = field
			_refresh())
		targets.add_child(b)
	_content.add_child(UiTheme.label("Colours (rare dyes cost credits or are earned)", 18, UiTheme.MUTED))
	var swatches := _swatch_row()
	var current: Variant = look.get(colour_target)
	for entry: Dictionary in WardrobeCatalog.DYES:
		var id := String(entry["id"])
		var label := ""
		if not WardrobeCatalog.is_owned(id):
			label = str(int(entry.get("price", 0))) if int(entry.get("price", 0)) > 0 else "?"
		swatches.add_child(_swatch(entry["color"], label, current is Color and (current as Color).is_equal_approx(entry["color"]), dye.bind(id)))


func _swatch_row() -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	_content.add_child(row)
	return row


func _swatch(color: Color, text: String, selected: bool, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(64, 64)
	b.focus_mode = Control.FOCUS_NONE
	b.text = text
	b.add_theme_font_size_override("font_size", 16)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var box := StyleBoxFlat.new()
		box.bg_color = color
		box.set_corner_radius_all(10)
		box.set_border_width_all(4 if selected else 2)
		box.border_color = Color(1, 0.9, 0.5) if selected else Color(0, 0, 0, 0.5)
		b.add_theme_stylebox_override(state, box)
	b.add_theme_color_override("font_color", Color.WHITE if color.get_luminance() < 0.55 else Color.BLACK)
	b.pressed.connect(on_pressed)
	return b
