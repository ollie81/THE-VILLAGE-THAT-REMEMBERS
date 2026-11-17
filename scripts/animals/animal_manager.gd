class_name AnimalManager
extends Node
## Every animal in the world, as saved records: the village's own (cows,
## sheep, pigs and horses on the farmland, dogs and cats by the homes) and
## the ones the player buys. An animal's 3D body only exists while the player
## is near it (spawned and removed by distance), so the world can hold many
## animals while only a handful think at once.
##
## Animals are never made by buildings: a pen or a stable only gives bought
## animals somewhere to live. Each record has a unique id, so nothing spawns
## twice.

signal changed

static var instance: AnimalManager

const SPAWN_DISTANCE := 85.0
const DESPAWN_DISTANCE := 100.0
const SCAN_INTERVAL := 0.5

## The village's own animals, created once per world: [species, home, name].
const VILLAGE_ANIMALS := [
	["cow", "pasture", "Daisy"], ["cow", "pasture", "Bluebell"], ["cow", "pasture", "Nutmeg"],
	["sheep", "sheepfold", "Cotton"], ["sheep", "sheepfold", "Nimbus"], ["sheep", "sheepfold", "Woolly"], ["sheep", "sheepfold", "Pebble"],
	["pig", "sty", "Truffle"], ["pig", "sty", "Acorn"],
	["horse", "paddock", "Juniper"], ["horse", "paddock", "Ember"],
	["dog", "door:tomas", "Rufus"], ["cat", "door:mara", "Misty"], ["dog", "street", "Scout"], ["cat", "street", "Ginger"],
]
## Village homes: centre and radius of the area they keep to.
const VILLAGE_HOMES := {
	"pasture": [Vector3(-12.0, 0.0, -112.0), 9.0],
	"sheepfold": [Vector3(6.0, 0.0, -152.0), 8.0],
	"sty": [Vector3(-86.0, 0.0, -112.0), 5.0],
	"paddock": [Vector3(6.0, 0.0, -126.0), 7.0],
	"street": [Vector3(-2.0, 0.0, 110.0), 9.0],
}

var records: Array[Dictionary] = []
var next_id: int = 1
var village_seeded: bool = false
var _nodes: Dictionary = {}  # id -> Animal
var _scan: float = 0.0


func _ready() -> void:
	name = "AnimalManager"
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _process(delta: float) -> void:
	_scan -= delta
	if _scan > 0.0:
		return
	_scan = SCAN_INTERVAL
	var player = GameManager.player
	if player == null:
		return
	var at: Vector3 = player.global_position
	for record in records:
		var id := String(record["id"])
		var p := record_position(record)
		var d := Vector2(p.x - at.x, p.z - at.z).length()
		var spawned: Animal = _nodes.get(id)
		if spawned == null and (d < SPAWN_DISTANCE or bool(record.get("follow", false))):
			_spawn(record)
		elif spawned and d > DESPAWN_DISTANCE and not bool(record.get("follow", false)):
			_despawn(id)


func record_position(record: Dictionary) -> Vector3:
	var pos: Array = record.get("pos", [])
	if pos.size() == 3:
		return Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	return home_area(record)["center"]


func _spawn(record: Dictionary) -> Animal:
	var animal := Animal.new()
	animal.setup(record)
	var p := record_position(record)
	animal.position = Vector3(p.x, VillageLayout.get_walk_height(p.x, p.z), p.z)
	add_child(animal)
	_nodes[String(record["id"])] = animal
	return animal


func _despawn(id: String) -> void:
	var animal: Animal = _nodes.get(id)
	if animal and is_instance_valid(animal):
		animal.queue_free()
	_nodes.erase(id)


## The body of the animal with this id, if it's near enough to exist.
func node_of(id: String) -> Animal:
	var a: Animal = _nodes.get(id)
	return a if a and is_instance_valid(a) else null


func spawned_count() -> int:
	return _nodes.size()


# --- Homes ----------------------------------------------------------------------------------

## Where an animal keeps to: {center, radius}.
func home_area(record: Dictionary) -> Dictionary:
	var home := String(record.get("home", "house"))
	if VILLAGE_HOMES.has(home):
		return {"center": VILLAGE_HOMES[home][0], "radius": float(VILLAGE_HOMES[home][1])}
	if home.begins_with("door:"):
		var door: Vector3 = VillageLayout.get_nav_nodes().get("door_" + home.substr(5), Vector3.ZERO)
		return {"center": door + Vector3(0, 0, 2.0), "radius": 4.0}
	if home.begins_with("pen:") or home.begins_with("stable:"):
		var s := _structure(int(home.get_slice(":", 1)))
		if not s.is_empty():
			var at: Array = s["position"]
			var c := Vector3(float(at[0]), 0, float(at[2]))
			if home.begins_with("stable:"):
				c += Basis(Vector3.UP, float(s.get("yaw", 0.0))) * Vector3(0, 0, 1.8)
				return {"center": c, "radius": 2.4}
			return {"center": c, "radius": 3.2}
	# The player's home, or by the meeting circle until there is one.
	for s in GameState.structures:
		if String(s.get("type", "")) == "house" and bool(s.get("complete", false)):
			var at: Array = s["position"]
			var c := Vector3(float(at[0]), 0, float(at[2])) + Basis(Vector3.UP, float(s.get("yaw", 0.0))) * Vector3(0, 0, 4.5)
			return {"center": c, "radius": 5.0}
	return {"center": Vector3(3.0, 0.0, 11.0), "radius": 5.0}


func _structure(uid: int) -> Dictionary:
	for s in GameState.structures:
		if int(s.get("uid", -1)) == uid:
			return s
	return {}


func residents(home: String) -> int:
	return records.filter(func(r): return String(r.get("home", "")) == home).size()


## A home with room for `species`, as a home string ("pen:12"), or "".
func free_home(species: StringName) -> String:
	var kind := String(AnimalSpecies.info(species).get("home", "house"))
	if kind == "house":
		var pets := records.filter(func(r): return String(r.get("owner", "")) == "player" and String(r.get("home", "")) == "house").size()
		return "house" if pets < int(AnimalSpecies.CAPACITY["house"]) else ""
	var type := "animal_pen" if kind == "pen" else "stable"
	for s in GameState.structures:
		if String(s.get("type", "")) == type and bool(s.get("complete", false)):
			var home := "%s:%d" % [kind, int(s["uid"])]
			if residents(home) < int(AnimalSpecies.CAPACITY[kind]):
				return home
	return ""


## Why `species` can't be bought now, or "".
func cannot_buy(species: StringName) -> String:
	var info := AnimalSpecies.info(species)
	if info.is_empty():
		return "Unknown animal"
	if free_home(species) == "":
		var kind := String(info["home"])
		if kind == "house":
			return "Your home already has %d pets" % int(AnimalSpecies.CAPACITY["house"])
		return "Build %s with room first" % AnimalSpecies.home_label(kind)
	var credits := VillageCredits.instance
	if credits == null or not credits.can_afford(int(info["price"])):
		return "Needs %d credits" % int(info["price"])
	return ""


## Buys one animal: pays, gives it a home and a name, and it appears there.
## Returns its record, or {} with a notice if it can't.
func buy(species: StringName) -> Dictionary:
	var reason := cannot_buy(species)
	if reason != "":
		GameManager.notify(reason + ".")
		return {}
	var info := AnimalSpecies.info(species)
	VillageCredits.instance.spend(int(info["price"]))
	var names: Array = info["names"]
	var owned := records.filter(func(r): return String(r.get("species", "")) == String(species) and String(r.get("owner", "")) == "player").size()
	var record := _new_record(species, free_home(species), String(names[owned % names.size()]), "player")
	GameManager.notify("%s the %s is yours! They live at %s." % [record["name"], String(info["name"]).to_lower(), _home_text(String(record["home"]))])
	Sounds.play("built", null, -6.0)
	changed.emit()
	return record


func _home_text(home: String) -> String:
	if home.begins_with("pen:"):
		return "your animal pen"
	if home.begins_with("stable:"):
		return "your stable"
	return "your home"


func _new_record(species: StringName, home: String, animal_name: String, owner: String) -> Dictionary:
	var record := {"id": "a%d" % next_id, "species": String(species), "home": home, "name": animal_name, "owner": owner,
		"fed_day": -1, "milked_day": -1, "follow": false, "since_day": WorldClock.day}
	next_id += 1
	var area := home_area(record)
	var c: Vector3 = area["center"]
	var a := randf() * TAU
	var r := randf() * float(area["radius"]) * 0.6
	record["pos"] = [c.x + cos(a) * r, 0.0, c.z + sin(a) * r]
	records.append(record)
	return record


func owned() -> Array:
	return records.filter(func(r): return String(r.get("owner", "")) == "player")


func _seed_village() -> void:
	for entry in VILLAGE_ANIMALS:
		_new_record(StringName(String(entry[0])), String(entry[1]), String(entry[2]), "village")
	village_seeded = true


# --- Save -----------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"records": records.duplicate(true), "next_id": next_id, "village_seeded": village_seeded}


func from_dict(data: Dictionary) -> void:
	for id in _nodes.keys():
		_despawn(String(id))
	records.clear()
	var saved: Array = data.get("records", []) if data.get("records", []) is Array else []
	var seen := {}
	for r in saved:
		if r is Dictionary and not seen.has(String(r.get("id", ""))) and AnimalSpecies.SPECIES.has(StringName(String(r.get("species", "")))):
			seen[String(r["id"])] = true
			records.append((r as Dictionary).duplicate(true))
	next_id = int(data.get("next_id", 1))
	for r in records:
		var id := String(r["id"])
		if id.begins_with("a") and id.substr(1).is_valid_int():
			next_id = maxi(next_id, int(id.substr(1)) + 1)
	village_seeded = bool(data.get("village_seeded", false))
	if not village_seeded:
		_seed_village()
	changed.emit()
