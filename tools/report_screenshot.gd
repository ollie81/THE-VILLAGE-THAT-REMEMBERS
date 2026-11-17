extends Node
## Developer tool: the Settings panel and the Report a problem screen.
## Run: godot --path . --resolution 1612x720 res://tools/report_screenshot.tscn -- --out=/some/dir
var _out := "user://screenshots"
var _main

func _ready() -> void:
	SaveService.enabled = false
	PopulationDirector.auto_arrivals = false
	GameState.reset()
	GameSettings.touch_mode = 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()

func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("saved ", name)

func _run() -> void:
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _wait(60)
	var settings: Control = _main.find_child("SettingsPanel", true, false)
	settings.visible = true
	var scroll: ScrollContainer = settings.find_child("*", true, false) as ScrollContainer
	for c in settings.find_children("*", "ScrollContainer", true, false):
		(c as ScrollContainer).scroll_vertical = 100000
	await _wait(10)
	await _shot("settings_report_button")
	(settings.find_child("ReportButton", true, false) as Button).pressed.emit()
	await _wait(10)
	await _shot("report_panel")
	get_tree().quit()
