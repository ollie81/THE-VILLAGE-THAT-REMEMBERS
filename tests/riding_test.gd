extends Node
## Headless test of Stage 3 of the living world: riding your own horse.
## Mounting and getting off, steering at a walk and a gallop, the horse
## staying under you, no swimming on horseback, the riding pose, the saddle
## and reins, the camera, and the horse staying where you leave it.
## Run:  godot --headless --path . res://tests/riding_test.tscn

var _failures: int = 0
var _main = null


func _ready() -> void:
	SaveService.enabled = false
	PopulationDirector.auto_arrivals = false
	Guide.rewards = false
	DailyGift.persist = false
	GameState.reset()
	_run.call_deferred()


func _check(condition: bool, description: String) -> void:
	if condition:
		print("  PASS  ", description)
	else:
		_failures += 1
		print("  FAIL  ", description)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


func _run() -> void:
	print("== Riding test ==")
	WorldClock.set_time(10.0)
	WorldClock.set_time_scale(0.0)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _frames(40)
	Weather.instance.set_weather(Weather.Kind.CLEAR, 48.0, true)
	var player: PlayerController = GameManager.player
	var manager := AnimalManager.instance
	# A village horse can't be ridden; your own can.
	var village_horse: Dictionary = manager.records.filter(func(r): return String(r["species"]) == "horse")[0]
	var home := manager.record_position(village_horse)
	player.global_position = Vector3(home.x + 3, VillageLayout.get_walk_height(home.x + 3, home.z) + 0.3, home.z)
	await _frames(45)
	var theirs := manager.node_of(String(village_horse["id"]))
	_check(theirs != null and theirs._verb() != "Ride", "the village's horses aren't yours to ride (%s)" % (theirs._verb() if theirs else "-"))
	GameState.add(&"wood", 60)
	GameState.add(&"stone", 20)
	var at := BuildMode.nearest_free_spot(&"stable", VillageLayout.ground_point(-30.0, 30.0), 0.0, Vector3(0, 0, 100))
	var stable := GameState.add_structure(&"stable", at, 0.0)
	await _frames(3)
	for s in get_tree().get_nodes_in_group("placed_structures"):
		if s.record == stable:
			while not s.is_complete():
				s.add_work(1.0)
	VillageCredits.instance.earn(200, "riding_test")
	var record := manager.buy(&"horse")
	player.global_position = Vector3(at.x, VillageLayout.get_walk_height(at.x, at.z + 6) + 0.3, at.z + 6)
	await _frames(45)
	var horse := manager.node_of(String(record["id"]))
	_check(horse != null and horse.find_child("Saddle", true, false) != null, "your horse wears a saddle")
	_check(horse._verb() == "Ride" and horse._prompt().begins_with("Ride "), "you can ride your horse (\"%s\")" % horse._prompt())
	# Mount.
	horse.interact(player)
	await _frames(5)
	_check(player.is_riding() and player.mount_animal == horse and horse.rider == player, "tapping Ride puts you in the saddle")
	_check(horse._verb() == "Get off", "the button now says Get off")
	var focused: Interactable = player.detector.focused
	_check(focused != null and focused.get_parent().get_parent() == horse, "while riding the only thing to tap is the horse (to get off)")
	var hips_above_ground := player.model.global_position.y - VillageLayout.get_walk_height(player.global_position.x, player.global_position.z)
	_check(hips_above_ground > 0.6 and hips_above_ground < 1.4, "you sit up on the horse's back (model raised %.2f m)" % hips_above_ground)
	var skeleton: Skeleton3D = player.model.get("skeleton")
	if skeleton:
		var thigh := skeleton.find_bone("thigh_l")
		var calf := skeleton.find_bone("calf_l")
		var foot := skeleton.find_bone("foot_l")
		var to_model := player.model.global_transform.affine_inverse() * skeleton.global_transform
		var hip_p := to_model * skeleton.get_bone_global_pose(thigh).origin
		var knee_p := to_model * skeleton.get_bone_global_pose(calf).origin
		var foot_p := to_model * skeleton.get_bone_global_pose(foot).origin
		_check(knee_p.y < hip_p.y - 0.12, "the thighs angle down round the horse (knee %.2f m below the hip)" % (hip_p.y - knee_p.y))
		_check(absf(foot_p.x) > 0.3, "the feet hang outside the horse's sides (%.2f m out)" % absf(foot_p.x))
		_check(foot_p.y < knee_p.y - 0.3, "the lower legs hang down to the stirrups")
	var reins := horse._reins.filter(func(r): return r.visible)
	_check(reins.size() == 2, "reins run from your hands to the bit")
	# Walk forward.
	var open := Vector3(-30, 0, -60)
	player.global_position = Vector3(open.x, VillageLayout.get_walk_height(open.x, open.z) + 0.1, open.z)
	player.model.rotation.y = PI
	await _frames(10)
	var start := player.global_position
	Input.action_press("move_forward")
	await _seconds(1.5)
	var walk := _flat(player.velocity)
	_check(walk > 2.5 and walk < 4.5, "the horse walks (%.1f m/s)" % walk)
	Input.action_press("run")
	await _seconds(2.0)
	var gallop := _flat(player.velocity)
	_check(gallop > 7.0, "hold run (or push the stick to the rim) to gallop (%.1f m/s)" % gallop)
	_check(gallop > player.run_speed, "galloping is faster than running on foot (%.1f > %.1f)" % [gallop, player.run_speed])
	var under := _flat(horse.global_position - player.global_position)
	_check(under < 0.05, "the horse stays under you (%.2f m)" % under)
	_check(String(horse.player_anim.current_animation).ends_with("Run"), "the horse gallops (%s)" % horse.player_anim.current_animation)
	Input.action_release("run")
	Input.action_release("move_forward")
	await _seconds(1.5)
	_check(_flat(player.velocity) < 0.5, "let go and the horse stops")
	_check(player.global_position.distance_to(start) > 8.0, "you've ridden %.0f m" % player.global_position.distance_to(start))
	# The camera pulls back to show the whole horse.
	var rig: CameraRig = _main.camera_rig
	_check(rig._ride_extra > 1.0, "the camera pulls back while riding (+%.1f m)" % rig._ride_extra)
	# Water: the horse won't swim.
	var lake := VillageLayout.LAKE_CENTER
	var shore := lake + Vector3(VillageLayout.LAKE_RADIUS + 6.0, 0, 0)
	player.global_position = Vector3(shore.x, VillageLayout.get_walk_height(shore.x, shore.z) + 0.1, shore.z)
	rig.yaw = PI * 0.5  # camera forward is -X: towards the lake
	await _frames(5)
	Input.action_press("move_forward")
	await _seconds(4.0)
	Input.action_release("move_forward")
	var depth := VillageLayout.water_depth(player.global_position.x, player.global_position.z)
	_check(not player.swimming and depth <= PlayerController.RIDE_MAX_WATER + 0.3, "the horse stops at deep water (depth %.2f m, swimming %s)" % [depth, player.swimming])
	# Get off: beside the horse, which waits there.
	player.global_position = Vector3(open.x, VillageLayout.get_walk_height(open.x, open.z) + 0.1, open.z)
	await _frames(10)
	var horse_at := horse.global_position
	player.detector.try_interact(player)
	await _frames(5)
	_check(not player.is_riding() and horse.rider == null, "tapping Get off gets you down")
	_check(player.model.position.length() < 0.01, "and you stand on the ground again")
	var apart := _flat(player.global_position - horse_at)
	_check(apart > 0.6 and apart < 2.0, "you land beside the horse (%.1f m)" % apart)
	var area := horse.home_area()
	_check(_flat(Vector3(area["center"]) - horse_at) < 0.5, "the horse waits where you left it")
	await _seconds(1.0)
	_check(_flat(horse.global_position - horse_at) < 4.0, "and grazes nearby rather than running off")
	# Saving while riding saves you standing beside the horse.
	horse.interact(player)
	await _frames(3)
	var data := player.get_save_data()
	_check(not player.is_riding() and (data["position"] as Array).size() == 3, "saving while riding gets you down first, so loading never leaves you stuck mid-air")
	print("== %s: %d failure(s) ==" % ["PASSED" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(0 if _failures == 0 else 1)
