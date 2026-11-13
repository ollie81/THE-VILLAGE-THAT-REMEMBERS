class_name Interiors
extends Node3D
## Homes you can walk into. Each front door gets an "Enter" interaction; the
## room is built from code when you go in, at a spot far outside the world,
## and freed when you leave, so entering is a short fade with no loading and
## costs no memory while you're outdoors.
##
## Every founder's home has its own layout, colours and belongings (Mara's
## building plans, Elias's seed sacks, Nia's drying herbs, Tomas's workbench,
## Sera's trade goods). In others' homes you can sit at the table; in your own
## house you sleep in your bed and cook stew at the hearth (stew heals you in
## a fight). Saving indoors saves the doorstep.

signal entered(home_id: String)
signal left(home_id: String)

## Where rooms are built: far beyond the edge of the world.
const ROOM_ORIGIN := Vector3(0.0, 0.0, 400.0)
const ROOM_SIZE := Vector2(9.0, 7.0)
const WALL_HEIGHT := 3.2
const FADE_TIME := 0.22
## Visiting hours for other people's homes.
const VISIT_FROM := 6.0
const VISIT_UNTIL := 22.0
## Cooking a stew: what it takes, and how many you can keep.
const STEW_COST := {&"food": 2, &"herbs": 1}
const MAX_STEWS := 5

## Founders' homes: owner -> belongings and colours.
const HOMES := {
	"mara": {"layout": 0, "rug": Color(0.62, 0.32, 0.25), "props": "plans"},
	"elias": {"layout": 1, "rug": Color(0.45, 0.55, 0.3), "props": "seeds"},
	"nia": {"layout": 2, "rug": Color(0.42, 0.5, 0.62), "props": "herbs"},
	"tomas": {"layout": 0, "rug": Color(0.55, 0.42, 0.28), "props": "workbench"},
	"sera": {"layout": 1, "rug": Color(0.62, 0.45, 0.62), "props": "trade"},
	"player": {"layout": 2, "rug": Color(0.7, 0.55, 0.3), "props": "own"},
}

static var instance: Interiors

## The home you're in ("" outdoors), and where you came in.
var current: String = ""
var _outside_door := Vector3.ZERO
var _outside_yaw: float = 0.0
var _room: Node3D
var _fade: ColorRect
var _busy: bool = false
var _doors: Node3D


func _ready() -> void:
	name = "Interiors"
	instance = self
	_doors = Node3D.new()
	_doors.name = "Doors"
	add_child(_doors)
	for building in VillageLayout.get_buildings():
		if String(building["type"]) == "house" and String(building["owner"]) != "":
			_add_founder_door(building)


func _exit_tree() -> void:
	if instance == self:
		instance = null


func is_inside() -> bool:
	return current != ""


## Where the player should be saved while indoors (the doorstep outside).
func exit_position() -> Vector3:
	return _outside_door


## Height of a room's floor at x, z (NAN outside rooms): rooms are flat.
static func floor_at(x: float, z: float) -> float:
	if instance == null or instance._room == null:
		return NAN
	var local := Vector2(x - ROOM_ORIGIN.x, z - ROOM_ORIGIN.z)
	if absf(local.x) <= ROOM_SIZE.x * 0.5 + 0.5 and absf(local.y) <= ROOM_SIZE.y * 0.5 + 0.5:
		return ROOM_ORIGIN.y
	return NAN


# --- Doors outside ------------------------------------------------------------------

func _add_founder_door(building: Dictionary) -> void:
	var owner := String(building["owner"])
	var center: Vector3 = building["position"]
	var yaw := float(building["yaw"])
	var front := Basis(Vector3.UP, yaw) * Vector3(0, 0, 1)
	var at := center + front * (float(building["footprint"].y) * 0.5 + 0.7)
	var door := UsableObject.new()
	door.name = "Door_" + owner
	door.prompt = func(): return _door_prompt(owner)
	door.verb = func(): return "Enter" if _can_visit(owner) else "Knock"
	door.use = func(_actor): _knock_or_enter(owner, at + front * 0.6, yaw)
	door.position = VillageLayout.ground_point(at.x, at.z)
	_doors.add_child(door)
	var interactable := Interactable.new()
	interactable.radius = 1.0
	interactable.handler = door
	interactable.interacted.connect(func(actor): door.use.call(actor))
	door.add_child(interactable)


static func _owner_name(owner: String) -> String:
	var villager = GameManager.get_villager(StringName(owner))
	return villager.data.display_name if villager else owner.capitalize()


func _can_visit(owner: String) -> bool:
	var person := Population.get_person(owner)
	if person and not person.is_present():
		return true  # the house stands empty now; you may look in
	var hour := WorldClock.time_of_day
	return hour >= VISIT_FROM and hour < VISIT_UNTIL


func _door_prompt(owner: String) -> String:
	if _can_visit(owner):
		return "Enter %s's house" % _owner_name(owner)
	return "%s's house  (everyone's asleep)" % _owner_name(owner)


func _knock_or_enter(owner: String, outside: Vector3, yaw: float) -> void:
	if not _can_visit(owner):
		GameManager.notify("You knock softly. No answer: %s is asleep. Come back in the morning." % _owner_name(owner))
		return
	enter(owner, outside, yaw)


# --- Going in and out ---------------------------------------------------------------

## Goes into `home_id`'s room ("player" for your own house). `outside` is the
## doorstep to come back to, `yaw` the house's facing.
func enter(home_id: String, outside: Vector3, yaw: float) -> void:
	if _busy or is_inside() or GameManager.player == null:
		return
	_busy = true
	await _fade_to(1.0)
	_outside_door = outside
	_outside_yaw = yaw
	_room = _build_room(home_id)
	add_child(_room)
	current = home_id
	var player = GameManager.player
	player.stand_up()
	player.velocity = Vector3.ZERO
	# Just inside the door, facing into the room.
	player.global_position = ROOM_ORIGIN + Vector3(0, 0.1, ROOM_SIZE.y * 0.5 - 1.2)
	player.model.rotation.y = PI
	_set_indoor(true)
	Sounds.play("open", null, -6.0)
	entered.emit(home_id)
	await _fade_to(0.0)
	_busy = false


func leave() -> void:
	if _busy or not is_inside():
		return
	_busy = true
	await _fade_to(1.0)
	var home := current
	current = ""
	var player = GameManager.player
	player.stand_up()
	player.velocity = Vector3.ZERO
	player.global_position = _outside_door + Vector3(0, 0.3, 0)
	player.model.rotation.y = _outside_yaw + PI
	if _room:
		_room.queue_free()
		_room = null
	_set_indoor(false)
	Sounds.play("open", null, -6.0)
	left.emit(home)
	await _fade_to(0.0)
	_busy = false


func _set_indoor(indoor: bool) -> void:
	var rig = GameManager.player.camera_rig if GameManager.player else null
	if rig:
		rig.indoor = indoor
		rig.yaw = GameManager.player.model.rotation.y + PI
		rig.pitch = -0.38 if indoor else -0.3
	if Guide.instance:
		Guide.instance.enabled = not indoor
	Sounds.set_indoor(indoor)


func _fade_to(alpha: float) -> void:
	if _fade == null:
		var layer := CanvasLayer.new()
		layer.layer = 50
		add_child(layer)
		_fade = ColorRect.new()
		_fade.color = Color(0, 0, 0, 0)
		_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		layer.add_child(_fade)
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", alpha, FADE_TIME)
	await tween.finished


# --- Building a room ----------------------------------------------------------------

func _style(home_id: String) -> Dictionary:
	var key := "player" if home_id == "player" else home_id
	return BuildingFactory.HOUSE_STYLES.get(key, BuildingFactory.HOUSE_STYLES["mara"])


func _build_room(home_id: String) -> Node3D:
	var home: Dictionary = HOMES.get(home_id, HOMES["mara"])
	var style := _style(home_id)
	var room := Node3D.new()
	room.name = "Room_" + home_id
	room.position = ROOM_ORIGIN
	var kit := BuildingFactory.Kit.new(hash(home_id))
	var m := kit.mesh
	var w := ROOM_SIZE.x
	var d := ROOM_SIZE.y
	var h := WALL_HEIGHT
	var wall: Color = (style["wall"] as Color).lightened(0.08)
	var trim: Color = style["trim"]
	var floor_color := Color(0.55, 0.4, 0.26)
	var flip := -1.0 if int(home["layout"]) == 1 else 1.0

	# Floor planks, walls, beams and a ceiling (no ceiling collision, so the
	# camera never snags on it).
	for i in 9:
		var x := -w * 0.5 + (float(i) + 0.5) * w / 9.0
		m.add_box_at(Vector3(x, -0.05, 0), Vector3(w / 9.0 - 0.02, 0.1, d), floor_color.lightened(0.04 * float(i % 3)))
	kit.box_collider(Vector3(0, -0.25, 0), Vector3(w + 1.0, 0.5, d + 1.0))
	for side in [-1.0, 1.0]:
		m.add_box_at(Vector3(side * w * 0.5, h * 0.5, 0), Vector3(0.2, h, d + 0.2), wall)
		kit.box_collider(Vector3(side * (w * 0.5 + 0.1), h * 0.5, 0), Vector3(0.4, h, d + 0.4))
		m.add_box_at(Vector3(0, h * 0.5, side * d * 0.5), Vector3(w + 0.2, h, 0.2), wall)
		kit.box_collider(Vector3(0, h * 0.5, side * (d * 0.5 + 0.1)), Vector3(w + 0.4, h, 0.4))
		# Skirting and corner posts.
		m.add_box_at(Vector3(side * (w * 0.5 - 0.12), 0.08, 0), Vector3(0.06, 0.16, d), trim)
		m.add_box_at(Vector3(0, 0.08, side * (d * 0.5 - 0.12)), Vector3(w, 0.16, 0.06), trim)
		for s2 in [-1.0, 1.0]:
			m.add_box_at(Vector3(side * (w * 0.5 - 0.15), h * 0.5, s2 * (d * 0.5 - 0.15)), Vector3(0.22, h, 0.22), trim)
	m.add_box_at(Vector3(0, h + 0.05, 0), Vector3(w + 0.2, 0.1, d + 0.2), (style["roof"] as Color).darkened(0.35))
	for i in 4:
		m.add_box_at(Vector3(0, h - 0.12, -d * 0.5 + (float(i) + 0.5) * d / 4.0), Vector3(w, 0.18, 0.2), trim)

	# The door (and its way out), windows with daylight.
	var door_z := d * 0.5 - 0.12
	m.add_box_at(Vector3(0, 1.05, door_z), Vector3(1.1, 2.1, 0.08), BuildingFactory.WOOD_DARK)
	m.add_box_at(Vector3(0, 2.18, door_z - 0.02), Vector3(1.4, 0.14, 0.12), trim)
	m.add_box_at(Vector3(0.38, 1.05, door_z - 0.06), Vector3(0.07, 0.07, 0.06), style["accent"])
	_usable(room, "ExitDoor", Vector3(0, 0, door_z - 0.4), 1.0,
		func(): return "Go outside", func(): return "Leave", func(_a): leave())
	for wx in [-2.6, 2.6]:
		kit.glow.add_box_at(Vector3(wx, 1.7, door_z - 0.01), Vector3(0.9, 0.8, 0.04), Color.WHITE)
		m.add_box_at(Vector3(wx, 1.7, door_z - 0.04), Vector3(0.06, 0.8, 0.04), trim)
		m.add_box_at(Vector3(wx, 1.27, door_z - 0.1), Vector3(1.0, 0.06, 0.18), trim)
	kit.glow.add_box_at(Vector3(-flip * (w * 0.5 - 0.11), 1.7, -0.6), Vector3(0.04, 0.8, 0.9), Color.WHITE)

	# A rug in the middle.
	m.add_box_at(Vector3(0, 0.02, 0.3), Vector3(3.4, 0.03, 2.4), home["rug"])
	m.add_box_at(Vector3(0, 0.03, 0.3), Vector3(3.0, 0.03, 2.0), (home["rug"] as Color).lightened(0.18))

	# Bed in a back corner.
	var bed := Vector3(flip * (w * 0.5 - 1.25), 0, -d * 0.5 + 1.2)
	m.add_box_at(bed + Vector3(0, 0.25, 0), Vector3(1.5, 0.3, 2.2), BuildingFactory.WOOD)
	m.add_box_at(bed + Vector3(0, 0.47, 0.05), Vector3(1.36, 0.16, 2.0), Color(0.92, 0.9, 0.84))
	m.add_box_at(bed + Vector3(0, 0.56, 0.35), Vector3(1.4, 0.06, 1.35), style["accent"])
	m.add_box_at(bed + Vector3(0, 0.6, -0.72), Vector3(0.9, 0.14, 0.4), Color(0.97, 0.96, 0.92))
	m.add_box_at(bed + Vector3(0, 0.6, -1.08), Vector3(1.5, 0.9, 0.1), BuildingFactory.WOOD_DARK)
	kit.box_collider(bed + Vector3(0, 0.35, 0), Vector3(1.5, 0.7, 2.2))
	if home_id == "player":
		_usable(room, "Bed", bed + Vector3(-flip * 0.95, 0, 0.3), 1.0, _bed_prompt, func(): return "Sleep", _sleep)

	# Table and two chairs.
	var table := Vector3(-flip * 1.6, 0, -0.8) if int(home["layout"]) != 2 else Vector3(-flip * 2.2, 0, 0.6)
	m.add_box_at(table + Vector3(0, 0.74, 0), Vector3(1.4, 0.08, 0.9), BuildingFactory.WOOD)
	for lx in [-0.6, 0.6]:
		for lz in [-0.36, 0.36]:
			m.add_box_at(table + Vector3(lx, 0.36, lz), Vector3(0.08, 0.72, 0.08), BuildingFactory.WOOD_DARK)
	m.add_cylinder_at(table + Vector3(0.25, 0.78, 0.1), 0.08, 0.07, 0.14, 7, Color(0.75, 0.62, 0.45))
	m.add_cylinder_at(table + Vector3(-0.3, 0.78, -0.1), 0.18, 0.18, 0.03, 9, Color(0.9, 0.88, 0.82))
	kit.box_collider(table + Vector3(0, 0.4, 0), Vector3(1.4, 0.8, 0.9))
	for side in [-1.0, 1.0]:
		var chair := table + Vector3(0, 0, side * 0.95)
		m.add_box_at(chair + Vector3(0, 0.45, 0), Vector3(0.48, 0.06, 0.46), BuildingFactory.WOOD)
		m.add_box_at(chair + Vector3(0, 0.8, side * 0.21), Vector3(0.48, 0.65, 0.05), BuildingFactory.WOOD_DARK)
		for lx in [-0.2, 0.2]:
			for lz in [-0.18, 0.18]:
				m.add_box_at(chair + Vector3(lx, 0.22, lz), Vector3(0.05, 0.44, 0.05), BuildingFactory.WOOD_DARK)
		var seat := {"position": room.position + chair, "yaw": 0.0 if side < 0 else PI, "height": 0.48}
		_usable(room, "Chair", chair + Vector3(0, 0, side * 0.35), 0.7,
			func(): return "Sit at the table", func(): return "Sit",
			func(actor): if actor and actor.has_method("sit"): actor.sit(seat))

	# Hearth with a fire and a cooking pot.
	var hearth := Vector3(flip * (w * 0.5 - 1.6), 0, d * 0.5 - 1.6) if int(home["layout"]) == 2 else Vector3(-flip * (w * 0.5 - 0.7), 0, -0.3)
	var hearth_yaw := PI if int(home["layout"]) == 2 else (PI * 0.5 * flip)
	var hb := Basis(Vector3.UP, hearth_yaw)
	m.add_box(Transform3D(hb, hearth + Vector3(0, 0.75, 0)), Vector3(1.6, 1.5, 0.8), BuildingFactory.STONE)
	m.add_box(Transform3D(hb, hearth + hb * Vector3(0, 0.55, 0.36)), Vector3(0.9, 0.7, 0.12), Color(0.12, 0.1, 0.09))
	m.add_box(Transform3D(hb, hearth + Vector3(0, 2.3, 0)), Vector3(0.9, 1.6, 0.6), BuildingFactory.STONE_DARK)
	m.add_cylinder_at(hearth + hb * Vector3(0, 0.35, 0.55), 0.22, 0.18, 0.28, 9, Color(0.2, 0.2, 0.22))
	kit.box_collider(hearth + Vector3(0, 0.75, 0), Vector3(1.7, 1.5, 1.7))
	var fire := OmniLight3D.new()
	fire.position = hearth + hb * Vector3(0, 0.6, 0.7)
	fire.light_color = Color(1.0, 0.62, 0.32)
	fire.light_energy = 1.4
	fire.omni_range = 6.5
	room.add_child(fire)
	var flames := MeshBuilder.new(5)
	flames.color_jitter = 0.0
	flames.add_cylinder_at(Vector3.ZERO, 0.2, 0.0, 0.42, 6, Color.WHITE)
	var flame := MeshInstance3D.new()
	flame.mesh = flames.build(Materials.flame())
	flame.position = hearth + hb * Vector3(0, 0.25, 0.32)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	room.add_child(flame)
	if home_id == "player":
		_usable(room, "Hearth", hearth + hb * Vector3(0, 0, 1.2), 1.0, _cook_prompt, func(): return "Cook", _cook)

	# Shelves with jars, a chest, a lamp.
	var shelf := Vector3(-flip * 1.0, 0, -d * 0.5 + 0.25)
	for level in 3:
		m.add_box_at(shelf + Vector3(0, 0.7 + level * 0.55, 0), Vector3(1.6, 0.05, 0.3), BuildingFactory.WOOD)
		for j in 4:
			m.add_cylinder_at(shelf + Vector3(-0.55 + j * 0.37, 0.73 + level * 0.55, 0), 0.07, 0.06, 0.2, 7,
				[Color(0.75, 0.45, 0.3), Color(0.5, 0.65, 0.45), Color(0.85, 0.8, 0.6), Color(0.45, 0.5, 0.7)][(j + level) % 4])
	var chest := bed + Vector3(-flip * 1.25, 0, 0.6)
	m.add_box_at(chest + Vector3(0, 0.3, 0), Vector3(0.9, 0.6, 0.55), BuildingFactory.WOOD_DARK)
	m.add_box_at(chest + Vector3(0, 0.62, 0), Vector3(0.94, 0.06, 0.6), BuildingFactory.WOOD)
	m.add_box_at(chest + Vector3(0, 0.45, 0.28), Vector3(0.12, 0.14, 0.04), Color(0.8, 0.7, 0.35))
	kit.box_collider(chest + Vector3(0, 0.3, 0), Vector3(0.9, 0.6, 0.55))
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, h - 0.6, 0)
	lamp.light_color = Color(1.0, 0.85, 0.6)
	lamp.light_energy = 0.9
	lamp.omni_range = 8.0
	room.add_child(lamp)
	m.add_cylinder_at(Vector3(0, h - 0.75, 0), 0.16, 0.1, 0.25, 8, Color(0.95, 0.8, 0.45))

	_add_belongings(m, kit, String(home["props"]), flip)
	kit.finish(room)
	return room


## What makes each home its owner's.
func _add_belongings(m: MeshBuilder, kit, props: String, flip: float) -> void:
	var w := ROOM_SIZE.x
	var d := ROOM_SIZE.y
	match props:
		"plans":  # Mara, builder: a drawing table and rolled plans
			var at := Vector3(flip * 1.2, 0, 1.6)
			m.add_box_at(at + Vector3(0, 0.95, 0), Vector3(1.2, 0.05, 0.8), BuildingFactory.WOOD, 0.2)
			m.add_box_at(at + Vector3(0, 0.97, 0), Vector3(0.9, 0.01, 0.6), Color(0.93, 0.9, 0.8), 0.2)
			m.add_box_at(at + Vector3(0, 0.47, 0), Vector3(0.12, 0.95, 0.12), BuildingFactory.WOOD_DARK)
			for i in 3:
				m.add_cylinder_at(at + Vector3(0.75, 0.1 + i * 0.12, -0.3 + i * 0.1), 0.05, 0.05, 0.6, 6, Color(0.9, 0.85, 0.7))
			kit.box_collider(at + Vector3(0, 0.5, 0), Vector3(1.2, 1.0, 0.8))
		"seeds":  # Elias, farmer: sacks of seed and a basket of vegetables
			for i in 3:
				m.add_blob_at(Vector3(flip * (w * 0.5 - 0.6), 0.35, 1.4 - i * 0.7), Vector3(0.35, 0.4, 0.3), Color(0.78, 0.68, 0.48), 7, 4, 0.12)
			m.add_cylinder_at(Vector3(-flip * 0.4, 0, 2.1), 0.32, 0.38, 0.35, 10, Color(0.6, 0.45, 0.25))
			for i in 5:
				m.add_blob_at(Vector3(-flip * 0.4 + (i % 3) * 0.12 - 0.12, 0.4, 2.1 + (i / 3) * 0.12), Vector3(0.09, 0.09, 0.09),
					[Color(0.9, 0.5, 0.15), Color(0.45, 0.7, 0.3), Color(0.8, 0.2, 0.2)][i % 3], 6, 4, 0.0)
		"herbs":  # Nia, herbalist: bundles drying under the beams, pots of plants
			for i in 7:
				var x := -2.8 + i * 0.9
				m.add_box_at(Vector3(x, WALL_HEIGHT - 0.5, -1.2), Vector3(0.02, 0.5, 0.02), Color(0.6, 0.55, 0.4))
				m.add_blob_at(Vector3(x, WALL_HEIGHT - 0.85, -1.2), Vector3(0.13, 0.25, 0.13), Color(0.4, 0.6, 0.3).lightened(0.05 * (i % 3)), 6, 4, 0.2)
			for i in 3:
				var pot := Vector3(flip * (1.0 + i * 0.6), 0, 2.4)
				m.add_cylinder_at(pot, 0.17, 0.2, 0.3, 8, Color(0.72, 0.4, 0.28))
				m.add_blob_at(pot + Vector3(0, 0.45, 0), Vector3(0.22, 0.25, 0.22), Color(0.35, 0.6, 0.3), 7, 4, 0.2)
		"workbench":  # Tomas, craftsman: a bench with tools and a half-made chair
			var at := Vector3(flip * 1.0, 0, 1.8)
			m.add_box_at(at + Vector3(0, 0.85, 0), Vector3(1.8, 0.1, 0.7), BuildingFactory.WOOD)
			for lx in [-0.8, 0.8]:
				m.add_box_at(at + Vector3(lx, 0.42, 0), Vector3(0.1, 0.84, 0.6), BuildingFactory.WOOD_DARK)
			m.add_box_at(at + Vector3(-0.4, 0.95, 0), Vector3(0.35, 0.06, 0.1), Color(0.6, 0.62, 0.66))
			m.add_box_at(at + Vector3(0.3, 0.93, 0.1), Vector3(0.5, 0.04, 0.12), Color(0.85, 0.7, 0.5))
			kit.box_collider(at + Vector3(0, 0.45, 0), Vector3(1.8, 0.9, 0.7))
		"trade":  # Sera, trader: crates, bolts of cloth, a little scale
			for i in 3:
				var crate := Vector3(flip * (w * 0.5 - 0.6), 0.3 + (0.6 if i == 2 else 0.0), 1.6 - (i % 2) * 0.7)
				m.add_box_at(crate, Vector3(0.6, 0.6, 0.6), BuildingFactory.WOOD.lightened(0.1))
			for i in 3:
				m.add_cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(-flip * 0.6, 0.15 + i * 0.22, 2.3)), 0.11, 0.11, 0.9, 8,
					[Color(0.75, 0.25, 0.3), Color(0.25, 0.45, 0.7), Color(0.85, 0.7, 0.25)][i])
			kit.box_collider(Vector3(flip * (w * 0.5 - 0.6), 0.6, 1.25), Vector3(0.7, 1.2, 1.4))
		"own":  # your house: a coat peg and your boots by the door
			m.add_box_at(Vector3(1.4, 1.6, d * 0.5 - 0.2), Vector3(0.6, 0.06, 0.06), BuildingFactory.WOOD_DARK)
			m.add_box_at(Vector3(1.25, 1.3, d * 0.5 - 0.25), Vector3(0.35, 0.6, 0.08), Color(0.35, 0.45, 0.65))
			for bx in [0.9, 1.1]:
				m.add_box_at(Vector3(bx, 0.12, d * 0.5 - 0.5), Vector3(0.14, 0.24, 0.3), Color(0.4, 0.28, 0.18))


func _usable(room: Node3D, object_name: String, at: Vector3, radius: float, prompt: Callable, verb: Callable, use: Callable) -> void:
	var holder := UsableObject.new()
	holder.name = object_name if room.find_child(object_name, false, false) == null else object_name + str(room.get_child_count())
	holder.prompt = prompt
	holder.verb = verb
	holder.use = use
	holder.position = at
	room.add_child(holder)
	var interactable := Interactable.new()
	interactable.radius = radius
	interactable.handler = holder
	interactable.interacted.connect(func(actor): use.call(actor))
	holder.add_child(interactable)


# --- Your own home ------------------------------------------------------------------

func _bed_prompt() -> String:
	return "Sleep until morning" if PlayerController.is_night() else "Your bed  (sleep here at night, or have a nap)"


func _sleep(actor) -> void:
	if PlayerController.is_night():
		if actor and actor.has_method("sleep_until_morning"):
			actor.sleep_until_morning(true)
		return
	# A daytime nap: two hours pass and you feel rested.
	WorldClock.advance(2.0)
	if actor and actor.get("combat") and actor.combat:
		actor.combat.heal_full()
	GameManager.notify("You have a short nap. Two hours pass and you feel rested.")


static func stews() -> int:
	return int(GameState.get_flag(&"stews", 0))


func _cook_prompt() -> String:
	if stews() >= MAX_STEWS:
		return "Hearth  (your pot is full: %d stews)" % stews()
	return "Cook a stew  (%s; heals you in a fight)  [%d / %d]" % [GameState.cost_text(STEW_COST), stews(), MAX_STEWS]


func _cook(actor) -> void:
	if stews() >= MAX_STEWS:
		GameManager.notify("You already have %d stews. That's all your pot can keep." % MAX_STEWS)
		return
	if not GameState.can_afford(STEW_COST):
		GameManager.notify("%s to cook a stew." % GameState.missing_text(STEW_COST))
		return
	GameState.spend(STEW_COST)
	GameState.increment(&"stews")
	if actor and actor.has_method("perform_action"):
		actor.perform_action(&"gather", 1.0, actor.global_position + actor.get_facing())
	Sounds.play("pickup", null, -4.0)
	GameManager.notify("You cook a hearty stew (%d / %d). Eat it to heal when you're hurt." % [stews(), MAX_STEWS])
