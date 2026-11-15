class_name LifeBrain
extends ScheduleBrain
## A villager's days, lived rather than repeated. Their job's timetable is the
## backbone, but each day is shaped by who they are:
## - a farmer works the big fields some mornings and looks after the farm
##   animals some afternoons; fishers go out to the lake or the pond; herbalists
##   walk to the pond for water mint;
## - after work they might go to market, visit a friend at home, walk out to
##   the windmill or the forest lake, or just stroll;
## - in the evening some cook supper (the village cook makes stew for everyone
##   at the meeting circle);
## and moment to moment they react to the world:
## - when it rains, most people shelter at home (the dutiful keep working,
##   the sociable crowd into a friend's house), and they hurry while it pours;
## - when thornlings are out in the woods, nobody goes near them; when there's
##   fighting nearby, people hurry indoors.
## The same person on the same day always makes the same plan (nothing to
## save), and different days differ.

## Chances, before personality nudges them.
const FIELD_MORNING := 0.5
const ANIMAL_AFTERNOON := 0.55
const MARKET := 0.3
const VISIT := 0.35
const WALK_OUT := 0.25
const COOK_SUPPER := 0.4
## How close a place may be to thornlings that are out.
const DANGER_RADIUS := 32.0
## Fighting within this distance sends people indoors.
const FIGHT_RADIUS := 26.0

## The village's farm animals and where villagers stand to tend them.
const ANIMAL_CARE := [
	["pasture", "Feeding the cows at the pasture"],
	["sheepfold", "Checking the sheep at the sheepfold"],
	["sty", "Feeding the pigs at the sty"],
	["paddock", "Brushing the horses in the paddock"],
]
const WALKS := [
	["windmill", "Walking out to the windmill"],
	["lake_shore", "Taking the air by the forest lake"],
	["pond", "Sitting by the pond"],
	["south_street_east", "Visiting the south street"],
]

var person_id: String = ""
var _base: Array = []
var _day: int = -999
## Today's plan as timetable entries (for tests and the People panel).
var plan: Array = []
var _reactions: Dictionary = {}  # cache: reason|original key -> VillagerActivity


func _init(data: VillagerData) -> void:
	super(data)
	person_id = String(data.id)
	_base = data.schedule.duplicate(true)


func choose_activity(villager: Node, hour: float) -> VillagerActivity:
	if WorldClock.day != _day:
		plan_day(WorldClock.day)
	var chosen := super(villager, hour)
	return _react(villager, chosen)


## Builds the timetable for `day` from the job's backbone.
func plan_day(day: int) -> void:
	_day = day
	_reactions.clear()
	plan = _base.duplicate(true)
	var person: Person = Population.get_person(person_id)
	if person != null and person.is_resident() and person.life_stage(day) in [Person.STAGE_ADULT, Person.STAGE_ELDER]:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("%s/%d" % [person_id, day])
		_vary(person, rng)
	_activities.clear()
	for entry in plan:
		_activities.append(VillagerActivity.from_entry(entry))
	_activities.sort_custom(func(a, b): return a.start_hour < b.start_hour)
	if _activities.is_empty():
		_activities.append(VillagerActivity.from_entry({"activity": "wander", "hour": 0.0}))


func _vary(person: Person, rng: RandomNumberGenerator) -> void:
	var job := person.profession
	var open := person.trait_weight("openness")
	var social := person.trait_weight("extraversion")
	var dutiful := person.trait_weight("conscientiousness")
	var morning: Variant = _find(func(e): return e["activity"] == "work" and float(e["hour"]) < 12.0)
	var afternoon: Variant = _find(func(e): return e["activity"] == "work" and float(e["hour"]) >= 12.5 and float(e["hour"]) < 17.0)
	var free: Variant = _find(func(e): return e["activity"] == "wander" and float(e["hour"]) >= 15.0 and float(e["hour"]) < 19.5)
	var evening: Variant = _find(func(e): return e["activity"] in ["socialize", "rest"] and float(e["hour"]) >= 18.5 and float(e["hour"]) < 21.5)
	# Work: the wider world.
	if morning:
		match job:
			"farmer":
				if rng.randf() < FIELD_MORNING:
					_assign(morning, "work", "farmland", "Working the big fields at the farmland", "work")
			"fisher":
				if rng.randf() < 0.45:
					var lake := rng.randf() < 0.5
					_assign(morning, "work", "lake_shore" if lake else "pond", "Fishing at the forest lake" if lake else "Fishing at the pond", "gather")
			"herbalist":
				if rng.randf() < 0.35:
					_assign(morning, "work", "pond", "Picking water mint by the pond", "gather")
	if afternoon:
		if job == "farmer" and rng.randf() < ANIMAL_AFTERNOON:
			var care: Array = ANIMAL_CARE[rng.randi_range(0, ANIMAL_CARE.size() - 1)]
			_assign(afternoon, "work", care[0], care[1], "gather")
		elif job in ["herbalist", "cook"] and rng.randf() < 0.25:
			_assign(afternoon, "work", "pasture", "Bringing scraps to the cows", "gather")
	# Free time: market, a friend, a walk, or a stroll.
	if free:
		var roll := rng.randf()
		var friend := _friend_to_visit(person, rng)
		var market_chance := MARKET + (social - 0.5) * 0.2
		var visit_chance := VISIT * (0.5 + social) if not friend.is_empty() else 0.0
		var walk_chance := WALK_OUT * (0.5 + open)
		if roll < market_chance:
			var market := market_location()
			_assign(free, "trade", market, "Shopping at the market" if market == "market" else "Buying supplies at the storehouse", "talk")
		elif roll < market_chance + visit_chance:
			_assign(free, "visit", String(friend["home"]), "Visiting %s at home" % friend["name"], "")
		elif roll < market_chance + visit_chance + walk_chance:
			var walk: Array = WALKS[rng.randi_range(0, WALKS.size() - 1)]
			_assign(free, "explore", walk[0], walk[1], "idle")
	# Evening: cooking.
	if job == "cook":
		var stew := {"hour": 18.0, "activity": "work", "location": "plaza", "label": "Cooking stew for everyone at the meeting circle", "anim": "work"}
		if evening == null or float(evening["hour"]) > 18.0:
			plan.append(stew)
	elif evening and String(evening["activity"]) == "rest" and rng.randf() < COOK_SUPPER + (dutiful - 0.5) * 0.2:
		_assign(evening, "rest", "home", "Cooking supper at home", "")
	elif evening and rng.randf() < COOK_SUPPER * (1.2 - social):
		# Even sociable people stay in and cook now and then.
		_assign(evening, "rest", "home", "Cooking supper at home", "")


## Replaces today's plan (tests, and scripted moments).
func use_plan(entries: Array) -> void:
	_day = WorldClock.day
	_reactions.clear()
	plan = entries.duplicate(true)
	_activities.clear()
	for entry in plan:
		_activities.append(VillagerActivity.from_entry(entry))


func _find(test: Callable) -> Variant:
	for entry in plan:
		if test.call(entry):
			return entry
	return null


func _assign(entry: Dictionary, activity: String, location: String, label: String, anim: String) -> void:
	entry["activity"] = activity
	entry["location"] = location
	entry["label"] = label
	entry["anim"] = anim


## A friend with a home to visit: {name, home}, or {}.
func _friend_to_visit(person: Person, rng: RandomNumberGenerator) -> Dictionary:
	var options: Array = []
	var me = _villager_of(person_id)
	if me == null:
		return {}
	for other_id in me.mind.relationships:
		if String(other_id) == GameManager.PLAYER_ID or me.mind.get_affection(String(other_id)) < SocialLife.FRIEND_AFFECTION:
			continue
		var other: Person = Population.get_person(String(other_id))
		if other and other.is_resident() and other.home != "" and other.home != person.home \
				and other.home != Population.CAMP_ID and VillageLayout.get_locations().has(other.home):
			options.append({"name": other.first_name, "home": other.home})
	if options.is_empty():
		return {}
	return options[rng.randi_range(0, options.size() - 1)]


static func _villager_of(id: String) -> Node:
	for v in GameManager.villagers:
		if is_instance_valid(v) and String(v.data.id) == id:
			return v
	return null


## Where the market is: the player's market stalls once there are any,
## otherwise the storehouse.
static func market_location() -> String:
	var spots: Array = []
	var looks: Array = []
	for s in GameState.structures:
		if String(s.get("type", "")) == "market_stall" and bool(s.get("complete", false)):
			var at: Array = s["position"]
			var origin := Vector3(float(at[0]), 0.0, float(at[2]))
			var basis := Basis(Vector3.UP, float(s.get("yaw", 0.0)))
			for x: float in [-0.8, 0.8]:
				spots.append(origin + basis * Vector3(x, 0, 1.9))
				looks.append(origin + basis * Vector3(x, 0, 0.5))
	if spots.is_empty():
		if VillageLayout.get_locations().has("market"):
			VillageLayout.unregister_location("market")
		return "storage"
	VillageLayout.register_location("market", spots, looks, false, "the market")
	return "market"


# --- Reacting to the moment ---------------------------------------------------------------

func _react(villager: Node, chosen: VillagerActivity) -> VillagerActivity:
	if chosen == null or chosen.is_sleep() or chosen.kind == &"wait":
		return chosen
	var person: Person = Population.get_person(person_id)
	# A raid: everyone but the guards gathers at the meeting circle.
	var defence := VillageDefence.instance
	if defence and defence.is_raid() and not defence.is_guard(villager):
		return _instead("raid", chosen, "socialize", "plaza", "Gathering at the meeting circle while the guards hold the edge")
	# Fighting nearby: indoors, now.
	var player = GameManager.player
	if player and player.get("combat") and player.combat.in_fight() and villager is Node3D \
			and (villager as Node3D).global_position.distance_to(player.global_position) < FIGHT_RADIUS:
		return _instead("fight", chosen, "shelter", "home", "Hurrying indoors: there's fighting nearby")
	# Thornlings out: keep away from them.
	if Thornwood.instance and Thornwood.instance.remaining() > 0 and _near(chosen.location_id, Thornwood.instance.center, DANGER_RADIUS):
		return _instead("thorns", chosen, "socialize", "plaza", "Keeping clear of the thornlings in the woods")
	# Rain: most people shelter.
	if Weather.instance and Weather.instance.is_raining() and not _is_sheltered(chosen):
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("%s/rain/%.1f" % [person_id, Weather.instance.until])
		var dutiful := person.trait_weight("conscientiousness") if person else 0.5
		var social := person.trait_weight("extraversion") if person else 0.5
		var roll := rng.randf()
		if chosen.kind == &"work" and roll < (dutiful - 0.55) * 1.4:
			return _instead("rain_work", chosen, "work", chosen.location_id, "%s in the rain" % (chosen.label if chosen.label != "" else "Working"), String(chosen.animation))
		if person and roll > 1.0 - (social - 0.5) * 0.8:
			var friend := _friend_to_visit(person, rng)
			if not friend.is_empty():
				return _instead("rain_visit", chosen, "visit", String(friend["home"]), "Sheltering from the rain at %s's" % friend["name"])
		return _instead("rain", chosen, "shelter", "home", "Sheltering from the rain at home")
	return chosen


func _is_sheltered(activity: VillagerActivity) -> bool:
	if activity.kind in [&"shelter", &"visit", &"rest"] or activity.location_id == "home":
		return true
	var location: Dictionary = VillageLayout.get_locations().get(activity.location_id, {})
	return bool(location.get("inside", false))


static func _near(location_id: String, point: Vector3, radius: float) -> bool:
	var location: Dictionary = VillageLayout.get_locations().get(location_id, {})
	for spot in location.get("spots", []):
		if Vector2((spot as Vector3).x - point.x, (spot as Vector3).z - point.z).length() < radius:
			return true
	return false


## A replacement activity, the same object each time (so the villager doesn't
## keep restarting it).
func _instead(reason: String, original: VillagerActivity, kind: String, location: String, label: String, anim: String = "") -> VillagerActivity:
	var cache_key := "%s|%s" % [reason, original.key()]
	if not _reactions.has(cache_key):
		var activity := VillagerActivity.from_entry({"activity": kind, "location": location, "label": label, "anim": anim, "hour": original.start_hour})
		activity.reason = reason
		_reactions[cache_key] = activity
	return _reactions[cache_key]
