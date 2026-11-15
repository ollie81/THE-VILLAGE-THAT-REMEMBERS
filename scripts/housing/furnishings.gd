class_name Furnishings
extends Node3D
## All the furniture and decorations the player owns, as saved records in
## GameState.furniture, and their bodies in the world: outdoor pieces stand in
## the village all the time; a house's pieces are made when you go inside
## (with its rooms) and go when you leave, so they cost nothing meanwhile.
##
## Places: "outside" (world position), "stored" (put away, to place again),
## or a house's interior id ("house_<uid>", or "player" for your home before
## you've built one), with positions in that house's room space.

static var instance: Furnishings

## Space kept between furniture and the inside of a wall.
const WALL_GAP := 0.12
## Pieces bumping into each other: how much overlap is tolerated.
const SNAP := 0.25


func _ready() -> void:
	name = "Furnishings"
	instance = self
	for record in GameState.furniture:
		if String(record.get("place", "")) == "outside":
			_spawn_outdoor(record)
	if StructureManager.instance:
		StructureManager.instance.structure_removed.connect(_on_structure_removed)


func _exit_tree() -> void:
	if instance == self:
		instance = null


# --- Records ------------------------------------------------------------------------------

static func records_in(place: String) -> Array:
	return GameState.furniture.filter(func(r): return String(r.get("place", "")) == place)


static func stored() -> Array:
	return records_in("stored")


static func next_id() -> int:
	var top := 0
	for r in GameState.furniture:
		top = maxi(top, int(r.get("id", 0)))
	return top + 1


## A house's interior id from its structure record.
static func place_of(structure: Dictionary) -> String:
	return "house_%d" % int(structure["uid"])


## The structure record behind a house interior id ({} for "player" with no
## house yet).
static func house_of(place: String) -> Dictionary:
	if place.begins_with("house_"):
		var uid := int(place.substr(6))
		for s in GameState.structures:
			if int(s.get("uid", -1)) == uid:
				return s
	return {}


static func house_type(place: String) -> StringName:
	var s := house_of(place)
	return StringName(String(s["type"])) if not s.is_empty() else &"house"


## Your own places: outdoors, your stored things, and houses you haven't
## given away.
func is_players_place(place: String) -> bool:
	if place == "outside" or place == "stored" or place == "player":
		return true
	var s := house_of(place)
	return not s.is_empty() and String(s.get("owner", "player")) == "player"


static func stored_total(record: Dictionary) -> int:
	var total := 0
	var storage: Dictionary = record.get("storage", {})
	for k in storage:
		total += int(storage[k])
	return total


# --- Placing --------------------------------------------------------------------------------

## Why `type` can't stand at `at` (room space indoors, world outside) turned
## by `yaw` in `place`, or "". `ignore` is the record being moved.
func can_place(type: StringName, place: String, at: Vector3, yaw: float, ignore: Dictionary = {}) -> String:
	var info := FurnitureCatalog.info(type)
	if info.is_empty():
		return "Unknown furniture"
	var size := FurnitureCatalog.footprint(type, yaw)
	var rect := Rect2(Vector2(at.x, at.z) - size * 0.5, size)
	var flat := bool(info.get("flat", false))
	if place == "outside":
		if not bool(info.get("outdoor", false)):
			return "%s belongs indoors" % info["name"]
		var radius := size.length() * 0.5
		var blocked := VillageLayout.blocking_reason(at.x, at.z, radius, 0.0)
		if blocked == "":
			blocked = VillageDecor.blocking_reason(at, radius)
		if blocked == "":
			blocked = KitCottage.blocking_reason(at, radius)
		if blocked != "":
			return blocked
		for structure in get_tree().get_nodes_in_group("placed_structures"):
			var other: float = StructureCatalog.radius(structure.get_type())
			if Vector2(at.x - structure.global_position.x, at.z - structure.global_position.z).length() < radius + other * 0.85:
				return "Too close to your %s" % String(structure.get_info()["name"]).to_lower()
	else:
		var house := house_type(place)
		var inside := false
		for r in HouseInterior.layout(house)["rooms"]:
			if (r[1] as Rect2).grow(-WALL_GAP).encloses(rect):
				inside = true
				break
		if not inside:
			return "It doesn't fit there (keep it inside one room)"
		if not flat:
			for b in HouseInterior.blocked(house):
				if (b as Rect2).intersects(rect.grow(-0.02)):
					return "That's in the way of a wall, a doorway or the hearth"
	if flat:
		return ""
	for r in records_in(place):
		if r == ignore or bool(FurnitureCatalog.info(StringName(String(r["type"]))).get("flat", false)):
			continue
		var p: Array = r["pos"]
		var other_size := FurnitureCatalog.footprint(StringName(String(r["type"])), float(r.get("yaw", 0.0)))
		var other := Rect2(Vector2(float(p[0]), float(p[2])) - other_size * 0.5, other_size)
		if other.intersects(rect.grow(-0.04)):
			return "Something else is already there"
	return ""


## The nearest spot (a spiral search) where `type` fits, or INF.
func free_spot(type: StringName, place: String, near: Vector3, yaw: float, ignore: Dictionary = {}, rings: int = 40) -> Vector3:
	if can_place(type, place, near, yaw, ignore) == "":
		return near
	for ring in range(1, rings):
		var r := ring * 0.25
		var steps := maxi(8, ring * 6)
		for i in steps:
			var a := TAU * i / steps
			var at := Vector3(snappedf(near.x + cos(a) * r, 0.05), near.y, snappedf(near.z + sin(a) * r, 0.05))
			if can_place(type, place, at, yaw, ignore) == "":
				return at
	return Vector3.INF


## Adds a new piece. Returns its record.
func add(type: StringName, place: String, at: Vector3, yaw: float) -> Dictionary:
	var record := {"id": next_id(), "type": String(type), "place": place, "pos": [at.x, at.y, at.z], "yaw": yaw, "storage": {}}
	if type == &"lamp":
		record["on"] = true
	GameState.furniture.append(record)
	if place == "outside":
		_spawn_outdoor(record)
	elif Interiors.instance and Interiors.instance.current == place and Interiors.instance._room:
		_spawn_in(Interiors.instance._room, record)
	return record


## Moves a piece (its body follows).
func move(record: Dictionary, place: String, at: Vector3, yaw: float) -> void:
	_despawn(record)
	record["place"] = place
	record["pos"] = [at.x, at.y, at.z]
	record["yaw"] = yaw
	if place == "outside":
		_spawn_outdoor(record)
	elif Interiors.instance and Interiors.instance.current == place and Interiors.instance._room:
		_spawn_in(Interiors.instance._room, record)


## Puts a piece away: it keeps what's stored in it and can be placed again.
func put_away(record: Dictionary) -> void:
	_despawn(record)
	record["place"] = "stored"


func body_of(record: Dictionary) -> FurniturePiece:
	for piece in get_tree().get_nodes_in_group("furniture"):
		if piece.record == record and not piece.is_queued_for_deletion():
			return piece
	return null


func _despawn(record: Dictionary) -> void:
	var piece := body_of(record)
	if piece:
		piece.get_parent().remove_child(piece)
		piece.queue_free()


func _spawn_outdoor(record: Dictionary) -> FurniturePiece:
	var piece := FurniturePiece.new().setup(record)
	var p: Array = record["pos"]
	piece.position = VillageLayout.ground_point(float(p[0]), float(p[2]))
	piece.rotation.y = float(record.get("yaw", 0.0))
	add_child(piece)
	return piece


func _spawn_in(room: Node3D, record: Dictionary) -> FurniturePiece:
	var piece := FurniturePiece.new().setup(record)
	var p: Array = record["pos"]
	piece.position = Vector3(float(p[0]), 0.0, float(p[2]))
	piece.rotation.y = float(record.get("yaw", 0.0))
	room.add_child(piece)
	return piece


# --- A house's furniture --------------------------------------------------------------------

## Fills a house's rooms with its furniture (giving a new house its starter
## pieces first). Anything that no longer fits (a wall built through it by an
## upgrade) moves to the nearest free floor, or is put away.
func populate(room: Node3D, place: String) -> void:
	var flag := StringName("furnished_" + place)
	if not GameState.get_flag(flag):
		GameState.set_flag(flag, true)
		for s in FurnitureCatalog.STARTER:
			var at := Vector3(float(s[1]), 0, float(s[2]))
			var spot := free_spot(s[0], place, at, float(s[3]))
			if spot != Vector3.INF:
				var record := {"id": next_id(), "type": String(s[0]), "place": place, "pos": [spot.x, 0.0, spot.z], "yaw": float(s[3]), "storage": {}}
				if s[0] == &"lamp":
					record["on"] = true
				GameState.furniture.append(record)
	var moved := 0
	for record in records_in(place):
		var p: Array = record["pos"]
		var at := Vector3(float(p[0]), 0, float(p[2]))
		var type := StringName(String(record["type"]))
		var yaw := float(record.get("yaw", 0.0))
		if can_place(type, place, at, yaw, record) != "":
			var spot := free_spot(type, place, at, yaw, record)
			if spot == Vector3.INF:
				record["place"] = "stored"
				moved += 1
				continue
			record["pos"] = [spot.x, 0.0, spot.z]
			moved += 1
		_spawn_in(room, record)
	if moved > 0:
		GameManager.notify("Some furniture was moved so it isn't in a wall's way. Tap Arrange to put it where you like.")


func _on_structure_removed(structure) -> void:
	if structure == null or not HouseDesigns.is_house(structure.get_type()):
		return
	var place := place_of(structure.record)
	var count := 0
	for r in records_in(place):
		r["place"] = "stored"
		count += 1
	if count > 0:
		GameManager.notify("The %d piece%s of furniture from that house were put away. Place them again from Build > Furniture." % [count, "" if count == 1 else "s"])


# --- Storage --------------------------------------------------------------------------------

## Moves up to `amount` of `resource` from the village stores into a chest.
## Returns how many went in.
func deposit(record: Dictionary, resource: StringName, amount: int) -> int:
	var holds := int(FurnitureCatalog.info(StringName(String(record["type"]))).get("holds", 0))
	var n := mini(mini(amount, GameState.count(resource)), holds - stored_total(record))
	if n <= 0:
		return 0
	GameState.add(resource, -n)
	var storage: Dictionary = record.get("storage", {})
	storage[String(resource)] = int(storage.get(String(resource), 0)) + n
	record["storage"] = storage
	return n


## Takes up to `amount` of `resource` out of a chest into the village stores.
func withdraw(record: Dictionary, resource: StringName, amount: int) -> int:
	var storage: Dictionary = record.get("storage", {})
	var n := mini(amount, int(storage.get(String(resource), 0)))
	if n <= 0:
		return 0
	storage[String(resource)] = int(storage[String(resource)]) - n
	if int(storage[String(resource)]) == 0:
		storage.erase(String(resource))
	record["storage"] = storage
	GameState.add(resource, n)
	return n
