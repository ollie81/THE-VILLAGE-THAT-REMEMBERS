extends Node
## Developer tool: the daily hooks in the real scene: coming back to the
## "While you were away..." story, today's requests and the markers over
## villagers' heads, being asked, and handing over what they needed.
## Run: godot --path . --resolution 1612x720 res://tools/hooks_screenshots.tscn -- --out=/some/dir

var _out_dir := "user://screenshots"
var _main


func _ready() -> void:
	SaveService.enabled = false
	PopulationDirector.auto_arrivals = false
	GameState.reset()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out_dir.path_join(file_name + ".png"))
	print("saved ", file_name)


## Stands a villager somewhere open (south of the meeting circle) so the
## camera can see them, and keeps them there.
func _out_in_the_open(villager, at: Vector3, yaw: float) -> void:
	villager._decision_timer = 1000.0
	villager._route = PackedVector3Array()
	villager.global_position = VillageLayout.ground_point(at.x, at.z)
	villager.rotation.y = yaw
	villager.visible = true
	villager.state = Villager.State.PERFORMING
	villager._perform_timer = 1000.0
	villager._look_target = null


func _run() -> void:
	WorldClock.day = 4
	WorldClock.set_time(22.0)
	WorldClock.set_time_scale(0.0)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _wait(60)
	var player: PlayerController = GameManager.player
	var rig: CameraRig = _main.camera_rig
	var dialogue = _main.find_child("DialoguePanel", true, false)
	for v in GameManager.villagers:
		v.mind.record_interaction(GameManager.PLAYER_ID, "conversation", 1, 9.0)
		v.mind.adjust_opinion(GameManager.PLAYER_ID, 15.0, 8.0)
		for topic in ConversationLibrary.topics_for(v.data.id):
			v.mind.memory.add("topic", GameManager.PLAYER_ID, 1, 9.0, String(topic["id"]))
	# A field planted before "leaving".
	GameState.add(&"wood", 20)
	var record := GameState.add_structure(&"farm_plot", VillageLayout.ground_point(13.0, -6.0), 0.0)
	await _wait(3)
	for s in get_tree().get_nodes_in_group("placed_structures"):
		if s.record == record:
			while not s.is_complete():
				s.add_work(1.0)
			s.use()

	# 1. Coming back after a night away.
	player.global_position = VillageLayout.ground_point(9.0, 2.0) + Vector3(0, 0.4, 0)
	player.face_towards(Vector3.ZERO)
	AwayTime.instance.catch_up(10.5)
	await _wait(90)
	rig.yaw = player.model.rotation.y + PI + 0.3
	rig.pitch = -0.25
	rig.distance = 6.0
	await _wait(40)
	await _shot("01_while_you_were_away")
	var panel: RequestsPanel = _main.find_child("RequestsPanel", true, false)
	panel._away.visible = false

	# 2. Today's requests and the ! over the people asking.
	var board := RequestBoard.instance
	var asker = GameManager.get_villager(StringName(String(board.requests[0]["from"])))
	_out_in_the_open(asker, Vector3(4.0, 0, 8.5), PI * 0.5)
	player.global_position = asker.global_position + Vector3(4.0, 0.4, 3.0)
	player.face_towards(asker.global_position)
	rig.yaw = player.model.rotation.y + PI + 0.25
	rig.pitch = -0.2
	rig.distance = 4.5
	await _wait(60)
	await _shot("02_todays_requests")

	# 3. Being asked.
	var facing := Vector3(sin(asker.rotation.y), 0, cos(asker.rotation.y))
	player.global_position = asker.global_position + facing * 1.6 + Vector3(0, 0.3, 0)
	player.face_towards(asker.global_position)
	await _wait(10)
	GameManager.start_conversation(asker)
	var ask := String(board.requests[0]["ask"]).substr(String(board.requests[0]["ask"]).find("]") + 1)
	for i in 12:
		await _wait(25)
		if dialogue._text_label.text == ask or dialogue._choice_box.visible:
			break
		dialogue.advance()
		await _wait(3)
		dialogue.advance()
	await _wait(40)
	await _shot("03_asked")
	while GameManager.is_in_conversation():
		if dialogue._choice_box.visible:
			dialogue._choose(dialogue._conversation.choices.size() - 1)
		else:
			dialogue.advance()
		await _wait(3)

	# 4. Handing it over (or passing on the message).
	var request: Dictionary = board.requests[0]
	var target = asker
	if String(request["kind"]) == "fetch":
		GameState.add(StringName(String(request["resource"])), int(request["amount"]))
	else:
		target = GameManager.get_villager(StringName(String(request["to"])))
		_out_in_the_open(target, Vector3(-4.0, 0, 8.5), -PI * 0.5)
		facing = Vector3(sin(target.rotation.y), 0, cos(target.rotation.y))
		player.global_position = target.global_position + facing * 1.6 + Vector3(0, 0.3, 0)
		player.face_towards(target.global_position)
		await _wait(10)
	GameManager.start_conversation(target)
	for i in 12:
		await _wait(25)
		if dialogue._choice_box.visible:
			break
		dialogue.advance()
		await _wait(3)
		dialogue.advance()
	await _wait(10)
	await _shot("04_request_choice")
	dialogue._choose(0)
	await _wait(80)
	await _shot("05_thanks")
	while GameManager.is_in_conversation():
		if dialogue._choice_box.visible:
			dialogue._choose(dialogue._conversation.choices.size() - 1)
		else:
			dialogue.advance()
		await _wait(3)
	await _wait(20)
	rig.yaw = player.model.rotation.y + PI + 0.3
	rig.distance = 5.0
	await _wait(30)
	await _shot("06_request_done")
	get_tree().quit()
