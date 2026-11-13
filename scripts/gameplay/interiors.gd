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
const ROOM_SIZE := Vector2(10.0, 8.0)
const WALL_HEIGHT := 3.4
## Where you appear: well inside the door, in the clear entrance area.
const SPAWN := Vector3(0.0, 0.05, 2.3)
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

## Goes into `home_id`'s room ("player" for your own house, "cottage_<uid>"
## for a cottage). `outside` is the doorstep to come back to, `yaw` the
## house's facing.
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
	_place_player_standing(ROOM_ORIGIN + SPAWN, PI)
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
	_place_player_standing(_outside_door + Vector3(0, 0.3, 0), _outside_yaw)
	if _room:
		_room.queue_free()
		_room = null
	_set_indoor(false)
	Sounds.play("open", null, -6.0)
	left.emit(home)
	await _fade_to(0.0)
	_busy = false


## Upright, still, no leftover sitting, lying or action pose.
func _place_player_standing(at: Vector3, facing_yaw: float) -> void:
	var player = GameManager.player
	player.stand_up()
	player.pose = &""
	player._seat = {}
	player._action_time = 0.0
	player.velocity = Vector3.ZERO
	player.model.position = Vector3.ZERO
	player.model.rotation = Vector3(0, facing_yaw, 0)
	player.model.set_animation(&"idle")
	if player.combat:
		player.combat.blocking = false
	player.global_position = at


func _set_indoor(indoor: bool) -> void:
	var rig = GameManager.player.camera_rig if GameManager.player else null
	if rig:
		rig.indoor = indoor
		rig.yaw = GameManager.player.model.rotation.y + PI
		rig.pitch = -0.5 if indoor else -0.3
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


# --- Who lives where ----------------------------------------------------------------

## Settings for a home: layout variant (0-2), mirror (1/-1), colours and
## belongings. Founders' homes are fixed; a cottage's come from its number
## and its residents' trades, so each cottage is its own and always the same.
func home_config(home_id: String) -> Dictionary:
	if HOMES.has(home_id):
		var fixed: Dictionary = HOMES[home_id].duplicate()
		fixed["style"] = BuildingFactory.HOUSE_STYLES.get(home_id, BuildingFactory.HOUSE_STYLES["mara"])
		fixed["flip"] = -1.0 if int(fixed["layout"]) == 1 else 1.0
		fixed["wood"] = [BuildingFactory.WOOD, BuildingFactory.WOOD.darkened(0.15), BuildingFactory.WOOD.lightened(0.12)][int(fixed["layout"])]
		return fixed
	var seed := absi(hash(home_id))
	var rugs := [Color(0.6, 0.35, 0.3), Color(0.35, 0.5, 0.6), Color(0.5, 0.58, 0.32), Color(0.62, 0.5, 0.3), Color(0.55, 0.4, 0.6)]
	var props := "own"
	var residents := cottage_residents(home_id)
	if not residents.is_empty():
		props = {"farmer": "seeds", "cook": "seeds", "fisher": "seeds", "builder": "plans", "woodcutter": "workbench",
			"craftsman": "workbench", "stonemason": "workbench", "herbalist": "herbs", "trader": "trade", "weaver": "trade"}.get(residents[0].profession, "own")
	return {"layout": seed % 3, "flip": -1.0 if (seed / 3) % 2 == 1 else 1.0, "rug": rugs[seed % rugs.size()],
		"props": props, "style": BuildingFactory.HOUSE_STYLES["cottage"],
		"wood": [BuildingFactory.WOOD, BuildingFactory.WOOD.darkened(0.15), BuildingFactory.WOOD.lightened(0.12)][(seed / 7) % 3]}


static func cottage_residents(home_id: String) -> Array:
	var out: Array = []
	for id in Population.residents_of(home_id):
		var person := Population.get_person(String(id))
		if person:
			out.append(person)
	return out


func _style(home_id: String) -> Dictionary:
	return home_config(home_id)["style"]


# --- Building a room ----------------------------------------------------------------
#
# Floor plan (seen from above, the door at the bottom, mirrored for some homes):
#
#   +----------------------------------+
#   | kitchen: hearth   shelf   bed    |
#   | counter            rug    chest  |
#   |      table+chairs        bench   |
#   | plant    [ clear entrance ]  belongings
#   +--------------- door -------------+

func _build_room(home_id: String) -> Node3D:
	var home := home_config(home_id)
	var style: Dictionary = home["style"]
	var own := home_id == "player"
	var room := Node3D.new()
	room.name = "Room_" + home_id
	room.position = ROOM_ORIGIN
	var kit := BuildingFactory.Kit.new(hash(home_id))
	var m := kit.mesh
	var w := ROOM_SIZE.x
	var d := ROOM_SIZE.y
	var h := WALL_HEIGHT
	var f: float = home["flip"]
	var layout: int = home["layout"]
	var wood: Color = home["wood"]
	var dark: Color = wood.darkened(0.3)
	var wall: Color = (style["wall"] as Color).lightened(0.06)
	var trim: Color = style["trim"]
	var accent: Color = style["accent"]

	# Shell: plank floor, plastered walls with a wooden dado, beams, ceiling.
	for i in 10:
		var x := -w * 0.5 + (float(i) + 0.5) * w / 10.0
		m.add_box_at(Vector3(x, -0.05, 0), Vector3(w / 10.0 - 0.02, 0.1, d), Color(0.58, 0.42, 0.27).lightened(0.035 * float(i % 3)))
	kit.box_collider(Vector3(0, -0.25, 0), Vector3(w + 1.0, 0.5, d + 1.0))
	for side in [-1.0, 1.0]:
		m.add_box_at(Vector3(side * w * 0.5, h * 0.5, 0), Vector3(0.2, h, d + 0.2), wall)
		m.add_box_at(Vector3(side * (w * 0.5 - 0.11), 0.5, 0), Vector3(0.04, 1.0, d - 0.2), wood.darkened(0.1))
		kit.box_collider(Vector3(side * (w * 0.5 + 0.1), h * 0.5, 0), Vector3(0.4, h, d + 0.4))
		m.add_box_at(Vector3(0, h * 0.5, side * d * 0.5), Vector3(w + 0.2, h, 0.2), wall)
		m.add_box_at(Vector3(0, 0.5, side * (d * 0.5 - 0.11)), Vector3(w - 0.2, 1.0, 0.04), wood.darkened(0.1))
		kit.box_collider(Vector3(0, h * 0.5, side * (d * 0.5 + 0.1)), Vector3(w + 0.4, h, 0.4))
		for s2 in [-1.0, 1.0]:
			m.add_box_at(Vector3(side * (w * 0.5 - 0.15), h * 0.5, s2 * (d * 0.5 - 0.15)), Vector3(0.24, h, 0.24), trim)
	m.add_box_at(Vector3(0, h + 0.05, 0), Vector3(w + 0.2, 0.1, d + 0.2), wood.darkened(0.45))
	for i in 5:
		m.add_box_at(Vector3(0, h - 0.13, -d * 0.5 + (float(i) + 0.5) * d / 5.0), Vector3(w, 0.2, 0.22), trim)

	# The door (and the way out), with a frame and a mat.
	var door_z := d * 0.5 - 0.12
	m.add_box_at(Vector3(0, 1.1, door_z), Vector3(1.15, 2.2, 0.08), BuildingFactory.WOOD_DARK)
	for sx in [-1.0, 1.0]:
		m.add_box_at(Vector3(sx * 0.66, 1.15, door_z - 0.03), Vector3(0.14, 2.3, 0.12), trim)
		m.add_box_at(Vector3(sx * 0.25, 1.1, door_z - 0.05), Vector3(0.04, 2.0, 0.03), BuildingFactory.WOOD_DARK.lightened(0.1))
	m.add_box_at(Vector3(0, 2.33, door_z - 0.03), Vector3(1.46, 0.14, 0.12), trim)
	m.add_box_at(Vector3(0.4, 1.05, door_z - 0.07), Vector3(0.08, 0.08, 0.06), accent)
	m.add_box_at(Vector3(0, 0.015, door_z - 0.8), Vector3(1.3, 0.02, 0.8), Color(0.62, 0.48, 0.3))
	_usable(room, "ExitDoor", Vector3(0, 0, door_z - 0.55), 1.0,
		func(): return "Go outside", func(): return "Leave", func(_a): leave())
	# Coat pegs by the door.
	m.add_box_at(Vector3(-1.5, 1.7, door_z - 0.05), Vector3(0.7, 0.07, 0.06), dark)
	m.add_box_at(Vector3(-1.62, 1.35, door_z - 0.1), Vector3(0.32, 0.6, 0.08), accent.darkened(0.25))

	# Windows: front wall either side of the door, and one on each side wall,
	# with frames, sills and curtains.
	for wx in [-3.0, 3.0]:
		_window(m, kit, Vector3(wx, 1.7, door_z), 0.0, trim, accent)
	for side in [-1.0, 1.0]:
		_window(m, kit, Vector3(side * (w * 0.5 - 0.12), 1.7, 0.8), PI * 0.5, trim, accent)

	# Bedroom corner: the bed against the back wall, a side table with a
	# candle, a chest at the foot, a rug.
	var bed := Vector3(f * 3.3, 0, -d * 0.5 + 1.35)
	m.add_box_at(bed + Vector3(0, 0.28, 0), Vector3(1.6, 0.32, 2.3), wood)
	m.add_box_at(bed + Vector3(0, 0.5, 0.05), Vector3(1.46, 0.16, 2.1), Color(0.93, 0.91, 0.86))
	m.add_box_at(bed + Vector3(0, 0.6, 0.4), Vector3(1.5, 0.07, 1.4), accent)
	m.add_box_at(bed + Vector3(0, 0.62, 1.05), Vector3(1.52, 0.08, 0.12), accent.lightened(0.2))
	m.add_box_at(bed + Vector3(0, 0.64, -0.78), Vector3(1.0, 0.15, 0.42), Color(0.98, 0.97, 0.94))
	m.add_box_at(bed + Vector3(0, 0.75, -1.14), Vector3(1.6, 1.05, 0.12), dark)
	m.add_box_at(bed + Vector3(0, 0.4, 1.12), Vector3(1.6, 0.5, 0.08), dark)
	kit.box_collider(bed + Vector3(0, 0.4, 0), Vector3(1.6, 0.8, 2.3))
	var side_table := bed + Vector3(-f * 1.2, 0, -0.85)
	m.add_box_at(side_table + Vector3(0, 0.3, 0), Vector3(0.5, 0.6, 0.45), wood)
	m.add_cylinder_at(side_table + Vector3(0, 0.6, 0), 0.05, 0.05, 0.14, 7, Color(0.97, 0.94, 0.85))
	kit.box_collider(side_table + Vector3(0, 0.3, 0), Vector3(0.5, 0.6, 0.45))
	var chest := bed + Vector3(0, 0, 1.55)
	m.add_box_at(chest + Vector3(0, 0.27, 0), Vector3(1.1, 0.54, 0.55), dark)
	m.add_box_at(chest + Vector3(0, 0.56, 0), Vector3(1.14, 0.06, 0.6), wood)
	m.add_box_at(chest + Vector3(0, 0.42, 0.29), Vector3(0.12, 0.14, 0.04), Color(0.82, 0.7, 0.35))
	kit.box_collider(chest + Vector3(0, 0.3, 0), Vector3(1.1, 0.6, 0.55))
	m.add_box_at(bed + Vector3(-f * 0.2, 0.012, 0.6), Vector3(2.6, 0.02, 2.0), (home["rug"] as Color).darkened(0.1))
	if own:
		_usable(room, "Bed", bed + Vector3(-f * 1.25, 0, 0.35), 0.9, _bed_prompt, func(): return "Sleep", _sleep)
		_usable(room, "Chest", chest + Vector3(0, 0, 0.75), 0.8,
			func(): return "Your chest  (see what the village has stored)", func(): return "Open", _open_chest)

	# Kitchen corner: hearth with a fire and pot against the back wall, a
	# worktop with food along the side wall, shelves of jars, hanging pans.
	var hearth := Vector3(-f * 3.4, 0, -d * 0.5 + 0.5)
	m.add_box_at(hearth + Vector3(0, 0.75, 0), Vector3(1.9, 1.5, 0.9), BuildingFactory.STONE)
	m.add_box_at(hearth + Vector3(0, 0.55, 0.41), Vector3(1.0, 0.72, 0.1), Color(0.12, 0.1, 0.09))
	m.add_box_at(hearth + Vector3(0, 1.55, 0.05), Vector3(2.1, 0.12, 1.0), trim)
	m.add_box_at(hearth + Vector3(0, 2.45, -0.05), Vector3(1.0, 1.8, 0.7), BuildingFactory.STONE_DARK)
	m.add_cylinder_at(hearth + Vector3(0, 0.32, 0.55), 0.24, 0.2, 0.3, 9, Color(0.2, 0.2, 0.22))
	for i in 3:
		m.add_cylinder_at(hearth + Vector3(-0.6 + i * 0.6, 1.61, 0.1), 0.08, 0.07, 0.18, 7, [Color(0.75, 0.45, 0.3), Color(0.85, 0.8, 0.6), Color(0.45, 0.5, 0.7)][i])
	kit.box_collider(hearth + Vector3(0, 0.75, 0.2), Vector3(1.9, 1.5, 1.3))
	var fire := OmniLight3D.new()
	fire.position = hearth + Vector3(0, 0.6, 0.9)
	fire.light_color = Color(1.0, 0.6, 0.3)
	fire.light_energy = 1.6
	fire.omni_range = 7.0
	room.add_child(fire)
	var flames := MeshBuilder.new(5)
	flames.color_jitter = 0.0
	flames.add_cylinder_at(Vector3.ZERO, 0.22, 0.0, 0.45, 6, Color.WHITE)
	flames.add_cylinder_at(Vector3(0.15, 0, 0.05), 0.12, 0.0, 0.3, 5, Color.WHITE)
	var flame := MeshInstance3D.new()
	flame.mesh = flames.build(Materials.flame())
	flame.position = hearth + Vector3(0, 0.22, 0.3)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	room.add_child(flame)
	if own:
		_usable(room, "Hearth", hearth + Vector3(0, 0, 1.45), 0.9, _cook_prompt, func(): return "Cook", _cook)
	var counter := Vector3(-f * (w * 0.5 - 0.45), 0, -0.9)
	m.add_box_at(counter + Vector3(0, 0.45, 0), Vector3(0.75, 0.9, 2.0), wood)
	m.add_box_at(counter + Vector3(0, 0.92, 0), Vector3(0.82, 0.06, 2.06), wood.lightened(0.1))
	m.add_blob_at(counter + Vector3(0, 1.02, -0.5), Vector3(0.2, 0.1, 0.14), Color(0.85, 0.65, 0.35), 7, 4, 0.1)
	for i in 4:
		m.add_blob_at(counter + Vector3(0.05, 1.0, 0.2 + i * 0.13), Vector3(0.06, 0.06, 0.06), [Color(0.9, 0.5, 0.15), Color(0.8, 0.2, 0.2), Color(0.45, 0.7, 0.3)][i % 3], 6, 3, 0.0)
	m.add_cylinder_at(counter + Vector3(0, 0.95, 0.75), 0.13, 0.11, 0.1, 9, Color(0.92, 0.9, 0.85))
	kit.box_collider(counter + Vector3(0, 0.45, 0), Vector3(0.8, 0.9, 2.0))
	var shelf_x := -f * (w * 0.5 - 0.17)
	for level in 2:
		m.add_box_at(Vector3(shelf_x, 1.55 + level * 0.45, -0.9), Vector3(0.3, 0.05, 1.8), wood.darkened(0.05))
		for j in 5:
			m.add_cylinder_at(Vector3(shelf_x, 1.58 + level * 0.45, -1.6 + j * 0.35), 0.07, 0.06, 0.18, 7,
				[Color(0.75, 0.45, 0.3), Color(0.5, 0.65, 0.45), Color(0.85, 0.8, 0.6), Color(0.45, 0.5, 0.7), Color(0.8, 0.6, 0.3)][(j + level) % 5])
	for i in 3:
		m.add_cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(-f * (2.2 - i * 0.35), h - 0.9, -d * 0.5 + 0.35)), 0.13, 0.13, 0.03, 9, Color(0.35, 0.33, 0.33))
	var barrel := Vector3(-f * (w * 0.5 - 0.5), 0, 0.6)
	m.add_cylinder_at(barrel, 0.3, 0.32, 0.8, 10, wood.darkened(0.12))
	m.add_cylinder_at(barrel + Vector3(0, 0.25, 0), 0.33, 0.33, 0.05, 10, Color(0.4, 0.4, 0.42))
	kit.box_collider(barrel + Vector3(0, 0.4, 0), Vector3(0.65, 0.8, 0.65))

	# Dining: a table (round or long) with two chairs, a jug and bread.
	var table := Vector3(-f * 1.7, 0, 0.3)
	if layout == 1:
		m.add_cylinder_at(table + Vector3(0, 0.72, 0), 0.62, 0.62, 0.07, 14, wood.lightened(0.05))
		m.add_cylinder_at(table + Vector3(0, 0, 0), 0.12, 0.08, 0.72, 8, dark)
	else:
		m.add_box_at(table + Vector3(0, 0.74, 0), Vector3(1.5, 0.08, 0.95), wood.lightened(0.05))
		for lx in [-0.65, 0.65]:
			for lz in [-0.38, 0.38]:
				m.add_box_at(table + Vector3(lx, 0.36, lz), Vector3(0.08, 0.72, 0.08), dark)
	m.add_cylinder_at(table + Vector3(0.25, 0.78, 0.1), 0.08, 0.07, 0.16, 7, Color(0.75, 0.62, 0.45))
	m.add_cylinder_at(table + Vector3(-0.3, 0.78, -0.12), 0.2, 0.2, 0.03, 10, Color(0.92, 0.9, 0.85))
	m.add_blob_at(table + Vector3(-0.3, 0.84, -0.12), Vector3(0.12, 0.06, 0.08), Color(0.82, 0.6, 0.32), 6, 3, 0.1)
	kit.box_collider(table + Vector3(0, 0.4, 0), Vector3(1.5, 0.8, 0.95))
	for side in [-1.0, 1.0]:
		var chair := table + Vector3(0, 0, side * 0.95)
		m.add_box_at(chair + Vector3(0, 0.45, 0), Vector3(0.48, 0.06, 0.46), wood)
		m.add_box_at(chair + Vector3(0, 0.82, side * 0.21), Vector3(0.48, 0.68, 0.05), dark)
		for lx in [-0.2, 0.2]:
			for lz in [-0.18, 0.18]:
				m.add_box_at(chair + Vector3(lx, 0.22, lz), Vector3(0.05, 0.44, 0.05), dark)
		var seat := {"position": room.position + chair, "yaw": 0.0 if side < 0 else PI, "height": 0.48}
		_usable(room, "Chair", chair + Vector3(0, 0, side * 0.4), 0.6,
			func(): return "Sit at the table", func(): return "Sit",
			func(actor): if actor and actor.has_method("sit"): actor.sit(seat))

	# A dresser or bookcase on the back wall between kitchen and bed, with a
	# picture above, and plants by the door.
	var back := Vector3(f * 0.3, 0, -d * 0.5 + 0.3)
	if layout == 2:
		m.add_box_at(back + Vector3(0, 0.95, 0), Vector3(1.4, 1.9, 0.4), dark)
		for level in 4:
			m.add_box_at(back + Vector3(0, 0.3 + level * 0.45, 0.05), Vector3(1.3, 0.04, 0.34), wood)
			for j in 5:
				m.add_box_at(back + Vector3(-0.5 + j * 0.24, 0.45 + level * 0.45, 0.06), Vector3(0.08, 0.28, 0.22),
					[Color(0.6, 0.2, 0.2), Color(0.25, 0.4, 0.6), Color(0.3, 0.5, 0.3), Color(0.7, 0.55, 0.25), Color(0.45, 0.3, 0.5)][(j + level) % 5])
	else:
		m.add_box_at(back + Vector3(0, 0.5, 0), Vector3(1.5, 1.0, 0.45), dark)
		m.add_box_at(back + Vector3(0, 1.02, 0), Vector3(1.56, 0.05, 0.5), wood)
		for j in 3:
			m.add_box_at(back + Vector3(-0.5 + j * 0.5, 0.55, 0.23), Vector3(0.4, 0.35, 0.02), wood.lightened(0.08))
		m.add_cylinder_at(back + Vector3(0.45, 1.05, 0), 0.1, 0.08, 0.25, 8, accent)
		m.add_blob_at(back + Vector3(0.45, 1.38, 0), Vector3(0.18, 0.16, 0.18), Color(0.95, 0.55, 0.5), 6, 3, 0.2)
	kit.box_collider(back + Vector3(0, 0.6, 0), Vector3(1.5, 1.2, 0.45))
	m.add_box_at(back + Vector3(0, 2.25, 0.05), Vector3(1.0, 0.7, 0.05), trim)
	m.add_box_at(back + Vector3(0, 2.25, 0.08), Vector3(0.86, 0.56, 0.02), Color(0.45, 0.62, 0.75))
	m.add_box_at(back + Vector3(0, 2.1, 0.09), Vector3(0.86, 0.22, 0.02), Color(0.4, 0.6, 0.35))
	for corner in [-1.0, 1.0]:
		var pot := Vector3(corner * (w * 0.5 - 0.55), 0, d * 0.5 - 0.6)
		m.add_cylinder_at(pot, 0.2, 0.24, 0.4, 9, Color(0.72, 0.4, 0.28))
		m.add_blob_at(pot + Vector3(0, 0.62, 0), Vector3(0.3, 0.32, 0.3), Color(0.35, 0.6, 0.3), 7, 4, 0.25)
		kit.box_collider(pot + Vector3(0, 0.3, 0), Vector3(0.5, 0.6, 0.5))

	# A warm lamp overhead.
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, h - 0.7, -0.4)
	lamp.light_color = Color(1.0, 0.84, 0.6)
	lamp.light_energy = 1.0
	lamp.omni_range = 9.0
	room.add_child(lamp)
	m.add_box_at(Vector3(0, h - 0.4, -0.4), Vector3(0.03, 0.5, 0.03), dark)
	m.add_cylinder_at(Vector3(0, h - 0.8, -0.4), 0.22, 0.12, 0.25, 8, Color(0.96, 0.82, 0.48))

	_add_belongings(m, kit, String(home["props"]), f)
	kit.finish(room)
	# Window glass shows the sky outside: daylight by day, deep blue at night.
	var glass := room.find_child("Windows", false, false) as MeshInstance3D
	if glass:
		var sky := StandardMaterial3D.new()
		sky.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var night := WorldClock.time_of_day >= 19.5 or WorldClock.time_of_day < 5.5
		sky.albedo_color = Color(0.13, 0.17, 0.32) if night else Color(0.84, 0.93, 1.0)
		glass.material_override = sky
	return room


## A window with glass that glows like daylight, a frame, sill and curtains.
func _window(m: MeshBuilder, kit, at: Vector3, yaw: float, trim: Color, accent: Color) -> void:
	var b := Basis(Vector3.UP, yaw)
	var inward := b * Vector3(0, 0, -1)
	kit.glow.add_box(Transform3D(b, at + inward * 0.005), Vector3(0.95, 0.85, 0.04), Color.WHITE)
	m.add_box(Transform3D(b, at + inward * 0.03), Vector3(0.06, 0.85, 0.05), trim)
	m.add_box(Transform3D(b, at + inward * 0.03), Vector3(0.95, 0.06, 0.05), trim)
	m.add_box(Transform3D(b, at + Vector3(0, -0.47, 0) + inward * 0.08), Vector3(1.1, 0.07, 0.18), trim)
	m.add_box(Transform3D(b, at + Vector3(0, 0.5, 0) + inward * 0.04), Vector3(1.2, 0.08, 0.08), trim.darkened(0.2))
	for sx in [-1.0, 1.0]:
		m.add_box(Transform3D(b, at + b * Vector3(sx * 0.62, -0.05, 0) + inward * 0.07), Vector3(0.22, 1.05, 0.04), accent.lightened(0.15))


## What makes each home its owner's: placed on the free side of the room
## by the door, clear of the entrance.
func _add_belongings(m: MeshBuilder, kit, props: String, f: float) -> void:
	var w := ROOM_SIZE.x
	var d := ROOM_SIZE.y
	var spot := Vector3(f * 3.3, 0, 1.9)
	match props:
		"plans":  # a drawing table and rolled plans
			m.add_box_at(spot + Vector3(0, 0.95, 0), Vector3(1.2, 0.05, 0.8), BuildingFactory.WOOD, 0.2)
			m.add_box_at(spot + Vector3(0, 0.97, 0), Vector3(0.9, 0.01, 0.6), Color(0.93, 0.9, 0.8), 0.2)
			m.add_box_at(spot + Vector3(0, 0.47, 0), Vector3(0.12, 0.95, 0.12), BuildingFactory.WOOD_DARK)
			for i in 3:
				m.add_cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), spot + Vector3(0.1, 1.02 + i * 0.05, 0.3)), 0.04, 0.04, 0.55, 6, Color(0.9, 0.85, 0.7))
			kit.box_collider(spot + Vector3(0, 0.5, 0), Vector3(1.2, 1.0, 0.8))
		"seeds":  # sacks of seed and a basket of vegetables
			for i in 3:
				m.add_blob_at(Vector3(f * (w * 0.5 - 0.5), 0.35, 1.2 + i * 0.65), Vector3(0.35, 0.4, 0.3), Color(0.78, 0.68, 0.48), 7, 4, 0.12)
			kit.box_collider(Vector3(f * (w * 0.5 - 0.5), 0.4, 1.85), Vector3(0.8, 0.8, 2.0))
			m.add_cylinder_at(spot + Vector3(-f * 0.6, 0, 0), 0.32, 0.38, 0.35, 10, Color(0.6, 0.45, 0.25))
			for i in 5:
				m.add_blob_at(spot + Vector3(-f * 0.6 + (i % 3) * 0.12 - 0.12, 0.4, (i / 3) * 0.12), Vector3(0.09, 0.09, 0.09),
					[Color(0.9, 0.5, 0.15), Color(0.45, 0.7, 0.3), Color(0.8, 0.2, 0.2)][i % 3], 6, 4, 0.0)
		"herbs":  # bundles drying under the beams, pots of plants
			for i in 7:
				var x := -3.0 + i * 1.0
				m.add_box_at(Vector3(x, WALL_HEIGHT - 0.5, -1.6), Vector3(0.02, 0.5, 0.02), Color(0.6, 0.55, 0.4))
				m.add_blob_at(Vector3(x, WALL_HEIGHT - 0.85, -1.6), Vector3(0.13, 0.25, 0.13), Color(0.4, 0.6, 0.3).lightened(0.05 * (i % 3)), 6, 4, 0.2)
			for i in 3:
				var pot := spot + Vector3(f * (i - 1) * 0.55, 0, 0.4)
				m.add_cylinder_at(pot, 0.17, 0.2, 0.3, 8, Color(0.72, 0.4, 0.28))
				m.add_blob_at(pot + Vector3(0, 0.45, 0), Vector3(0.22, 0.25, 0.22), Color(0.35, 0.6, 0.3), 7, 4, 0.2)
			kit.box_collider(spot + Vector3(0, 0.3, 0.4), Vector3(1.6, 0.6, 0.5))
		"workbench":  # a bench with tools and a half-made chair
			m.add_box_at(spot + Vector3(0, 0.85, 0), Vector3(1.8, 0.1, 0.7), BuildingFactory.WOOD)
			for lx in [-0.8, 0.8]:
				m.add_box_at(spot + Vector3(lx, 0.42, 0), Vector3(0.1, 0.84, 0.6), BuildingFactory.WOOD_DARK)
			m.add_box_at(spot + Vector3(-0.4, 0.95, 0), Vector3(0.35, 0.06, 0.1), Color(0.6, 0.62, 0.66))
			m.add_box_at(spot + Vector3(0.3, 0.93, 0.1), Vector3(0.5, 0.04, 0.12), Color(0.85, 0.7, 0.5))
			kit.box_collider(spot + Vector3(0, 0.45, 0), Vector3(1.8, 0.9, 0.7))
		"trade":  # crates, bolts of cloth
			for i in 3:
				var crate := Vector3(f * (w * 0.5 - 0.55), 0.3 + (0.6 if i == 2 else 0.0), 1.5 + (i % 2) * 0.7)
				m.add_box_at(crate, Vector3(0.6, 0.6, 0.6), BuildingFactory.WOOD.lightened(0.1))
			kit.box_collider(Vector3(f * (w * 0.5 - 0.55), 0.6, 1.85), Vector3(0.7, 1.2, 1.4))
			for i in 3:
				m.add_cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), spot + Vector3(-f * 0.5, 0.15 + i * 0.22, 0.2)), 0.11, 0.11, 0.9, 8,
					[Color(0.75, 0.25, 0.3), Color(0.25, 0.45, 0.7), Color(0.85, 0.7, 0.25)][i])
			kit.box_collider(spot + Vector3(-f * 0.5, 0.35, 0.2), Vector3(0.9, 0.7, 0.3))
		_:  # a cosy bench and a basket of wool
			m.add_box_at(spot + Vector3(0, 0.42, 0), Vector3(1.4, 0.08, 0.5), BuildingFactory.WOOD)
			for lx in [-0.6, 0.6]:
				m.add_box_at(spot + Vector3(lx, 0.2, 0), Vector3(0.08, 0.4, 0.45), BuildingFactory.WOOD_DARK)
			m.add_box_at(spot + Vector3(0.2, 0.5, 0), Vector3(0.45, 0.1, 0.4), Color(0.75, 0.4, 0.35))
			m.add_cylinder_at(spot + Vector3(-f * 1.0, 0, 0.1), 0.22, 0.26, 0.28, 9, Color(0.62, 0.48, 0.3))
			m.add_blob_at(spot + Vector3(-f * 1.0, 0.32, 0.1), Vector3(0.12, 0.1, 0.12), Color(0.85, 0.85, 0.95), 6, 3, 0.1)
			kit.box_collider(spot + Vector3(0, 0.25, 0), Vector3(1.4, 0.5, 0.5))


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
	return "Sleep until morning" if PlayerController.is_night() else "Your bed  (sleep at night, or have a nap)"


## Lies down on the mattress, then sleeps (to morning at night, a two-hour
## nap by day) and gets up standing beside the bed.
func _sleep(actor) -> void:
	if actor == null or _busy or _room == null:
		return
	var bed_holder := _room.find_child("Bed", false, false) as Node3D
	var f := float(home_config(current)["flip"])
	var mattress := ROOM_ORIGIN + Vector3(f * 3.3, 0, -ROOM_SIZE.y * 0.5 + 1.35)
	_busy = true
	actor.stand_up()
	actor._action_time = 0.0
	actor.velocity = Vector3.ZERO
	actor.global_position = mattress + Vector3(0, 0.0, 0.25)
	actor.model.rotation = Vector3(0, PI, 0)
	actor.model.position = Vector3(0, 0.52, 0)
	actor.pose = &"sleep"
	actor._pose_time = -1000.0  # the bed decides when you wake, not the timer
	actor._slept = true
	actor.model.set_animation(&"sleep")
	await get_tree().create_timer(1.0).timeout
	await _fade_to(1.0)
	if PlayerController.is_night():
		actor.sleep_until_morning(true)
	else:
		WorldClock.advance(2.0)
		GameManager.notify("You have a short nap. Two hours pass and you feel rested.")
	if actor.get("combat") and actor.combat:
		actor.combat.heal_full()
	var beside := bed_holder.global_position if bed_holder else ROOM_ORIGIN + SPAWN
	_place_player_standing(Vector3(beside.x, ROOM_ORIGIN.y + 0.05, beside.z), PI * 0.5 * -f)
	await _fade_to(0.0)
	_busy = false


## Lying down indoors: in your own house that means going to bed; in someone
## else's home you don't lie on their floor.
func lie_down_indoors(actor) -> void:
	if current == "player":
		_sleep(actor)
	else:
		GameManager.notify("You can't lie down in someone else's home. Your own bed is in your house.")


func _open_chest(_actor) -> void:
	var parts := PackedStringArray()
	for resource in GameState.RESOURCES:
		parts.append("%s %d" % [GameState.RESOURCE_NAMES[resource], GameState.count(resource)])
	parts.append("stews %d" % stews())
	GameManager.notify("In your chest and the village stores: " + ", ".join(parts))


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
