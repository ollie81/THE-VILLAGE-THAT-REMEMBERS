extends Node
## Developer tool: a conversation on a phone-sized screen: your turn (answers
## and the message box), your typed line, the villager's answer, and typing
## with the on-screen keyboard up.
## Run: godot --path . --resolution 1612x720 res://tools/conversation_screenshots.tscn -- --out=/some/dir
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
	WorldClock.set_time(10.0)
	WorldClock.set_time_scale(0.0)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _wait(60)
	for tip in main.find_children("TutorialTips", "", true, false):
		tip.visible = false
		tip.set_process(false)
	var panel: DialoguePanel = main.find_child("DialoguePanel", true, false)
	var nia = GameManager.get_villager(&"nia")
	var player = GameManager.player
	player.global_position = nia.global_position + Vector3(1.6, 0, 1.2)
	await _wait(5)
	GameManager.start_conversation(nia)
	await _wait(5)
	var guard := 0
	while not panel._choice_box.visible and guard < 30:
		panel.advance()
		await _wait(2)
		guard += 1
	await _wait(10)
	await _shot("1_your_turn")
	panel._input.text = "Hi Nia! My name is Sam. I love flowers."
	panel.send_typed()
	await _wait(40)
	await _shot("2_you_say")
	panel.advance()
	panel.advance()
	await _wait(40)
	await _shot("3_she_answers")
	guard = 0
	while not panel._choice_box.visible and guard < 10:
		panel.advance()
		await _wait(2)
		guard += 1
	panel._input.grab_focus()
	panel._input.text = "What do you remember about me?"
	panel.keyboard_height_override = 300.0
	await _wait(10)
	await _shot("4_typing_keyboard_up")
	panel._input.release_focus()
	panel.keyboard_height_override = -1.0
	panel.send_typed()
	await _wait(5)
	panel.advance()
	panel.advance()
	await _wait(40)
	await _shot("5_she_remembers")
	get_tree().quit()
