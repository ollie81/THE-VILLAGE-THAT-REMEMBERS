class_name MonsterSpawner
extends Node3D
## Brings the wild to life around the player, and only there: when you're
## out of the village, monsters suited to the place and the hour appear a
## little way off (never in sight of the village, never more than a handful
## at once) and are removed once you've moved on. The dragon keeps a lair in
## the wilds and shows itself there every few days.
## Saved: when the dragon was last driven off.

static var instance: MonsterSpawner

const SCAN_INTERVAL := 2.0
## At most this many monsters about at once (fewer on Low quality).
const MAX_ACTIVE := 6
const MAX_ACTIVE_LOW := 4
const SPAWN_MIN := 24.0
const SPAWN_MAX := 40.0
const DESPAWN_DISTANCE := 70.0
## How many each zone keeps about you (before the cap).
const WANTED := {MonsterZones.FOREST: 3, MonsterZones.WILDS: 4}
const NIGHT_EXTRA := 1
## Where the dragon lives, how close you must come, and how often it returns.
const DRAGON_LAIR := Vector3(124.0, 0.0, 52.0)
const DRAGON_RANGE := 48.0
const DRAGON_DAYS := 3

var dragon_beaten_day: int = -100
var dragon_seen: bool = false
var _scan: float = 0.5
var _dragon: Monster = null
var _rng := RandomNumberGenerator.new()
var _last_zone: int = MonsterZones.SAFE
var _warned_at: float = -999.0


func _ready() -> void:
	name = "MonsterSpawner"
	instance = self
	_rng.randomize()


func _exit_tree() -> void:
	if instance == self:
		instance = null


func cap() -> int:
	return MAX_ACTIVE_LOW if GameSettings.quality_name() == "Low" else MAX_ACTIVE


func active() -> Array:
	return get_children().filter(func(m): return m is Monster and m.is_alive())


static func is_night() -> bool:
	return WorldClock.time_of_day >= 20.0 or WorldClock.time_of_day < 5.5


func _process(delta: float) -> void:
	_scan -= delta
	if _scan > 0.0:
		return
	_scan = SCAN_INTERVAL
	var player = GameManager.player
	if player == null:
		return
	var p: Vector3 = player.global_position
	var zone := MonsterZones.zone_at(p.x, p.z)
	_announce(zone)
	# Tidy up: far away, or left behind when you went home.
	for m in active():
		var d: float = (m.global_position - p).length()
		if d > DESPAWN_DISTANCE or (zone == MonsterZones.SAFE and d > 40.0 and m != _dragon):
			m.queue_free()
	_update_dragon(p)
	var indoors := Interiors.instance != null and Interiors.instance.is_inside()
	if zone == MonsterZones.SAFE or indoors:
		return
	var wanted: int = int(WANTED.get(zone, 0)) + (NIGHT_EXTRA if is_night() else 0)
	var count := active().size()
	if count >= mini(wanted, cap()):
		return
	var kind := pick_kind(zone, is_night(), _rng)
	var group := 1
	if kind == &"slime":
		group = _rng.randi_range(1, 3)
	elif kind == &"bat" or kind == &"wolf":
		group = _rng.randi_range(1, 2)
	group = mini(group, cap() - count)
	var at := spawn_point(p, zone)
	if at == Vector3.INF:
		return
	for i in group:
		var offset := Vector3(_rng.randf_range(-2.5, 2.5), 0, _rng.randf_range(-2.5, 2.5))
		spawn(kind, at + offset)


## Which monster turns up in a zone at this hour.
static func pick_kind(zone: int, night: bool, rng: RandomNumberGenerator) -> StringName:
	var roll := rng.randf()
	if night:
		if roll < 0.65:
			return &"skeleton"
		return &"bat" if zone == MonsterZones.FOREST or roll < 0.82 else &"wolf"
	if zone == MonsterZones.WILDS:
		return &"wolf" if roll < 0.6 else &"bat"
	return &"slime" if roll < 0.6 else &"bat"


## A spot a little way off in the same kind of danger, dry, open and not too
## steep, or INF.
func spawn_point(p: Vector3, zone: int) -> Vector3:
	for attempt in 10:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(SPAWN_MIN, SPAWN_MAX)
		var at := Vector3(p.x + cos(a) * r, 0, p.z + sin(a) * r)
		if MonsterZones.zone_at(at.x, at.z) == MonsterZones.SAFE:
			continue
		if VillageLayout.is_water_area(at.x, at.z, 2.0):
			continue
		if maxf(absf(at.x), absf(at.z)) > VillageLayout.MOUNTAINS_FROM - 4.0:
			continue
		if VillageLayout.blocking_reason(at.x, at.z, 1.0, 0.0) != "":
			continue
		at.y = TerrainGenerator.get_height(at.x, at.z) + 0.3
		return at
	return Vector3.INF


func spawn(kind: StringName, at: Vector3) -> Monster:
	var m := Monster.create(kind, at)
	add_child(m)
	return m


# --- The dragon -------------------------------------------------------------------------

func dragon_due() -> bool:
	return WorldClock.day - dragon_beaten_day >= DRAGON_DAYS


func _update_dragon(p: Vector3) -> void:
	var near := Vector2(p.x - DRAGON_LAIR.x, p.z - DRAGON_LAIR.z).length() < DRAGON_RANGE
	if _dragon and not is_instance_valid(_dragon):
		_dragon = null
	if near and _dragon == null and dragon_due():
		var at := DRAGON_LAIR
		at.y = TerrainGenerator.get_height(at.x, at.z) + 0.5
		_dragon = spawn(&"dragon", at)
		_dragon.defeated.connect(func(_m):
			dragon_beaten_day = WorldClock.day
			SaveService.save_game())
		if not dragon_seen:
			dragon_seen = true
			GameManager.notify("A dragon! Its lair is here in the wilds. Block its bite, dodge, and strike while it recovers.")
	elif _dragon and not near and Vector2(p.x - DRAGON_LAIR.x, p.z - DRAGON_LAIR.z).length() > DRAGON_RANGE + 30.0:
		_dragon.queue_free()
		_dragon = null


## Tells you when you step out into danger (at most once a minute).
func _announce(zone: int) -> void:
	if zone == _last_zone:
		return
	var was := _last_zone
	_last_zone = zone
	var now := Time.get_ticks_msec() / 1000.0
	if now - _warned_at < 60.0 or zone < was:
		return
	_warned_at = now
	var armed := PlayerCombat.is_armed()
	match zone:
		MonsterZones.FOREST:
			GameManager.notify("You're leaving the village. Slimes and bats roam the forest%s." % ("" if armed else "; they keep their distance from someone without a sword"))
		MonsterZones.WILDS:
			GameManager.notify("The wilds: wolves hunt here, and something bigger lives further in.%s" % ("" if armed else " Best not come unarmed."))


# --- Save ---------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"dragon_beaten_day": dragon_beaten_day, "dragon_seen": dragon_seen}


func from_dict(data: Dictionary) -> void:
	dragon_beaten_day = int(data.get("dragon_beaten_day", -100))
	dragon_seen = bool(data.get("dragon_seen", false))
