class_name TaskSystem
extends Node
## Jobs the player can ask villagers to do. Whether they agree depends on
## who they are (Mara loves building, Tomas's knees mind the quarry), how
## they feel about the player and what time it is. While at work they
## really contribute: building sites progress, wood and stone arrive in the
## village stores, crops grow faster.

const TASK_HOURS := 3.0
## Work given to a building site per game hour by one helper.
const MEETING_RADIUS := 3.6
const MEETING_RING := 10
const BUILD_RATE := 1.2
## Resources delivered per game hour by one helper.
const GATHER_RATE := 2.0

const KINDS: Array[StringName] = [&"build", &"wood", &"stone", &"farm"]
const LABELS := {&"build": "Helping you build", &"wood": "Gathering wood for the village",
	&"stone": "Breaking stone at the quarry", &"farm": "Tending the crops", &"meeting": "At the village meeting"}
const ASK_TEXT := {&"build": "Could you help me build?", &"wood": "Could you gather some wood?",
	&"stone": "Could you break some stone at the quarry?", &"farm": "Could you tend the crops?"}

## How keen each villager is on each job (0..1).
const PREFERENCES := {
	&"mara": {&"build": 1.0, &"stone": 0.8, &"wood": 0.6, &"farm": 0.25},
	&"elias": {&"farm": 1.0, &"wood": 0.6, &"build": 0.45, &"stone": 0.35},
	&"nia": {&"farm": 0.8, &"wood": 0.4, &"build": 0.3, &"stone": 0.25},
	&"tomas": {&"build": 0.8, &"wood": 0.55, &"farm": 0.35, &"stone": 0.15},
	&"sera": {&"wood": 0.55, &"stone": 0.5, &"farm": 0.45, &"build": 0.4},
}

## What they say when they agree eagerly ("love"), agree ("ok") or refuse.
const LINES := {
	&"mara": {
		&"love": "[laughing]Finally, something worth doing! I'll get my hammer.",
		&"ok": "[happy]Alright, I can spare a few hours.",
		&"no": "[worried]Not now. I've got my own walls to raise.",
	},
	&"elias": {
		&"love": "[happy]The land's always glad of another pair of hands. I'm on my way.",
		&"ok": "[happy]Of course. That's what neighbours are for.",
		&"no": "[sad]I'm sorry, I can't leave the fields today.",
	},
	&"nia": {
		&"love": "[laughing]Yes! I'll check the soil while I'm there.",
		&"ok": "[happy]Sure, I can help for a while.",
		&"no": "[worried]Oh... I'm not really strong enough for that. Ask Mara?",
	},
	&"tomas": {
		&"love": "[happy]Good work wants good hands. I'll come, slowly.",
		&"ok": "[happy]My knees will complain, but alright.",
		&"no": "[sad]Not with these knees, I'm afraid. Mara's your woman for that.",
	},
	&"sera": {
		&"love": "[laughing]An adventure! Well, a small one. I'm in.",
		&"ok": "[happy]Fine, fine. You'll owe me a story.",
		&"no": "[worried]Ugh, not today. Ask me again tomorrow?",
	},
}

static var instance: TaskSystem

var _accumulated: Dictionary = {}
var _last_clock: float = -1.0


func _ready() -> void:
	name = "TaskSystem"
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


static func absolute_hours() -> float:
	return WorldClock.day * 24.0 + WorldClock.time_of_day


## Asks `villager` to do `kind`. Returns { "accepted": bool, "lines": [...] }.
static func request(villager, kind: StringName) -> Dictionary:
	var id: StringName = villager.data.id
	var lines_for: Dictionary = LINES[id] if LINES.has(id) else generated_lines(villager.person)
	var mind: VillagerMind = villager.mind
	var player := GameManager.PLAYER_ID
	if mind.is_hostile(player):
		return {"accepted": false, "lines": ["[angry]Why would I help you?"]}
	if villager.person and villager.person.life_stage() == Person.STAGE_CHILD:
		return {"accepted": false, "lines": ["[laughing]I'm too little for that! Ask a grown-up."]}
	if WorldClock.time_of_day >= 20.0 or WorldClock.time_of_day < 6.0:
		return {"accepted": false, "lines": ["[worried]It's too dark for that now. Ask me in the morning."]}
	if villager.has_task() and String(villager.task.get("kind", "")) != "meeting":
		return {"accepted": false, "lines": ["[laughing]One thing at a time! I'm still on the last job."]}
	var target := task_target(villager, kind)
	if target.is_empty():
		return {"accepted": false, "lines": ["[surprised]There's nothing to build yet. Place a foundation first."]}
	var preference := float(PREFERENCES[id].get(kind, 0.4)) if PREFERENCES.has(id) \
		else (Professions.task_preference(villager.person, kind) if villager.person else 0.4)
	var warmth := mind.get_affection(player) / 100.0
	var score := preference + warmth * 0.6 + mind.get_trust(player) / 100.0 * 0.3
	if score < 0.35:
		return {"accepted": false, "lines": [lines_for[&"no"]]}
	var activity := VillagerActivity.new()
	activity.kind = StringName("task_" + String(kind))
	activity.location_id = "task"
	activity.label = String(LABELS[kind])
	activity.animation = &"gather" if kind == &"farm" else &"work"
	activity.start_hour = absolute_hours()
	target["kind"] = String(kind)
	target["activity"] = activity
	target["until"] = absolute_hours() + TASK_HOURS
	villager.assign_task(target)
	GameState.increment(&"tasks_accepted")
	mind.adjust_opinion(player, 1.0, 2.0)
	return {"accepted": true, "lines": [lines_for[&"love"] if preference >= 0.75 else lines_for[&"ok"]]}


## Replies for newcomers, by temperament: cheerful, dutiful or grumpy.
static func generated_lines(person: Person) -> Dictionary:
	if person == null:
		return LINES[&"elias"]
	if person.trait_weight("extraversion") > 0.6:
		return {&"love": "[laughing]Ha! Just what I'm good at. Watch this!", &"ok": "[happy]Sure, why not? I'll head over now.",
			&"no": "[worried]Oh, I'd only get in the way with that. Ask someone else?"}
	if person.trait_weight("agreeableness") < 0.38:
		return {&"love": "[happy]Finally, real work. I'll do it properly.", &"ok": "Fine. Don't hover while I work.",
			&"no": "[angry]That's not my job."}
	return {&"love": "[happy]That's my trade. I'll be glad to.", &"ok": "[happy]Alright, I can help with that.",
		&"no": "[sad]I'm sorry, that's not something I can do well."}


## Where the villager should work, or {} if there's nowhere to do this job.
static func task_target(villager, kind: StringName) -> Dictionary:
	var from: Vector3 = villager.global_position
	# Each villager's own slot, so two helpers never stand on one spot.
	var count := maxi(GameManager.villagers.size(), 1)
	var slot := maxi(GameManager.villagers.find(villager), 0)
	match kind:
		&"build":
			var site: PlacedStructure = StructureManager.instance.nearest_unfinished(from) if StructureManager.instance else null
			if site == null:
				return {}
			var side := (from - site.global_position)
			side.y = 0.0
			side = side.normalized() if side.length() > 0.1 else Vector3.BACK
			side = side.rotated(Vector3.UP, (slot - (count - 1) * 0.5) * 0.45)
			var point := site.global_position + side * (StructureCatalog.radius(site.get_type()) + 0.8)
			return {"point": point, "look": site.global_position, "site": site}
		&"wood", &"stone":
			var wanted: StringName = &"tree" if kind == &"wood" else &"rock"
			var best: ResourceNode = null
			for node in ResourceSpawner.nodes:
				if node.kind == wanted and (best == null or node.global_position.distance_to(from) < best.global_position.distance_to(from)):
					best = node
			if best == null:
				return {}
			var offset := Vector3(1.3, 0, 0.0).rotated(Vector3.UP, TAU * slot / count)
			return {"point": best.global_position + offset, "look": best.global_position}
		&"farm":
			var spot: Vector3 = VillageLayout.get_locations()["farm"]["spots"][1]
			spot += Vector3(0, 0, (slot - (count - 1) * 0.5) * 1.1)
			return {"point": spot, "look": spot + Vector3(1, 0, 0)}
		&"meeting":
			return {"point": meeting_spot(villager), "look": Vector3.ZERO}
	return {}


## Each villager's own place in a ring around the fire, so nobody shares a
## spot (two people on one spot render as one body with two faces). The ring
## leaves a gap on the +X side, where the player stands to call the meeting.
static func meeting_spot(villager) -> Vector3:
	# Rings of up to MEETING_RING places, further out as the village grows.
	var index := maxi(GameManager.villagers.find(villager), 0)
	var ring := index / MEETING_RING
	var in_ring := mini(GameManager.villagers.size() - ring * MEETING_RING, MEETING_RING)
	var slot := index % MEETING_RING
	var angle := lerpf(0.9, TAU - 0.9, (slot + 0.5) / maxf(in_ring, 1.0)) + ring * 0.2
	var radius := MEETING_RADIUS + ring * 1.4
	return VillageLayout.ground_point(cos(angle) * radius, sin(angle) * radius)


## Contributions from villagers who are at work, as game time passes.
func _process(_delta: float) -> void:
	var clock := absolute_hours()
	if _last_clock < 0.0 or clock <= _last_clock:
		_last_clock = clock
		return
	var hours := minf(clock - _last_clock, 6.0)
	_last_clock = clock
	for villager in GameManager.villagers:
		if villager.is_working_on_task():
			contribute(villager, hours)


## What one villager achieves in `hours` of work on their task.
func contribute(villager, hours: float) -> void:
	var kind := String(villager.task.get("kind", ""))
	match kind:
		"build":
			var site = villager.task.get("site")
			if site != null and is_instance_valid(site) and not site.is_complete():
				site.add_work(BUILD_RATE * hours)
			elif site != null:
				villager.task["until"] = 0.0
		"wood", "stone", "farm":
			var resource: StringName = &"food" if kind == "farm" else StringName(kind)
			var key := "%s:%s" % [villager.data.id, resource]
			_accumulated[key] = float(_accumulated.get(key, 0.0)) + GATHER_RATE * hours * (0.5 if kind == "farm" else 1.0)
			var whole := int(_accumulated[key])
			if whole > 0:
				_accumulated[key] = float(_accumulated[key]) - whole
				GameState.add(resource, whole)
				FloatingText.spawn(villager.get_parent(), villager.global_position + Vector3(0, 2.3, 0),
					"+%d %s" % [whole, GameState.RESOURCE_NAMES[resource]], Color(0.75, 0.95, 0.75))
			if kind == "farm":
				for structure in get_tree().get_nodes_in_group("placed_structures"):
					structure.grow(hours * 0.5)
