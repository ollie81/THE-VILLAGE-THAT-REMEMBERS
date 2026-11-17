extends Node
## Developer tool: sitting on the meeting-circle log and on the cottage chair, seen from the side.
var _out := "user://screenshots"
var _main
func _ready() -> void:
	SaveService.enabled = false
	PopulationDirector.auto_arrivals = false
	GameState.reset()
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
	WorldClock.set_time(11.0)
	WorldClock.set_time_scale(0.0)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _wait(60)
	for tip in _main.find_children("TutorialTips", "", true, false):
		tip.visible = false
		tip.set_process(false)
	var player: PlayerController = GameManager.player
	var rig: CameraRig = _main.camera_rig
	var objects: WorldObjects = _main.find_child("WorldObjects", true, false)
	var log_object: Node3D = objects.get_node("Log0")
	player.global_position = log_object.global_position + Vector3(0.8, 0.4, 0.8)
	await _wait(10)
	player.detector.try_interact(player)
	await _wait(40)
	rig.yaw = player.model.rotation.y - PI * 0.5
	rig.pitch = 0.05
	rig.distance = 1.8
	await _wait(20)
	await _shot("sit_log")
	player.stand_up()
	await _wait(10)
	var cottage := KitCottage.instance
	var seat := cottage.find_child("Seat", true, false) as Node3D
	player.global_position = seat.global_position + Vector3(0, 0.3, 0)
	await _wait(10)
	(seat as UsableObject).use.call(player)
	await _wait(40)
	rig.overhead = false
	cottage.roof.visible = false
	rig.yaw = player.model.rotation.y + PI * 0.5
	rig.pitch = -0.05
	rig.distance = 1.6
	await _wait(20)
	await _shot("sit_chair")
	get_tree().quit()
