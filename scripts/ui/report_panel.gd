class_name ReportPanel
extends PanelContainer
## "Report a problem" (in Settings): everything needed to track down a bug
## seen on a phone, in one screen you can copy and paste into a message.
## Which build it is, the phone, screen and renderer, the frame rate (now and
## the lowest in the last minute), where you are in the game, and the last
## errors and warnings from the game's log file.

static var instance: ReportPanel
const LOG_LINES := 30

var _text: TextEdit
## Frame-rate history: one sample a second for the last minute.
static var _fps_samples: Array[int] = []
var _sample_timer: float = 0.0


func _ready() -> void:
	name = "ReportPanel"
	instance = self
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	custom_minimum_size = Vector2(900, 600)
	add_theme_stylebox_override("panel", UiTheme._box(Color(0.13, 0.1, 0.08, 0.98), 14))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	box.add_child(header)
	var title := UiTheme.label("Report a problem", 28, UiTheme.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var copy := UiTheme.button("Copy", 130)
	copy.pressed.connect(func():
		DisplayServer.clipboard_set(_text.text)
		GameManager.notify("Copied. Paste it into your message with a description of what happened."))
	header.add_child(copy)
	var close := UiTheme.button("Close", 130)
	close.pressed.connect(func(): visible = false)
	header.add_child(close)
	box.add_child(UiTheme.label("Tap Copy and paste this into your message, with what you did and what you expected.", 16, UiTheme.MUTED))
	_text = TextEdit.new()
	_text.editable = false
	_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.add_theme_font_size_override("font_size", 16)
	box.add_child(_text)


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _process(delta: float) -> void:
	_sample_timer += delta
	if _sample_timer >= 1.0:
		_sample_timer = 0.0
		_fps_samples.append(int(Engine.get_frames_per_second()))
		if _fps_samples.size() > 60:
			_fps_samples.pop_front()


func open() -> void:
	_text.text = build_report()
	visible = true
	move_to_front()


## The whole report as plain text (also read by tests).
static func build_report() -> String:
	var out := PackedStringArray()
	out.append("THE VILLAGE THAT REMEMBERS  %s" % BuildInfo.text())
	out.append("Device: %s · %s %s · %d CPU cores" % [OS.get_model_name(), OS.get_name(), OS.get_version(), OS.get_processor_count()])
	# A RenderingDevice exists only with Vulkan; without it the phone fell back to OpenGL.
	var renderer := "Vulkan (Mobile)" if RenderingServer.get_rendering_device() != null else "OpenGL (Compatibility)"
	out.append("Renderer: %s · %s · %s" % [renderer, RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_api_version()])
	var window := DisplayServer.window_get_size()
	out.append("Screen: %s · window %dx%d · UI %dx%d · scale %.2f" % [DisplayServer.screen_get_size(), window.x, window.y,
		int(ProjectSettings.get_setting("display/window/size/viewport_width")), int(ProjectSettings.get_setting("display/window/size/viewport_height")),
		DisplayServer.screen_get_scale()])
	var lowest: int = _fps_samples.min() if not _fps_samples.is_empty() else int(Engine.get_frames_per_second())
	out.append("FPS: %d now · lowest %d in the last minute · quality %s · touch controls %s" % [Engine.get_frames_per_second(), lowest,
		GameSettings.quality_name(), "on" if GameSettings.touch_controls_visible() else "off"])
	out.append("Memory: %.0f MB" % (OS.get_static_memory_usage() / 1048576.0))
	out.append("")
	out.append("Game: day %d %s" % [WorldClock.day, WorldClock.get_time_string()])
	if GameState.is_week_complete():
		out.append("Goal: first week complete")
	else:
		var objective := GameState.current_objective()
		out.append("Goal: day %d · %s · %s" % [int(objective["day"]), objective["title"], GameState.objective_progress()])
	var player = GameManager.player
	if player and is_instance_valid(player):
		var p: Vector3 = player.global_position
		var focus = player.detector.focused if player.get("detector") else null
		out.append("Player at (%.1f, %.1f, %.1f)%s%s" % [p.x, p.y, p.z,
			" · indoors" if Interiors.instance and Interiors.instance.is_inside() else "",
			" · next to: %s" % focus.get_prompt() if focus and is_instance_valid(focus) else ""])
	var shown := GameManager.villagers.filter(func(v): return is_instance_valid(v) and v.visible).size()
	out.append("Villagers: %d living here, %d spawned, %d visible now" % [Population.count(), GameManager.villagers.size(), shown])
	var tree := Engine.get_main_loop() as SceneTree
	var structures: Array = tree.get_nodes_in_group("placed_structures") if tree else []
	out.append("Buildings: %d (%d finished) · hens %d" % [structures.size(), structures.filter(func(s): return s.is_complete()).size(),
		tree.get_nodes_in_group("chickens").size() if tree else 0])
	out.append("Resources: %s" % ", ".join([&"wood", &"stone", &"food", &"herbs"].map(func(r): return "%s %d" % [r, GameState.count(r)])))
	var saved := float(SaveService._data.get("saved_unix", 0.0))
	out.append("Save: %s" % ("last saved %d s ago" % int(Time.get_unix_time_from_system() - saved) if saved > 0.0 else "not saved yet"))
	out.append("")
	out.append("Recent errors and warnings:")
	var problems := recent_problems()
	if problems.is_empty():
		out.append("  none logged")
	for line in problems:
		out.append("  " + line)
	return "\n".join(out)


## The last errors and warnings in the game's log file (with the line
## saying where each happened).
static func recent_problems() -> PackedStringArray:
	var found := PackedStringArray()
	var path := String(ProjectSettings.get_setting("debug/file_logging/log_path", "user://logs/godot.log"))
	if not FileAccess.file_exists(path):
		return found
	var lines := FileAccess.get_file_as_string(path).split("\n")
	for i in lines.size():
		var line := lines[i].strip_edges()
		if line.begins_with("ERROR") or line.begins_with("SCRIPT ERROR") or line.begins_with("WARNING") or line.begins_with("USER ERROR") or line.begins_with("USER WARNING"):
			var where := lines[i + 1].strip_edges() if i + 1 < lines.size() and lines[i + 1].strip_edges().begins_with("at:") else ""
			found.append(line + ("  [" + where + "]" if where != "" else ""))
	if found.size() > LOG_LINES:
		found = found.slice(found.size() - LOG_LINES)
	return found
