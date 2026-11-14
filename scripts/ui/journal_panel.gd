class_name JournalPanel
extends PanelContainer
## The Journal: the goal you're on (what to do next, what it needs, where,
## with which tool, and what it brings), your missions, everything you can do
## (and what opens the rest), and a reminder of the controls. Opened by
## tapping the goal card (top left) or J on a keyboard.

static var instance: JournalPanel
var _text: RichTextLabel


func _ready() -> void:
	name = "JournalPanel"
	instance = self
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	custom_minimum_size = Vector2(820, 600)
	# Solid, so notices and tips behind it don't show through the text.
	add_theme_stylebox_override("panel", UiTheme._box(Color(0.13, 0.1, 0.08, 0.98), 14))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	var title := UiTheme.label("Journal", 30, UiTheme.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := UiTheme.button("Close", 140)
	close.pressed.connect(func(): visible = false)
	header.add_child(close)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = false
	_text.scroll_active = true
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.add_theme_font_size_override("normal_font_size", 19)
	_text.add_theme_font_size_override("bold_font_size", 21)
	box.add_child(_text)


func _exit_tree() -> void:
	if instance == self:
		instance = null


func toggle() -> void:
	visible = not visible
	if visible:
		move_to_front()
		refresh()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.physical_keycode == KEY_J and not GameManager.is_in_conversation():
		toggle()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if visible and GameManager.is_in_conversation():
		visible = false


func refresh() -> void:
	_text.text = build_text()


## The whole journal as BBCode (also read by tests).
static func build_text() -> String:
	var gold := "#f0c060"
	var dim := "#b8a890"
	var out := PackedStringArray()
	# --- Now ---
	out.append("[b][color=%s]Now[/color][/b]" % gold)
	var guide := Guide.instance
	if guide:
		guide.refresh()
	if not GameState.is_week_complete():
		var objective := GameState.current_objective()
		out.append("[b]Day %d · %s[/b]   %s" % [int(objective["day"]), objective["title"], GameState.objective_progress()])
	elif Thornwood.instance and Thornwood.instance.mission_active():
		out.append("[b]Mission: the thornlings in the west woods[/b]")
	else:
		out.append("[b]Your first week is complete.[/b] The village is yours to shape.")
	if guide and guide.step != "":
		out.append("Next: %s" % guide.step)
		var details := PackedStringArray()
		if guide.wanted_build != &"":
			details.append("Needs %s" % GameState.cost_text(StructureCatalog.info(guide.wanted_build)["cost"]))
		if guide.tool != "":
			details.append("Tool: %s" % guide.tool)
		if guide.target != Vector3.INF and GameManager.player:
			details.append("Where: %s, %d m away (follow the gold marker)" % [guide.target_label, int(GameManager.player.global_position.distance_to(guide.target))])
		if not details.is_empty():
			out.append("[color=%s]%s[/color]" % [dim, "  ·  ".join(details)])
		var reward := guide.reward_text()
		if reward != "":
			out.append("Reward: %s" % reward)
	out.append("")
	# --- Missions ---
	out.append("[b][color=%s]Missions[/color][/b]" % gold)
	var missions := 0
	if RequestBoard.instance:
		for request in RequestBoard.instance.open_requests():
			out.append("• %s" % String(request.get("summary", request.get("text", "A villager's request"))))
			missions += 1
	if Thornwood.instance and Thornwood.instance.mission_active():
		out.append("• Chase the thornlings out of the west woods (for Tomas).  Reward: +%s" % GameState.cost_text(Thornwood.FIRST_REWARD))
		missions += 1
	if Festival.instance and Festival.instance.is_active():
		var festival := Festival.instance.current()
		for goal: Dictionary in festival["goals"]:
			var done := Festival.instance.done.has(String(goal["id"]))
			out.append("• %s: %s  %s" % [festival["name"], goal["text"], "(done)" if done else "(%d / %d)" % [Festival.instance.goal_progress(String(goal["id"])), int(goal["goal"])]])
			missions += 1
	if missions == 0:
		out.append("[color=%s]No missions right now. Talk to people with a ! over them.[/color]" % dim)
	out.append("")
	# --- What you can do ---
	out.append("[b][color=%s]What you can do  (%d / %d open)[/color][/b]" % [gold, Activities.open_count(), Activities.LIST.size()])
	for activity: Dictionary in Activities.LIST:
		var id := String(activity["id"])
		if Activities.unlocked(id):
			var extra := Activities.progress(id)
			out.append("[b]%s[/b]%s — %s" % [activity["name"], "  (%s)" % extra if extra != "" else "", activity["how"]])
			var where := "Where: %s" % activity["where"]
			if String(activity["tool"]) != "":
				where += "  ·  Tool: %s" % activity["tool"]
			out.append("[color=%s]   %s[/color]" % [dim, where])
	var locked := Activities.LIST.filter(func(a): return not Activities.unlocked(String(a["id"])))
	if not locked.is_empty():
		out.append("[color=%s]Coming later:[/color]" % dim)
		for activity: Dictionary in locked:
			out.append("[color=%s]   %s: %s[/color]" % [dim, activity["name"], Activities.unlock_hint(String(activity["id"]))])
	out.append("")
	# --- Controls ---
	out.append("[b][color=%s]Controls[/color][/b]" % gold)
	out.append("Left stick: walk (push to the edge to run).  Drag the right side: look.  Pinch: zoom.")
	out.append("The round button on the right does what you're next to: Talk, Chop, Mine, Build, Enter, Fish...")
	out.append("Build (top right): make things.  Actions: sit, sleep, wave, dance.  People: everyone in the village.  Village View: see it all from above.")
	if PlayerCombat.is_armed():
		out.append("In a fight: Attack, Block (hold), Dodge, and Eat a stew to heal.")
	return "\n".join(out)
