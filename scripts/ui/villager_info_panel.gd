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
## Live close-up of the selected villager's face (rendered only while shown).
var _portrait_view: SubViewport
var _portrait_camera: Camera3D
var _portrait_light: OmniLight3D


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
	_build_portrait(box)
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


func _build_portrait(parent: Control) -> void:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(340, 240)
	parent.add_child(frame)
	var container := SubViewportContainer.new()
	container.stretch = true
	container.custom_minimum_size = Vector2(320, 220)
	frame.add_child(container)
	_portrait_view = SubViewport.new()
	_portrait_view.size = Vector2i(320, 220)
	_portrait_view.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_portrait_view.msaa_3d = Viewport.MSAA_2X
	container.add_child(_portrait_view)
	_portrait_camera = Camera3D.new()
	_portrait_camera.fov = 28.0
	_portrait_camera.near = 0.05
	_portrait_camera.far = 30.0
	_portrait_view.add_child(_portrait_camera)
	_portrait_light = OmniLight3D.new()
	_portrait_light.light_color = Color(1.0, 0.94, 0.86)
	_portrait_light.light_energy = 0.7
	_portrait_light.omni_range = 1.6
	_portrait_view.add_child(_portrait_light)


func _update_portrait() -> void:
	if _villager == null or not is_instance_valid(_villager) or not _villager.visible:
		return
	var face: Vector3 = _villager.model.get_face_position()
	var facing: Vector3 = _villager.global_transform.basis.z
	facing.y = 0.0
	facing = facing.normalized()
	var side := facing.cross(Vector3.UP)
	var eye := face + facing * 0.85 + side * 0.18 + Vector3(0, 0.02, 0)
	_portrait_camera.global_transform = Transform3D(Basis.looking_at(face - Vector3(0, 0.06, 0) - eye, Vector3.UP), eye)
	_portrait_light.global_position = eye + Vector3(0, 0.3, 0)


func _on_villager_selected(villager) -> void:
	_villager = villager
	visible = villager != null
	if visible:
		_refresh()


func _process(delta: float) -> void:
	_portrait_light.visible = visible
	if not visible:
		return
	_update_portrait()
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
	var mind: VillagerMind = _villager.mind
	var subject := GameManager.PLAYER_ID
	var times := mind.get_familiarity(subject)
	if times == 0:
		_memory.text = "You haven't spoken yet."
		return
	var text := "Feels about you: %s (warmth %+d, trust %+d)" % [mind.opinion_label(subject), int(mind.get_affection(subject)), int(mind.get_trust(subject))]
	var deeds := mind.memory.find("deed", subject)
	var heard := mind.memory.find("heard", subject)
	if not deeds.is_empty():
		text += "\nRemembers you %s." % DialogueService.unpack_deed(String(deeds[deeds.size() - 1]["detail"]))["text"]
	if not heard.is_empty():
		var parts := String(heard[heard.size() - 1]["detail"]).split("|")
		if parts.size() >= 2:
			var source = GameManager.get_villager(StringName(parts[0]))
			text += "\nHeard from %s that you %s." % [source.data.display_name if source else parts[0], parts[1]]
	_memory.text = text
