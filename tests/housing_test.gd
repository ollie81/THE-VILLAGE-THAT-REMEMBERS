extends Node
## Headless test of Living Village stage A: building houses (four sizes,
## designs), their rooms (walls with doorways), furniture (making, placing,
## carrying, moving, putting away, using: beds, seats, lamps, books, storage),
## outdoor furniture, redecorating, expanding a house, removing one, and
## saving it all.
## Run:  godot --headless --path . res://tests/housing_test.tscn

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


func _player() -> PlayerController:
	return GameManager.player


func _rich() -> void:
	for r in GameState.RESOURCES:
		GameState.add(r, 400)


## Flat open ground near `near` where `type` can stand.
func _open_ground(type: StringName, near: Vector3) -> Vector3:
	for ring in range(0, 30):
		for i in maxi(1, ring * 8):
			var a := TAU * i / maxi(1, ring * 8)
			var at := VillageLayout.ground_point(near.x + cos(a) * ring * 2.0, near.z + sin(a) * ring * 2.0)
			if BuildMode.placement_reason(type, at, 0.0, null, true) == "":
				return at
	return Vector3.INF


func _node_of(record: Dictionary) -> PlacedStructure:
	for s in get_tree().get_nodes_in_group("placed_structures"):
		if s.record == record:
			return s
	return null


func _finish(record: Dictionary) -> PlacedStructure:
	await _frames(3)
	var s := _node_of(record)
	while not s.is_complete():
		s.add_work(1.0)
	await _frames(2)
	return s


func _enter(structure: PlacedStructure) -> void:
	_player().global_position = structure.doorstep()
	structure.use(_player())
	await _seconds(Interiors.FADE_TIME * 2.0 + 0.3)
	await _frames(3)


func _leave() -> void:
	Interiors.instance.leave()
	await _seconds(Interiors.FADE_TIME * 2.0 + 0.3)
	await _frames(2)


func _pieces() -> Array:
	return Interiors.instance._room.get_children().filter(func(c): return c is FurniturePiece)


func _run() -> void:
	print("== Housing test ==")
	WorldClock.set_time(10.0)
	WorldClock.set_time_scale(0.0)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _frames(40)
	Weather.instance.set_weather(Weather.Kind.CLEAR, 400.0, true)
	MonsterSpawner.instance.set_process(false)
	_rich()
	_catalog()
	var small := await _build_with_design()
	await _rooms(small)
	await _furniture(small)
	await _uses(small)
	await _carry_outside(small)
	_outdoors()
	await _save_load(small)
	await _redecorate_and_expand(small)
	await _bigger_houses()
	await _remove()
	print("== %s: %d failure(s) ==" % ["PASSED" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(0 if _failures == 0 else 1)


func _catalog() -> void:
	var homes: Array = StructureCatalog.CATEGORIES["Homes"]
	_check(HouseDesigns.SIZES.all(func(t): return homes.has(t)), "the Build menu offers small, medium and large houses and a manor")
	var wood := HouseDesigns.SIZES.map(func(t): return int(StructureCatalog.info(t)["cost"][&"wood"]))
	_check(wood[0] < wood[1] and wood[1] < wood[2] and wood[2] < wood[3], "bigger houses cost more (%s wood)" % str(wood))
	_check(HouseDesigns.options().size() == 6, "designs choose the style, walls, roof, door, windows and floor")


## Places a small house through the real Build flow with a chosen design.
func _build_with_design() -> PlacedStructure:
	var at := _open_ground(&"house_medium", Vector3(30, 0, 40))  # room to expand later
	var player := _player()
	player.global_position = at + Vector3(0, 0.3, 8.0)
	player.model.rotation.y = PI
	await _frames(3)
	var build := BuildMode.instance
	build.start(&"house")
	var d := HouseDesigns.default_design()
	d = HouseDesigns.step(d, "style", 1)  # stone
	d = HouseDesigns.step(d, "roof", 2)
	d = HouseDesigns.step(d, "window", 1)  # arched
	d = HouseDesigns.step(d, "floor", 2)  # tiles
	build.set_design(d)
	await _frames(3)
	var panel := DesignPanel.instance
	_check(panel.is_open(), "placing a house shows the Design panel")
	var door_before := int(build.design["door"])
	(panel.find_child("Next_door", true, false) as Button).pressed.emit()
	await _frames(2)
	_check(int(build.design["door"]) == (door_before + 1) % HouseDesigns.DOORS.size(), "its buttons change the design (door: %s)" % HouseDesigns.choice_label(build.design, "door"))
	(panel.find_child("Back_door", true, false) as Button).pressed.emit()
	var before := GameState.structures.size()
	var why := build.confirm()
	_check(why == "" and GameState.structures.size() == before + 1, "a house can be placed through the Build menu (%s)" % ("ok" if why == "" else why))
	var record: Dictionary = GameState.structures[GameState.structures.size() - 1]
	_check(HouseDesigns.of(record)["style"] == "stone" and HouseDesigns.of(record)["floor"] == "tiles", "the chosen design is saved with it (%s)" % str(record.get("design")))
	var house := await _finish(record)
	return house


func _rooms(house: PlacedStructure) -> void:
	await _enter(house)
	var interiors := Interiors.instance
	_check(interiors.is_inside() and interiors.current == Furnishings.place_of(house.record), "the house's door takes you into its own rooms (%s)" % interiors.current)
	_check(interiors._room.find_child("Hearth", false, false) != null and interiors._room.find_child("ExitDoor", false, false) != null, "inside: a hearth to cook at and the door out")
	var names := _pieces().map(func(p): return p.type)
	_check(names.has(&"bed") and names.has(&"chest") and names.has(&"table") and names.has(&"chair") and names.has(&"lamp"),
		"a new house comes with a bed, a chest, a table and chairs and a lamp (%s)" % str(names))
	_check(interiors._room.find_child("Bed", false, false) is FurniturePiece, "and the bed is real furniture you can move, not part of the walls")
	await _leave()


func _furniture(house: PlacedStructure) -> void:
	var place := Furnishings.place_of(house.record)
	var f := Furnishings.instance
	# The rules.
	_check(f.can_place(&"wardrobe", place, Vector3(3.9, 0, 0), 0.0) != "", "furniture can't go through a wall")
	_check(f.can_place(&"wardrobe", place, Vector3(0, 0, 2.6), 0.0) != "", "nor block the way out")
	_check(f.can_place(&"chair", place, Vector3(2.6, 0, -1.75), 0.0) != "", "nor stand where something else is")
	_check(f.can_place(&"rug", place, Vector3(2.6, 0, -1.75), 0.0) == "", "but a rug can go under things")
	await _enter(house)
	# Make a new bookshelf: the preview, then Place.
	var player := _player()
	var wood := GameState.count(&"wood")
	player.global_position = Interiors.ROOM_ORIGIN + Vector3(-1.5, 0.05, 1.9)
	player.model.rotation.y = -PI * 0.5  # facing -X, toward the side wall
	var mode := FurnishMode.instance
	mode.start_new(&"bookshelf")
	await _frames(3)
	while mode.reason != "" and mode._turns < 3:
		mode.turn()
		await _frames(1)
	var why := mode.confirm()
	var shelves := _pieces().filter(func(p): return p.type == &"bookshelf")
	_check(why == "" and shelves.size() == 1, "you can make a bookshelf and place it in your house (%s)" % ("ok" if why == "" else why))
	_check(GameState.count(&"wood") == wood - 8, "it costs what it says (8 wood)")
	# Arrange: pick up a chair (carried), walk, put it down.
	mode.set_arranging(true)
	var chair: FurniturePiece = _pieces().filter(func(p): return p.type == &"chair")[0]
	var record: Dictionary = chair.record
	var old: Array = (record["pos"] as Array).duplicate()
	_check(chair._verb() == "Pick up", "while arranging, a chair says Pick up")
	chair.interact(player)
	await _frames(2)
	_check(mode.active and mode.is_carrying() and player.find_child("Carried", false, false) != null, "you carry the chair in your hands")
	_check(not is_instance_valid(chair) or chair.is_queued_for_deletion(), "and it's gone from where it stood")
	player.global_position = Interiors.ROOM_ORIGIN + Vector3(1.6, 0.05, 1.2)
	player.model.rotation.y = PI * 0.5
	await _frames(3)
	var put := mode.confirm()
	_check(put == "" and (record["pos"] as Array) != old, "you put it down somewhere else (%s)" % ("ok" if put == "" else put))
	_check(_pieces().any(func(p): return p.record == record), "and it stands there")
	# Put it away, then place it again for free.
	var piece: FurniturePiece = _pieces().filter(func(p): return p.record == record)[0]
	piece.interact(player)
	await _frames(2)
	mode.put_away()
	_check(String(record["place"]) == "stored" and Furnishings.stored().has(record), "a piece can be put away")
	wood = GameState.count(&"wood")
	mode.start_new(&"chair", record)
	await _frames(3)
	var again := mode.confirm()
	_check(again == "" and String(record["place"]) == Furnishings.place_of(house.record) and GameState.count(&"wood") == wood, "and placed again later, free")
	# Cancel puts a picked-up piece back where it was.
	var lamp: FurniturePiece = _pieces().filter(func(p): return p.type == &"lamp")[0]
	var lamp_record: Dictionary = lamp.record
	var lamp_at: Array = (lamp_record["pos"] as Array).duplicate()
	lamp.interact(player)
	await _frames(2)
	mode.cancel()
	await _frames(2)
	_check((lamp_record["pos"] as Array) == lamp_at and _pieces().any(func(p): return p.record == lamp_record), "Cancel puts it back where it was")
	mode.set_arranging(false)
	await _leave()


func _uses(house: PlacedStructure) -> void:
	await _enter(house)
	var player := _player()
	# Sit.
	var chair: FurniturePiece = _pieces().filter(func(p): return p.type == &"chair")[0]
	chair.interact(player)
	await _frames(3)
	_check(player.pose == &"sit", "tap a chair and you sit on it")
	player.stand_up()
	# Lamp.
	var lamp: FurniturePiece = _pieces().filter(func(p): return p.type == &"lamp")[0]
	var was := lamp.lamp_on()
	lamp.interact(player)
	_check(lamp.lamp_on() != was and lamp._light.visible == lamp.lamp_on(), "a lamp switches on and off")
	# Read.
	var pages := int(GameState.get_flag(&"pages_read", 0))
	var shelf: FurniturePiece = _pieces().filter(func(p): return p.type == &"bookshelf")[0]
	shelf.interact(player)
	_check(int(GameState.get_flag(&"pages_read", 0)) == pages + 1, "a bookshelf has stories to read")
	# Storage: really holds things.
	var chest: FurniturePiece = _pieces().filter(func(p): return p.type == &"chest")[0]
	var stone := GameState.count(&"stone")
	var moved := Furnishings.instance.deposit(chest.record, &"stone", 12)
	_check(moved == 12 and GameState.count(&"stone") == stone - 12 and Furnishings.stored_total(chest.record) == 12, "a chest stores resources (12 stone in)")
	var back := Furnishings.instance.withdraw(chest.record, &"stone", 5)
	_check(back == 5 and GameState.count(&"stone") == stone - 7, "and gives them back (5 out)")
	var full := Furnishings.instance.deposit(chest.record, &"wood", 999)
	_check(Furnishings.stored_total(chest.record) == 40, "but holds only so much (%d in, 40 max)" % full)
	Furnishings.instance.withdraw(chest.record, &"wood", 999)
	chest.interact(player)
	_check(StoragePanel.instance.is_open(), "tapping it opens the storage panel")
	StoragePanel.instance.close_panel()
	# Sleep in the bed.
	WorldClock.set_time(22.0)
	var day := WorldClock.day
	var bed: FurniturePiece = _pieces().filter(func(p): return p.type == &"bed")[0]
	bed.interact(player)
	await _frames(5)
	_check(player.pose == &"sleep" and player.model.position.y > 0.4, "tap the bed and you lie down on the mattress")
	await _seconds(1.0 + Interiors.FADE_TIME * 2.0 + 0.4)
	await _frames(3)
	_check(WorldClock.day == day + 1 and WorldClock.time_of_day < 8.0, "and wake up the next morning")
	_check(player.pose == &"" and player.model.position.y == 0.0, "standing beside the bed")
	WorldClock.set_time(10.0)
	await _leave()


## Carry a stool out of the front door and put it down outside.
func _carry_outside(house: PlacedStructure) -> void:
	await _enter(house)
	var player := _player()
	var mode := FurnishMode.instance
	mode.start_new(&"stool")
	player.global_position = Interiors.ROOM_ORIGIN + Vector3(-1.0, 0.05, 1.0)
	player.model.rotation.y = 0.0
	await _frames(3)
	mode.confirm()
	var stool: FurniturePiece = _pieces().filter(func(p): return p.type == &"stool")[0]
	var record: Dictionary = stool.record
	mode.set_arranging(true)
	stool.interact(player)
	await _frames(2)
	_check(FurnishMode.allows_interaction(Interiors.instance._room.find_child("ExitDoor", false, false).get_child(0)), "carrying, you can still use the door")
	await _leave()
	_check(mode.is_carrying(), "and walk out still carrying the stool")
	player.global_position = house.doorstep() + house.global_transform.basis.z * 2.0
	await _frames(3)
	var put := mode.confirm()
	_check(put == "" and String(record["place"]) == "outside", "then put it down outside (%s)" % ("ok" if put == "" else put))
	mode.set_arranging(false)


func _outdoors() -> void:
	var f := Furnishings.instance
	var spot := VillageLayout.ground_point(0, 0)
	var at := f.free_spot(&"bench_seat", "outside", Vector3(12, 0, 30), 0.0)
	_check(at != Vector3.INF, "there's room outdoors for a garden bench")
	var record := f.add(&"bench_seat", "outside", at, 0.0)
	_check(f.body_of(record) != null and f.body_of(record).get_parent() == f, "outdoor pieces stand in the village")
	_check(f.can_place(&"bed", "outside", at + Vector3(4, 0, 0), 0.0) != "", "beds belong indoors")
	_check(f.can_place(&"bench_seat", "outside", spot, 0.0) != "", "nothing goes on the meeting circle")


func _save_load(house: PlacedStructure) -> void:
	var place := Furnishings.place_of(house.record)
	var before := Furnishings.records_in(place).map(func(r): return [r["id"], r["type"], r["pos"], r["yaw"]])
	var chest: Dictionary = Furnishings.records_in(place).filter(func(r): return r["type"] == "chest")[0]
	GameState.add(&"food", 3)
	Furnishings.instance.deposit(chest, &"food", 3)
	var stored := Furnishings.stored_total(chest)
	var data: Dictionary = JSON.parse_string(JSON.stringify(GameState.to_dict()))
	GameState.from_dict(data)
	var after := Furnishings.records_in(place).map(func(r): return [r["id"], r["type"], r["pos"], r["yaw"]])
	_check(JSON.stringify(before) == JSON.stringify(after), "after saving and loading, every piece is where you left it (%d pieces)" % after.size())
	var chest_again: Dictionary = Furnishings.records_in(place).filter(func(r): return r["type"] == "chest")[0]
	_check(Furnishings.stored_total(chest_again) == stored, "and what's in the chest is still there")
	_check(Furnishings.records_in("outside").size() >= 2, "outdoor pieces are saved too")
	# The structure records came back as new dictionaries: rebind the house.
	for s in get_tree().get_nodes_in_group("placed_structures"):
		for r in GameState.structures:
			if int(r["uid"]) == int(s.record["uid"]):
				s.record = r
	await _enter(house)
	var pieces := _pieces()
	var matched := pieces.filter(func(p): return before.any(func(b): return int(b[0]) == int(p.record["id"]) and JSON.stringify(b[2]) == JSON.stringify(p.record["pos"])))
	_check(pieces.size() == before.size() and matched.size() == pieces.size(), "going back in, the room is as you left it")
	await _leave()


func _redecorate_and_expand(house: PlacedStructure) -> void:
	# Build > Redecorate, then tap the house: the panel opens for it.
	BuildMode.instance.set_edit_mode("redecorate")
	_check(house.get_interaction_verb() == "Redecorate", "in Redecorate, your house says Redecorate")
	house._on_interacted(_player())
	await _frames(2)
	_check(DesignPanel.instance.structure == house and DesignPanel.instance.is_open(), "tapping it opens the Design panel for that house")
	var before_design := HouseDesigns.of(house.record)
	(DesignPanel.instance.find_child("Next_roof", true, false) as Button).pressed.emit()
	var want_roof := int(HouseDesigns.step(before_design, "roof", 1)["roof"])  # skips paints not yet unlocked
	_check(int(HouseDesigns.of(house.record)["roof"]) == want_roof and want_roof != int(before_design["roof"]), "and changes it straight away")
	DesignPanel.instance.close_panel()
	await _frames(2)
	var d := HouseDesigns.of(house.record)
	BuildMode.instance.redecorate(house, HouseDesigns.step(d, "wall", 1))
	_check(int(HouseDesigns.of(house.record)["wall"]) == int(HouseDesigns.step(d, "wall", 1)["wall"]) and int(HouseDesigns.of(house.record)["wall"]) != int(d["wall"]), "a finished house can be redecorated")
	var place := Furnishings.place_of(house.record)
	var count := Furnishings.records_in(place).size()
	var why := BuildMode.instance.upgrade(house)
	_check(why == "" and house.get_type() == &"house_medium" and not house.is_complete(), "a small house can be expanded into a medium one (%s)" % ("ok" if why == "" else why))
	var left := int(StructureCatalog.info(&"house_medium")["work"]) - int(house.record["work"])
	_check(left == 2, "the extra rooms take 2 more stages to build (%d)" % left)
	while not house.is_complete():
		house.add_work(1.0)
	await _enter(house)
	var rooms: int = (HouseInterior.layout(&"house_medium")["rooms"] as Array).size()
	_check(Interiors.instance._room_size == HouseDesigns.size_info(&"house_medium")["inside"] and rooms == 2, "inside, it's bigger: a living room and a bedroom")
	var still := Furnishings.records_in(place).size() + Furnishings.stored().size()
	_check(Furnishings.records_in(place).size() == count, "all %d pieces of furniture came along (%d)" % [count, Furnishings.records_in(place).size()])
	var all_fit := Furnishings.records_in(place).all(func(r): return Furnishings.instance.can_place(StringName(String(r["type"])), place, Vector3(float(r["pos"][0]), 0, float(r["pos"][2])), float(r["yaw"]), r) == "")
	_check(all_fit, "and none is stuck in the new wall")
	# The new wall is solid; its doorway isn't.
	var space := get_viewport().world_3d.direct_space_state
	var o := Interiors.ROOM_ORIGIN
	var wall := space.intersect_ray(PhysicsRayQueryParameters3D.create(o + Vector3(-3.0, 1.0, 0.5), o + Vector3(-3.0, 1.0, -1.5)))
	var door := space.intersect_ray(PhysicsRayQueryParameters3D.create(o + Vector3(2.5, 1.0, 0.5), o + Vector3(2.5, 1.0, -1.5)))
	_check(not wall.is_empty() and door.is_empty(), "the wall between the rooms is solid, the doorway open")
	await _leave()
	_check(still >= count, "nothing was lost")


func _bigger_houses() -> void:
	var counts := []
	for type in [&"house_large", &"manor"]:
		var at := _open_ground(type, Vector3(50, 0, 60))
		var record := GameState.add_structure(type, at, 0.0)
		var house := await _finish(record)
		_check(house.find_children("*", "MeshInstance3D", true, false).size() > 0, "a %s can be built" % StructureCatalog.info(type)["name"])
		await _enter(house)
		var layout := HouseInterior.layout(type)
		counts.append(layout["rooms"].size())
		var lights := Interiors.instance._room.find_children("Light_*", "OmniLight3D", false, false).size()
		_check(lights == layout["rooms"].size(), "%s: %d rooms, each lit" % [StructureCatalog.info(type)["name"], lights])
		# Every room can be reached from the door through doorways (walk a ray path).
		await _leave()
	_check(counts == [3, 6], "the large house has 3 rooms, the manor 6 (%s)" % str(counts))


func _remove() -> void:
	var record: Dictionary = GameState.structures.filter(func(r): return r["type"] == "manor")[0]
	var house := _node_of(record)
	var place := Furnishings.place_of(record)
	var n := Furnishings.records_in(place).size()
	BuildMode.instance.remove(house)
	await _frames(3)
	_check(Furnishings.records_in(place).is_empty() and Furnishings.stored().size() >= n, "removing a house puts its furniture away (%d pieces)" % n)
