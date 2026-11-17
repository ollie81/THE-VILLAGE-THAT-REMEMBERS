extends Node
## Developer tool: the first goal a new player sees, and the reminder question.
## Run: godot --path . --resolution 1612x720 res://tools/first_day_screenshots.tscn -- --out=/some/dir
var _out := "user://screenshots"

func _ready() -> void:
	SaveService.enabled = false
	PopulationDirector.auto_arrivals = false
	DailyGift.persist = false
	Reminders.persist = false
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
	WorldClock.set_time(9.0)
	WorldClock.set_time_scale(0.0)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _wait(60)
	GameState.give_starter_kit()
	await _wait(20)
	await _shot("1_first_goal")
	for tip in main.find_children("TutorialTips", "", true, false):
		tip.visible = false
	Reminders.instance.ask()
	await _wait(15)
	await _shot("2_reminder_question")
	get_tree().quit()
