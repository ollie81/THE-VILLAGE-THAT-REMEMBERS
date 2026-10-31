extends Node
## Headless smoke test for Milestone 1.
## Run:  godot --headless --path . res://tests/smoke_test.tscn
## Exits with code 0 when every check passes, 1 otherwise.

const MAIN_SCENE := "res://scenes/main.tscn"

var _failures: int = 0
## Untyped: the main scene script has no class_name.
var _main = null


func _ready() -> void:
	SaveService.enabled = false
	_run.call_deferred()


func _run() -> void:
	print("== The Village That Remembers: smoke test ==")
	WorldClock.set_time(9.0)
	WorldClock.set_time_scale(1.0)
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	add_child(_main)
	await _frames(30)

	# 1. World content
	_check(_main.get_node_or_null("World/TerrainMesh") != null, "terrain mesh exists")
	_check(_main.get_node_or_null("World/TerrainBody") != null, "terrain collision exists")
	var village: Node = _main.get_node_or_null("World/Village")
	_check(village != null and village.get_child_count() >= 13, "village buildings exist (%d nodes)" % (village.get_child_count() if village else 0))
	for id in ["HouseMara", "HouseElias", "HouseNia", "HouseTomas", "HouseSera", "Storage", "Workshop", "Garden", "Farm", "Plaza"]:
		_check(village != null and village.get_node_or_null(id) != null, "building %s exists" % id)
	_check(_main.get_node_or_null("World/River/Water") != null, "river water exists")
	_check(_main.get_node_or_null("World/River/Bridge") != null, "bridge exists")
	var nature: Node = _main.get_node_or_null("World/Nature")
	_check(nature != null and nature.get_child_count() > 10, "nature batches spawned")

	# 2. Villagers
	_check(GameManager.villagers.size() == 5, "five villagers registered (%d)" % GameManager.villagers.size())
	var expected := {"mara": 29, "elias": 35, "nia": 24, "tomas": 61, "sera": 27}
	for id in expected:
		var villager = GameManager.get_villager(StringName(id))
		_check(villager != null, "villager %s present" % id)
		if villager:
			_check(villager.data.age == expected[id], "%s is %d" % [id, expected[id]])
	# Characters are real skinned 3D meshes on a humanoid skeleton, within a mobile budget.
	for villager in GameManager.villagers:
		var model: CharacterModel = villager.model
		var body := model.skeleton.get_node_or_null("Body") as MeshInstance3D
		var triangles: int = body.mesh.surface_get_array_len(0) / 3 if body else 0
		_check(model.skeleton.get_bone_count() == 19 and body != null and body.skin != null,
			"%s has a skinned body on a 19-bone skeleton" % villager.data.display_name)
		_check(triangles > 1500 and triangles < 9000, "%s body is %d triangles (budget 9000)" % [villager.data.display_name, triangles])
		_check(model.animation_player.get_animation_list().size() >= 8, "%s has skeletal animations" % villager.data.display_name)
		# Arms: every vertex bound to a left/right arm bone sits on that side,
		# and both arms have the same amount of geometry.
		var arrays := body.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bone_ids: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var bone_weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var arm_counts := {"Left": 0, "Right": 0}
		var misbound := 0
		for v in verts.size():
			var main := bone_ids[v * 4] if bone_weights[v * 4] >= bone_weights[v * 4 + 1] else bone_ids[v * 4 + 1]
			var bone_name := model.skeleton.get_bone_name(main)
			for side in ["Left", "Right"]:
				if bone_name.begins_with(side) and (bone_name.contains("Arm") or bone_name.contains("Hand")):
					arm_counts[side] += 1
					if verts[v].x * (1.0 if side == "Left" else -1.0) < 0.0:
						misbound += 1
		_check(misbound == 0 and arm_counts["Left"] == arm_counts["Right"],
			"%s arms are symmetric (%d/%d vertices, %d on the wrong side)" % [villager.data.display_name, arm_counts["Left"], arm_counts["Right"], misbound])
		var head_mesh: Mesh = model.head.mesh if model.head else null
		_check(head_mesh != null and head_mesh.get_blend_shape_count() == FaceExpressions.SHAPES.size(),
			"%s face has %d expression blend shapes" % [villager.data.display_name, head_mesh.get_blend_shape_count() if head_mesh else 0])
	var distinct := {}
	for villager in GameManager.villagers:
		distinct["%d_%d" % [roundi(villager.global_position.x), roundi(villager.global_position.z)]] = true
	_check(distinct.size() >= 4, "villagers are spread out, not stacked (%d distinct spots)" % distinct.size())

	# 3. Player movement
	var player: PlayerController = GameManager.player
	_check(player != null, "player exists")
	await _physics_frames(30)
	_check(player.is_on_floor(), "player stands on the ground")
	var start := player.global_position
	Input.action_press("move_forward")
	await _physics_frames(60)
	var walked := Vector2(player.global_position.x - start.x, player.global_position.z - start.z).length()
	_check(walked > 1.5, "player walks forward (%.2f m in 1 s)" % walked)
	var walk_start := player.global_position
	Input.action_press("run")
	await _physics_frames(60)
	var ran := Vector2(player.global_position.x - walk_start.x, player.global_position.z - walk_start.z).length()
	_check(ran > walked * 1.3, "running is faster than walking (%.2f m vs %.2f m)" % [ran, walked])
	Input.action_release("run")
	Input.action_release("move_forward")
	await _physics_frames(20)
	Input.action_press("jump")
	await _physics_frames(2)
	Input.action_release("jump")
	await _physics_frames(10)
	_check(not player.is_on_floor(), "player can jump")
	await _physics_frames(90)
	_check(player.is_on_floor(), "player lands again")

	# 3b. On-screen touch controls (as a phone delivers touches).
	GameSettings.touch_mode = GameSettings.TouchMode.ALWAYS
	GameSettings.settings_changed.emit()
	await _frames(2)
	var touch: TouchControls = _main.hud.find_child("TouchControls", true, false)
	var view := get_viewport().get_visible_rect().size
	_check(touch != null and touch.visible and touch.size.is_equal_approx(view), "touch controls cover the screen (%s)" % (touch.size if touch else Vector2.ZERO))
	var touch_start := player.global_position
	var stick := Vector2(170, view.y - 170)
	_send_touch(0, stick, true)
	await get_tree().process_frame
	_send_drag(0, stick + Vector2(0, -60), Vector2(0, -60))
	await _physics_frames(45)
	var touch_walked := player.global_position.distance_to(touch_start)
	_check(touch_walked > 1.0 and player.model.get_animation() == &"walk", "touch joystick walks the player (%.2f m)" % touch_walked)
	_send_touch(0, stick + Vector2(0, -60), false)
	await _physics_frames(30)
	_check(InputRouter.touch_move == Vector2.ZERO and player.model.get_animation() == &"idle", "releasing the joystick stops and idles")
	GameSettings.touch_mode = GameSettings.TouchMode.AUTO
	GameSettings.settings_changed.emit()

	# 4. Camera switching
	var rig: CameraRig = _main.camera_rig
	var explore_height := rig.camera.global_position.y - player.global_position.y
	GameManager.toggle_camera_mode()
	_check(GameManager.camera_mode == GameManager.CameraMode.MANAGEMENT, "switched to management camera")
	await _frames(90)
	var manage_height := rig.camera.global_position.y - player.global_position.y
	_check(manage_height > explore_height + 10.0, "management camera is high above (%.1f m vs %.1f m)" % [manage_height, explore_height])
	var before_pan := player.global_position
	Input.action_press("move_forward")
	await _physics_frames(30)
	Input.action_release("move_forward")
	_check(player.global_position.distance_to(before_pan) < 0.3, "player does not move while managing")
	GameManager.toggle_camera_mode()
	await _frames(90)
	_check(GameManager.camera_mode == GameManager.CameraMode.EXPLORATION, "switched back to exploration camera")

	# 5. Day / night
	var cycle: DayNightCycle = _main.day_night
	WorldClock.set_time(12.5)
	await _frames(12)
	var noon_energy := cycle.sun.light_energy
	_check(noon_energy > 1.0 and cycle.night_factor < 0.05, "midday is bright (sun %.2f)" % noon_energy)
	WorldClock.set_time(0.5)
	await _frames(12)
	_check(cycle.night_factor > 0.9 and cycle.sun.light_energy < 0.4, "midnight is dark (light %.2f)" % cycle.sun.light_energy)
	_check(Materials.window_glow().emission_energy_multiplier > 1.0, "windows glow at night")
	var asleep := 0
	await _physics_frames(75)
	for villager in GameManager.villagers:
		if villager.state == Villager.State.INSIDE or villager.state == Villager.State.TRAVELING:
			asleep += 1
	_check(asleep == 5, "everyone heads home at night (%d/5)" % asleep)

	# 6. Villagers come out and walk to work in the morning.
	# Wait until everyone is actually indoors first (at most ~40 s of game).
	for i in 2400:
		var inside := 0
		for villager in GameManager.villagers:
			if villager.state == Villager.State.INSIDE:
				inside += 1
		if inside == 5:
			break
		await get_tree().physics_frame
	WorldClock.set_time(9.0)
	WorldClock.set_time_scale(0.0)
	await _physics_frames(90)
	var moved_from := {}
	for villager in GameManager.villagers:
		moved_from[villager] = villager.global_position
	await _physics_frames(240)
	var moving := 0
	for villager in GameManager.villagers:
		if villager.global_position.distance_to(moved_from[villager]) > 0.5:
			moving += 1
	_check(moving >= 3, "villagers walk around in the morning (%d/5 moved)" % moving)

	# 7. Interaction
	var mara = GameManager.get_villager(&"mara")
	await _wait_until_visible(mara)
	player.global_position = mara.global_position + Vector3(1.2, 0.5, 0.0)
	player.velocity = Vector3.ZERO
	player.face_towards(mara.global_position)
	await _physics_frames(20)
	_check(player.detector.focused != null, "detector focuses a nearby villager")
	var met_before: int = mara.mind.get_familiarity(GameManager.PLAYER_ID)
	var started := GameManager.start_conversation(mara)
	_check(started, "conversation starts")
	_check(mara.state == Villager.State.INTERACTING, "villager stops to talk")
	var lines := DialogueService.build_greeting(mara, "nobody")
	_check(lines.size() >= 2 and lines[0].contains("Mara"), "introduction mentions the villager's name")
	GameManager.end_conversation()
	_check(mara.state != Villager.State.INTERACTING, "villager resumes their day")
	_check(mara.mind.get_familiarity(GameManager.PLAYER_ID) == met_before + 1, "villager remembers the conversation")
	var second := DialogueService.build_greeting(mara, GameManager.PLAYER_ID)
	_check(not second[0].contains("don't think we've met"), "second greeting is different")

	# 7a. Milestone 2: choices, opinions, memories and gossip.
	var tomas = GameManager.get_villager(&"tomas")
	var nia = GameManager.get_villager(&"nia")
	# Start these three from a clean slate, and restore them afterwards.
	var saved_minds := {}
	for v in [mara, tomas, nia]:
		saved_minds[v] = v.mind.to_dict()
		v.mind.from_dict({})
	var first := DialogueService.build_conversation(mara, GameManager.PLAYER_ID)
	_check(first.topic_id == "mara_new_house" and first.choices.size() == 3, "first conversation offers a topic with choices")
	while first.has_lines():
		first.next_line()
	first.choose(0)
	_check(mara.mind.get_affection(GameManager.PLAYER_ID) > 0.0 and first.has_lines(), "a kind choice raises affection and gets a reply")
	_check(mara.mind.memory.find("deed", GameManager.PLAYER_ID).size() == 1, "the choice is remembered as a deed")
	var second_talk := DialogueService.build_conversation(mara, GameManager.PLAYER_ID)
	_check(second_talk.topic_id == "mara_wolves", "the next visit moves on to the next topic")
	var story := GossipSystem.share(mara, tomas)
	_check(story == "offered to help build the new house", "Mara tells Tomas what the player did")
	_check(tomas.mind.get_affection(GameManager.PLAYER_ID) > 0.0, "gossip shapes the listener's opinion")
	_check(GossipSystem.share(mara, tomas) == "", "the same story isn't told twice")
	var tomas_talk := DialogueService.build_conversation(tomas, GameManager.PLAYER_ID)
	_check(" ".join(tomas_talk.lines).contains("Mara told me you offered to help build the new house"), "Tomas brings up what Mara told him")
	WorldClock.day += 1
	var next_day := DialogueService.build_conversation(mara, GameManager.PLAYER_ID)
	_check(" ".join(next_day.lines).contains("I haven't forgotten that you offered to help build the new house"), "a day later Mara recalls the deed")
	var again := DialogueService.build_conversation(mara, GameManager.PLAYER_ID)
	_check(not " ".join(again.lines).contains("haven't forgotten"), "a memory is brought up only once")
	WorldClock.day -= 1
	nia.mind.adjust_opinion(GameManager.PLAYER_ID, -50.0, -20.0)
	var cold := DialogueService.build_conversation(nia, GameManager.PLAYER_ID)
	_check(cold.topic_id == "apology", "a villager who dislikes the player wants an apology")
	while cold.has_lines():
		cold.next_line()
	cold.choose(0)
	_check(not nia.mind.is_hostile(GameManager.PLAYER_ID), "apologising mends the relationship")
	var restored := VillagerMind.new("tomas")
	restored.from_dict(JSON.parse_string(JSON.stringify(tomas.mind.to_dict())))
	_check(is_equal_approx(restored.get_affection(GameManager.PLAYER_ID), tomas.mind.get_affection(GameManager.PLAYER_ID))
		and restored.memory.find("heard", GameManager.PLAYER_ID).size() == 1, "opinions and gossip survive save/load")
	for v in saved_minds:
		v.mind.from_dict(saved_minds[v])

	# 7b. Facial expressions drive the blend shapes.
	var face_model: CharacterModel = mara.model
	face_model.set_expression(&"laughing", 1.0, 0.0)
	var laugh_index := face_model.head.find_blend_shape_by_name(&"laughing")
	_check(laugh_index >= 0 and is_equal_approx(face_model.head.get_blend_shape_value(laugh_index), 1.0), "expressions set blend shape weights")
	face_model.set_expression(&"neutral", 1.0, 0.0)
	_check(is_zero_approx(face_model.head.get_blend_shape_value(laugh_index)), "neutral clears the expression")
	var parsed := DialoguePanel.split_expression("[angry]Stay back!")
	_check(parsed[0] == &"angry" and parsed[1] == "Stay back!", "dialogue lines carry expression tags")

	# 8. Save data round trip (in memory only)
	var saved: Dictionary = mara.get_save_data()
	var copy := VillagerMind.new("mara")
	copy.from_dict(JSON.parse_string(JSON.stringify(saved))["mind"])
	_check(copy.get_familiarity(GameManager.PLAYER_ID) == met_before + 1, "mind survives JSON save/load")

	print("== %s: %d failure(s) ==" % ["PASSED" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(0 if _failures == 0 else 1)


## Touch input in window pixels, the way the OS delivers it.
func _send_touch(index: int, viewport_position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = get_tree().root.get_final_transform() * viewport_position
	event.pressed = pressed
	Input.parse_input_event(event)


func _send_drag(index: int, viewport_position: Vector2, relative: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = get_tree().root.get_final_transform() * viewport_position
	event.relative = get_tree().root.get_final_transform().basis_xform(relative)
	Input.parse_input_event(event)


func _wait_until_visible(villager) -> void:
	for i in 600:
		if villager.visible and villager.state != Villager.State.INSIDE:
			return
		await get_tree().physics_frame


func _check(condition: bool, description: String) -> void:
	if condition:
		print("  PASS  ", description)
	else:
		_failures += 1
		print("  FAIL  ", description)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _physics_frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
