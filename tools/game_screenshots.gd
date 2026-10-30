extends Node
## Developer tool: captures in-game screenshots for reviewing art changes:
## a conversation with every villager, the normal third-person view next to
## a villager, Village View with a selected villager's portrait, and evening.
## Run: godot --path . res://tools/game_screenshots.tscn -- --out=/some/dir

const VILLAGERS: Array[StringName] = [&"mara", &"elias", &"nia", &"tomas", &"sera"]

var _out_dir: String = "user://screenshots"
var _main


func _ready() -> void:
	SaveService.enabled = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := _out_dir.path_join(file_name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


## Puts the player 1.6 m in front of a villager, facing them.
func _stand_before(villager) -> void:
	var player = GameManager.player
	var facing := Vector3(sin(villager.rotation.y), 0, cos(villager.rotation.y))
	player.global_position = villager.global_position + facing * 1.6 + Vector3(0, 0.3, 0)
	player.velocity = Vector3.ZERO
	player.face_towards(villager.global_position)


func _run() -> void:
	WorldClock.set_time(10.5)
	WorldClock.set_time_scale(0.0)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _wait(240)
	var rig: CameraRig = _main.camera_rig

	# Conversation close-ups with each villager, each line's expression.
	for id in VILLAGERS:
		var villager = GameManager.get_villager(id)
		if not villager.visible:
			continue
		_stand_before(villager)
		await _wait(20)
		GameManager.start_conversation(villager)
		await _wait(80)
		await _shot("talk_" + String(id))
		GameManager.end_conversation()
		await _wait(30)

	# Normal third-person gameplay view beside a villager.
	var nia = GameManager.get_villager(&"nia")
	_stand_before(nia)
	var player = GameManager.player
	rig.yaw = player.model.rotation.y + PI + 0.7
	rig.pitch = -0.25
	rig.distance = 5.5
	await _wait(80)
	await _shot("third_person")

	# Village View, selecting a villager zooms in and shows their portrait.
	GameManager.toggle_camera_mode()
	await _wait(60)
	await _shot("village_view_default")
	GameManager.select_villager(GameManager.get_villager(&"elias"))
	await _wait(150)
	await _shot("village_view_selected")
	GameManager.select_villager(null)
	GameManager.toggle_camera_mode()

	# Evening at the meeting circle: faces under firelight.
	WorldClock.set_time(19.6)
	await _wait(400)
	var sera = GameManager.get_villager(&"sera")
	if sera.visible:
		_stand_before(sera)
		await _wait(20)
		GameManager.start_conversation(sera)
		await _wait(80)
		await _shot("talk_evening")
	get_tree().quit()
