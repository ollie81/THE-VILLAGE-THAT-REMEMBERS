class_name CreditRewards
extends Node
## More ways to earn Village Credits by playing (no ads needed):
## - Discoveries: the first visit to each landmark around the valley.
## - Achievements: milestones in building, furnishing, animals, exploring,
##   gathering and coming back.
## - Daily challenges: three small tasks a day (the same three for the whole
##   day, chosen by the date), with a bonus for finishing all three.
##
## Every payout goes through VillageCredits with its own token
## ("discover_windmill", "achievement_builder", "challenge_2026-11-16_wood"),
## so nothing is ever paid twice, and the record of what's been found or
## achieved is the (saved, checksummed) list of paid tokens itself.

signal changed

static var instance: CreditRewards
## Set while resources arrive from a purchase or gift, so buying planks
## doesn't count as gathering them.
static var quiet: bool = false
## Switched off by tests that count credits from other sources exactly (like
## DailyGift.enabled), so a date-dependent challenge can't pay in between.
static var enabled: bool = true

## Landmarks to discover: id, name, where, how close counts as "found".
const PLACES := [
	{"id": "windmill", "name": "the windmill", "at": Vector3(-12.0, 0.0, -138.0), "radius": 16.0},
	{"id": "watchtower", "name": "the watchtower", "at": Vector3(124.0, 0.0, -28.0), "radius": 14.0},
	{"id": "ruins", "name": "the old ruins", "at": Vector3(-150.0, 0.0, -62.0), "radius": 14.0},
	{"id": "lake", "name": "the forest lake", "at": Vector3(-128.0, 0.0, 18.0), "radius": 28.0},
	{"id": "pond", "name": "the pond", "at": Vector3(-34.0, 0.0, 122.0), "radius": 14.0},
	{"id": "fields", "name": "the farmland", "at": Vector3(-55.0, 0.0, -142.0), "radius": 22.0},
	{"id": "lair", "name": "the dragon's lair", "at": Vector3(124.0, 0.0, 52.0), "radius": 18.0},
]

## Achievements: what's measured ("stat"), the target, and the credits.
const ACHIEVEMENTS := [
	{"id": "first_home", "name": "A roof of your own", "text": "Build a house", "stat": "houses", "target": 1, "credits": 10},
	{"id": "builder", "name": "Builder", "text": "Finish 5 buildings", "stat": "buildings", "target": 5, "credits": 15},
	{"id": "master_builder", "name": "Master builder", "text": "Finish 15 buildings", "stat": "buildings", "target": 15, "credits": 30},
	{"id": "homemaker", "name": "Homemaker", "text": "Own 8 pieces of furniture", "stat": "furniture", "target": 8, "credits": 10},
	{"id": "cosy", "name": "Cosy corners", "text": "Own 20 pieces of furniture", "stat": "furniture", "target": 20, "credits": 20},
	{"id": "animal_friend", "name": "Animal friend", "text": "Bring home an animal", "stat": "animals", "target": 1, "credits": 10},
	{"id": "farmyard", "name": "Farmyard", "text": "Look after 5 animals", "stat": "animals", "target": 5, "credits": 20},
	{"id": "explorer", "name": "Explorer", "text": "Discover 3 places", "stat": "places", "target": 3, "credits": 10},
	{"id": "cartographer", "name": "Map maker", "text": "Discover every place", "stat": "places", "target": 7, "credits": 40},
	{"id": "woodcutter", "name": "Woodcutter", "text": "Gather 60 wood", "stat": "wood", "target": 60, "credits": 10},
	{"id": "stonemason", "name": "Stonemason", "text": "Gather 40 stone", "stat": "stone", "target": 40, "credits": 10},
	{"id": "regular", "name": "One of the family", "text": "Visit on 7 different days", "stat": "visits", "target": 7, "credits": 20},
	{"id": "go_getter", "name": "Go-getter", "text": "Finish 6 daily challenges", "stat": "challenges", "target": 6, "credits": 15},
]

## Daily challenge pool; three are chosen each day.
const CHALLENGES := [
	{"id": "wood", "text": "Gather %d wood", "event": "wood", "target": 15},
	{"id": "stone", "text": "Gather %d stone", "event": "stone", "target": 10},
	{"id": "herbs", "text": "Pick %d herbs", "event": "herbs", "target": 4},
	{"id": "talk", "text": "Talk with villagers %d times", "event": "talk", "target": 3},
	{"id": "build", "text": "Finish %d building", "event": "build", "target": 1},
	{"id": "furnish", "text": "Place %d piece of furniture", "event": "furnish", "target": 1},
	{"id": "walk", "text": "Walk to %d landmark", "event": "landmark", "target": 1},
]
const PER_DAY := 3
const CHECK_EVERY := 1.0

## Today's date (UTC) and progress on its challenges: id -> count.
var day: String = ""
var progress: Dictionary = {}
## Lifetime gathering by hand (not bought or given).
var gathered: Dictionary = {}
var _timer: float = 0.0
var _furniture_count: int = -1


func _ready() -> void:
	name = "CreditRewards"
	instance = self
	GameState.inventory_changed.connect(_on_inventory)
	GameManager.conversation_started.connect(func(_v, _c): record("talk"))
	if StructureManager.instance:
		StructureManager.instance.structure_completed.connect(func(_s): record("build"))
	_roll_day()


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _process(delta: float) -> void:
	if not enabled:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = CHECK_EVERY
	_roll_day()
	_check_places()
	_check_furniture()
	check_achievements()


static func _credits() -> VillageCredits:
	return VillageCredits.instance


# --- Discoveries -------------------------------------------------------------------------

func is_discovered(id: String) -> bool:
	return _credits() != null and _credits().paid.has("discover_" + id)


func discovered_count() -> int:
	var n := 0
	for place in PLACES:
		if is_discovered(String(place["id"])):
			n += 1
	return n


func _check_places() -> void:
	var player = GameManager.player
	if player == null or _credits() == null:
		return
	var at: Vector3 = player.global_position
	for place in PLACES:
		var centre: Vector3 = place["at"]
		if Vector2(at.x - centre.x, at.z - centre.z).length() <= float(place["radius"]):
			discover(String(place["id"]))


## Marks a place found (pays the first time). Returns the credits paid.
func discover(id: String) -> int:
	for place in PLACES:
		if String(place["id"]) != id:
			continue
		var paid := VillageCredits.award("discovery", "discover_" + id, "discovering %s" % place["name"])
		if paid > 0:
			record("landmark")
			changed.emit()
		return paid
	return 0


# --- Achievements -------------------------------------------------------------------------

func stat(name_: String) -> int:
	match name_:
		"houses":
			var n := 0
			for type in HouseDesigns.SIZES:
				n += GameState.completed_structures(type)
			return n
		"buildings":
			var n := 0
			for record in GameState.structures:
				if bool(record.get("complete", false)):
					n += 1
			return n
		"furniture":
			return GameState.furniture.size()
		"animals":
			return AnimalManager.instance.owned().size() if AnimalManager.instance else 0
		"places":
			return discovered_count()
		"wood", "stone":
			return int(gathered.get(name_, 0))
		"visits":
			return DailyGift.instance.claims if DailyGift.instance else 0
		"challenges":
			var n := 0
			if _credits():
				for token in _credits().paid:
					if String(token).begins_with("challenge_") and not String(token).ends_with("_all"):
						n += 1
			return n
	return 0


func is_achieved(id: String) -> bool:
	return _credits() != null and _credits().paid.has("achievement_" + id)


func check_achievements() -> void:
	if _credits() == null:
		return
	for a in ACHIEVEMENTS:
		var id := String(a["id"])
		if not is_achieved(id) and stat(String(a["stat"])) >= int(a["target"]):
			if _credits().earn(int(a["credits"]), "achievement_" + id) > 0:
				GameManager.notify("Achievement: %s! +%d Village Credits." % [a["name"], int(a["credits"])])
				Sounds.play("built", null, -6.0)
				changed.emit()


# --- Daily challenges -------------------------------------------------------------------

static func today() -> String:
	# Tests can pin the date to check every set of challenges.
	var pinned := OS.get_environment("VILLAGE_TEST_DATE")
	return pinned if pinned != "" and OS.is_debug_build() else Time.get_date_string_from_system(true)


## The three challenges for `date` (the same all day, different most days).
static func challenges_for(date: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("village-challenges:" + date)
	var pool := CHALLENGES.duplicate()
	var out: Array = []
	for _i in PER_DAY:
		out.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	return out


func todays_challenges() -> Array:
	_roll_day()
	return challenges_for(day)


func challenge_done(id: String) -> bool:
	return _credits() != null and _credits().paid.has("challenge_%s_%s" % [day, id])


func _roll_day() -> void:
	var now := today()
	if now != day:
		day = now
		progress.clear()
		changed.emit()


## Something happened that a challenge might count (`event`, `amount` times).
func record(event: String, amount: int = 1) -> void:
	if not enabled:
		return
	_roll_day()
	for c in challenges_for(day):
		if String(c["event"]) != event:
			continue
		var id := String(c["id"])
		progress[id] = mini(int(progress.get(id, 0)) + amount, int(c["target"]))
		if int(progress[id]) >= int(c["target"]) and not challenge_done(id):
			if VillageCredits.award("challenge", "challenge_%s_%s" % [day, id], "a daily challenge") > 0:
				_check_all_done()
		changed.emit()


func _check_all_done() -> void:
	for c in challenges_for(day):
		if not challenge_done(String(c["id"])):
			return
	VillageCredits.award("challenges_all", "challenge_%s_all" % day, "finishing all of today's challenges")


func _on_inventory(resource: StringName, amount: int, _total: int) -> void:
	if quiet or amount <= 0 or not enabled:
		return
	var key := String(resource)
	if key in ["wood", "stone", "herbs"]:
		gathered[key] = int(gathered.get(key, 0)) + amount
		record(key, amount)


func _check_furniture() -> void:
	var n := GameState.furniture.size()
	if _furniture_count >= 0 and n > _furniture_count:
		record("furnish", n - _furniture_count)
	_furniture_count = n


# --- Save ----------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"day": day, "progress": progress.duplicate(), "gathered": gathered.duplicate()}


func from_dict(data: Dictionary) -> void:
	gathered.clear()
	progress.clear()
	var g = data.get("gathered", {})
	if g is Dictionary:
		for k in g:
			gathered[String(k)] = maxi(int(g[k]), 0)
	day = String(data.get("day", ""))
	var p = data.get("progress", {})
	if day == today() and p is Dictionary:
		for k in p:
			progress[String(k)] = maxi(int(p[k]), 0)
	else:
		day = today()
