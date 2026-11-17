class_name Festival
extends Node3D
## A village festival every week, from the second week on: four kinds in
## turn (harvest, lanterns, builders, stories), each over two village days
## (days 5 and 6 of the week), announced the day before. During a festival
## the meeting circle is decorated, villagers greet you with festival talk,
## everyone dances at the fire in the evening, and there are a few optional
## goals with rewards. Nothing is lost by missing one: next week brings the
## next festival.

signal changed

const START_WEEK := 1  # 0-based: the first week is for settling in
const FIRST_DAY_OF_WEEK := 4  # 0-based day in the week: days 5 and 6
const LENGTH_DAYS := 2
const EVENING_HOUR := 18.0

const FESTIVALS := [
	{
		"id": "harvest", "name": "Harvest Festival",
		"intro": "The Harvest Festival has begun! Bring in food and share it with your neighbours.",
		"announce": "Tomorrow is the Harvest Festival. Everyone's baking already.",
		"goals": [
			{"id": "food", "text": "Bring in 12 food", "kind": "collect", "resource": &"food", "goal": 12, "reward": {&"herbs": 3, &"wood": 5}},
			{"id": "gifts", "text": "Give gifts to 2 villagers", "kind": "gifts", "goal": 2, "reward": {&"stone": 4, &"food": 3}},
		],
		"bonus": {&"wood": 10, &"food": 8},
		"lines": ["[happy]Happy Harvest Festival! Have you tried the honey bread?", "[laughing]The harvest's in! Tonight we dance by the fire.",
			"[happy]A good harvest means a good winter. Thank you for your part in it."],
		"child": ["[laughing]There are apple cakes! Did you get one?", "[happy]I helped carry the pumpkins!"],
		"grumpy": ["[worried]Festival, festival. Someone still has to wash the pots.", "Hmph. The bread's not bad this year, I'll give them that."],
		"chatter": "[happy]Everyone's still talking about the Harvest Festival.",
	},
	{
		"id": "lanterns", "name": "Lantern Night",
		"intro": "Lantern Night! Light up the village and meet everyone at the fire after dark.",
		"announce": "Tomorrow is Lantern Night. Get your lanterns ready!",
		"goals": [
			{"id": "lantern", "text": "Build a lantern", "kind": "build", "type": &"lantern", "goal": 1, "reward": {&"stone": 4, &"wood": 4}},
			{"id": "fire", "text": "Join everyone at the fire after dark", "kind": "fire_night", "goal": 1, "reward": {&"food": 4}},
		],
		"bonus": {&"stone": 10, &"herbs": 4},
		"lines": ["[happy]It's Lantern Night! Each light is a wish for the village.", "[happy]Will you come to the fire tonight? It's beautiful with all the lanterns.",
			"[laughing]I made my lantern myself. It's a bit crooked, but it's mine."],
		"child": ["[laughing]Can I hold a lantern? Please? I'll be careful!", "[happy]The lanterns look like fireflies!"],
		"grumpy": ["Lanterns everywhere. Mind nobody sets the thatch alight.", "[worried]Late nights and candle wax. Lovely."],
		"chatter": "[happy]Lantern Night was lovely. I made a wish for you too.",
	},
	{
		"id": "builders", "name": "Builders' Fair",
		"intro": "The Builders' Fair is on! Gather timber and finish something new for the village.",
		"announce": "The Builders' Fair is tomorrow. Mind your thumbs!",
		"goals": [
			{"id": "wood", "text": "Chop 10 wood", "kind": "collect", "resource": &"wood", "goal": 10, "reward": {&"stone": 5}},
			{"id": "build", "text": "Finish any building", "kind": "build", "type": &"", "goal": 1, "reward": {&"wood": 6, &"food": 3}},
		],
		"bonus": {&"wood": 12, &"stone": 8},
		"lines": ["[happy]The Builders' Fair! Show us what you can make.", "[laughing]Elias says his fence is the straightest. We'll see about that.",
			"[happy]A village grows one plank at a time. Good to have you building with us."],
		"child": ["[laughing]I built a tower of sticks! It fell over, but it was SO tall.", "[happy]When I'm big I'll build a castle."],
		"grumpy": ["Hammering from dawn till dusk. My poor head.", "[worried]Everyone's a builder this week. Heaven help us."],
		"chatter": "[happy]Did you see what went up at the Builders' Fair? The village is growing.",
	},
	{
		"id": "stories", "name": "Story Night",
		"intro": "It's Story Night! Talk with the villagers and hear their stories at the fire.",
		"announce": "Tomorrow is Story Night. Think of a good tale to tell!",
		"goals": [
			{"id": "talk", "text": "Talk with 4 villagers", "kind": "talk", "goal": 4, "reward": {&"herbs": 3, &"food": 3}},
			{"id": "fire", "text": "Hear the stories at the fire after dark", "kind": "fire_night", "goal": 1, "reward": {&"wood": 5}},
		],
		"bonus": {&"food": 8, &"stone": 6},
		"lines": ["[happy]It's Story Night. Shall I tell you how this village began?", "[laughing]Tomas tells the ghost story every year. Every year we pretend to be scared.",
			"[happy]Stories are how a village remembers. Yours is part of ours now."],
		"child": ["[laughing]I know a story about a dragon! Do you want to hear it?", "[worried]Tomas's ghost story isn't real... is it?"],
		"grumpy": ["The same old stories, every year. ...I do like the one about the flood.", "[worried]If Tomas tells the ghost story again I'm going to bed."],
		"chatter": "[happy]I keep thinking about the stories from Story Night.",
	},
]

static var instance: Festival

## Which week's festival the state below belongs to (-1: none yet).
var week: int = -1
var progress: Dictionary = {}
var done: Dictionary = {}
var bonus_given: bool = false
var talked: Dictionary = {}
var gifts_base: int = 0
var evening_day: int = -1
var announced_week: int = -1
var opened_week: int = -1
## Past festivals: [{week, id, goals_done, all_done}]
var history: Array = []

var _decorations: Node3D
var _granting: bool = false
var _fire_timer: float = 0.0


func _ready() -> void:
	name = "Festival"
	instance = self
	GameState.inventory_changed.connect(_on_inventory_changed)
	GameManager.conversation_started.connect(_on_conversation_started)
	WorldClock.hour_changed.connect(func(_h): refresh())
	WorldClock.day_changed.connect(func(_d): refresh())
	if StructureManager.instance:
		StructureManager.instance.structure_completed.connect(_on_structure_completed)
	refresh.call_deferred()


func _exit_tree() -> void:
	if instance == self:
		instance = null


# --- Calendar ---------------------------------------------------------------------

static func week_of(day: int) -> int:
	return (day - 1) / 7


static func day_in_week(day: int) -> int:
	return (day - 1) % 7


## The festival running on `day` ({} if none).
static func festival_on(day: int) -> Dictionary:
	var w := week_of(day)
	var d := day_in_week(day)
	if w < START_WEEK or d < FIRST_DAY_OF_WEEK or d >= FIRST_DAY_OF_WEEK + LENGTH_DAYS:
		return {}
	return FESTIVALS[(w - START_WEEK) % FESTIVALS.size()]


## The festival starting tomorrow ({} if none).
static func festival_tomorrow(day: int) -> Dictionary:
	if not festival_on(day).is_empty():
		return {}
	var next := festival_on(day + 1)
	return next if day_in_week(day + 1) == FIRST_DAY_OF_WEEK else {}


func current() -> Dictionary:
	return festival_on(WorldClock.day)


func is_active() -> bool:
	return not current().is_empty()


# --- Running it -------------------------------------------------------------------

func refresh() -> void:
	var festival := current()
	var w := week_of(WorldClock.day)
	if festival.is_empty():
		_close_if_over()
		var tomorrow := festival_tomorrow(WorldClock.day)
		if not tomorrow.is_empty() and announced_week != w and WorldClock.time_of_day >= 7.0:
			announced_week = w
			GameManager.notify(String(tomorrow["announce"]))
		_set_decorations(false)
		return
	if week != w:
		_begin(w)
	if opened_week != w:
		opened_week = w
		GameManager.notify(String(festival["intro"]))
		Sounds.play("notify", null, -4.0)
	_set_decorations(true)
	if WorldClock.time_of_day >= EVENING_HOUR and WorldClock.time_of_day < 22.0 and evening_day != WorldClock.day:
		evening_day = WorldClock.day
		_gather_at_fire(festival)
	changed.emit()


func _begin(w: int) -> void:
	week = w
	progress = {}
	done = {}
	bonus_given = false
	talked = {}
	gifts_base = int(GameState.get_flag(&"gifts", 0))
	evening_day = -1


## When a festival ends, it goes into the village's memory.
func _close_if_over() -> void:
	if week < 0 or (not history.is_empty() and int(history[-1]["week"]) == week):
		return
	var festival: Dictionary = FESTIVALS[(week - START_WEEK) % FESTIVALS.size()]
	history.append({"week": week, "id": festival["id"], "goals_done": done.size(), "all_done": bonus_given, "day": WorldClock.day})
	if history.size() > 12:
		history.pop_front()


## In the evening everyone who's free gathers at the fire and dances.
func _gather_at_fire(festival: Dictionary) -> void:
	for villager in GameManager.villagers:
		if not is_instance_valid(villager) or not villager.visible or villager.is_visitor() or villager.is_leaving() or villager.has_task():
			continue
		var target := TaskSystem.task_target(villager, &"meeting")
		if target.is_empty():
			continue
		var activity := VillagerActivity.new()
		activity.kind = &"task_festival"
		activity.location_id = "task"
		activity.label = "Celebrating %s" % festival["name"]
		activity.animation = &"dance"
		target["kind"] = "festival"
		target["activity"] = activity
		target["until"] = TaskSystem.absolute_hours() + 3.0
		villager.assign_task(target)


func _process(delta: float) -> void:
	if not is_active():
		return
	_fire_timer -= delta
	if _fire_timer > 0.0:
		return
	_fire_timer = 0.5
	var player = GameManager.player
	var hour := WorldClock.time_of_day
	if player and (hour >= EVENING_HOUR or hour < 1.0) and Vector2(player.global_position.x, player.global_position.z).length() < 6.0:
		_advance("fire_night", 1)


# --- Goals ------------------------------------------------------------------------

func goals() -> Array:
	var festival := current()
	return festival.get("goals", []) if not festival.is_empty() else []


func goal_progress(goal_id: String) -> int:
	return int(progress.get(goal_id, 0))


func _advance(kind: String, amount: int, match_value: Variant = null) -> void:
	if not is_active() or amount <= 0:
		return
	for goal: Dictionary in goals():
		if String(goal["kind"]) != kind or done.has(String(goal["id"])):
			continue
		if kind == "collect" and StringName(goal["resource"]) != match_value:
			continue
		if kind == "build" and StringName(goal["type"]) != &"" and StringName(goal["type"]) != match_value:
			continue
		var id := String(goal["id"])
		progress[id] = mini(goal_progress(id) + amount, int(goal["goal"]))
		if goal_progress(id) >= int(goal["goal"]):
			_complete(goal)
	changed.emit()


## Sets a goal's progress directly (counts that are totals, like gifts).
func _set_progress(kind: String, value: int) -> void:
	if not is_active():
		return
	for goal: Dictionary in goals():
		if String(goal["kind"]) == kind and not done.has(String(goal["id"])):
			var id := String(goal["id"])
			progress[id] = mini(value, int(goal["goal"]))
			if goal_progress(id) >= int(goal["goal"]):
				_complete(goal)
	changed.emit()


func _complete(goal: Dictionary) -> void:
	done[String(goal["id"])] = true
	VillageCredits.award("festival_goal", "festival_%d_%s" % [WorldClock.day / 7, String(goal["id"])], "a festival goal")
	var reward: Dictionary = goal["reward"]
	_grant(reward)
	GameManager.notify("Festival goal done: %s  (+%s)" % [goal["text"], GameState.cost_text(reward)])
	Sounds.play("built", null, -4.0)
	if done.size() >= goals().size() and not bonus_given:
		bonus_given = true
		var festival := current()
		_grant(festival["bonus"])
		# Everyone's happier for a festival well kept.
		for villager in GameManager.villagers:
			if is_instance_valid(villager) and villager.person:
				villager.person.happiness = minf(villager.person.happiness + 8.0, 100.0)
				villager.mind.adjust_opinion(GameManager.PLAYER_ID, 4.0, 2.0)
		GameManager.notify("You made %s one to remember!  (+%s, and everyone is happier)" % [festival["name"], GameState.cost_text(festival["bonus"])])


func _grant(items: Dictionary) -> void:
	_granting = true
	for resource in items:
		GameState.add(resource, int(items[resource]))
	_granting = false


func _on_inventory_changed(resource: StringName, amount: int, _total: int) -> void:
	if _granting or amount <= 0:
		return
	_advance("collect", amount, resource)
	_set_progress("gifts", int(GameState.get_flag(&"gifts", 0)) - gifts_base)


func _on_conversation_started(villager, _conversation) -> void:
	if villager == null or not is_instance_valid(villager) or not is_active():
		return
	var id := String(villager.get_villager_id())
	if talked.has(id):
		return
	talked[id] = true
	_advance("talk", 1)


func _on_structure_completed(structure) -> void:
	_advance("build", 1, structure.get_type())


## Called by Deeds after a gift (gift counts aren't an inventory gain).
func note_gift() -> void:
	_set_progress("gifts", int(GameState.get_flag(&"gifts", 0)) - gifts_base)


# --- Dialogue ---------------------------------------------------------------------

## A festival greeting in this villager's own manner (once per festival each).
func greeting_for(villager) -> String:
	var festival := current()
	if festival.is_empty():
		return ""
	var key := "festival:%d" % week
	var mind: VillagerMind = villager.mind
	if mind.memory.has_detail("mentioned", GameManager.PLAYER_ID, key):
		return ""
	mind.memory.add("mentioned", GameManager.PLAYER_ID, WorldClock.day, WorldClock.time_of_day, key)
	var tone := LineBank.tone_of(villager)
	var pool: Array = festival.get(tone, festival["lines"]) if tone in ["child", "grumpy"] else festival["lines"]
	return String(pool[hash(String(villager.get_villager_id()) + key) % pool.size()])


## The last festival, if it was within the last few days (for chatter).
func recent_memory() -> Dictionary:
	if history.is_empty() or is_active():
		return {}
	var last: Dictionary = history[-1]
	if WorldClock.day - int(last.get("day", 0)) > 3:
		return {}
	for festival: Dictionary in FESTIVALS:
		if festival["id"] == last["id"]:
			return {"week": int(last["week"]), "line": festival["chatter"], "all_done": bool(last["all_done"])}
	return {}


# --- Decorations ------------------------------------------------------------------

func _set_decorations(on: bool) -> void:
	if on and _decorations == null:
		_decorations = _build_decorations()
		add_child(_decorations)
	elif not on and _decorations != null:
		_decorations.queue_free()
		_decorations = null


## Bunting on poles around the meeting circle.
func _build_decorations() -> Node3D:
	var root := Node3D.new()
	root.name = "FestivalDecorations"
	var b := MeshBuilder.new(77)
	var colors := [Color(0.9, 0.3, 0.25), Color(0.95, 0.75, 0.2), Color(0.3, 0.6, 0.9), Color(0.4, 0.75, 0.35), Color(0.85, 0.45, 0.8)]
	var floor_y := VillageLayout.plaza_floor_height()
	var radius := VillageLayout.PLAZA_RADIUS + 0.4
	var poles := 8
	for i in poles:
		var a := TAU * (float(i) + 0.5) / poles
		var p := Vector3(cos(a) * radius, floor_y, sin(a) * radius)
		b.add_cylinder_at(p, 0.06, 0.05, 2.6, 6, Color(0.45, 0.32, 0.2))
		var a2 := TAU * (float(i) + 1.5) / poles
		var q := Vector3(cos(a2) * radius, floor_y, sin(a2) * radius)
		# Little flags hanging between this pole and the next.
		for f in 7:
			var t := (float(f) + 1.0) / 8.0
			var sag := sin(t * PI) * 0.35
			var at := p.lerp(q, t) + Vector3(0, 2.45 - sag, 0)
			b.add_box_at(at, Vector3(0.22, 0.22, 0.02), colors[(i + f) % colors.size()], atan2(q.x - p.x, q.z - p.z) + PI * 0.5)
	var mesh := MeshInstance3D.new()
	mesh.mesh = b.build(Materials.vertex_color())
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mesh)
	return root


# --- Save -------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"week": week, "progress": progress.duplicate(), "done": done.duplicate(), "bonus_given": bonus_given,
		"talked": talked.duplicate(), "gifts_base": gifts_base, "evening_day": evening_day,
		"announced_week": announced_week, "opened_week": opened_week, "history": history.duplicate(true)}


func from_dict(data: Dictionary) -> void:
	if data.is_empty():
		return
	week = int(data.get("week", -1))
	progress = {}
	for key in data.get("progress", {}):
		progress[String(key)] = int(data["progress"][key])
	done = (data.get("done", {}) as Dictionary).duplicate()
	bonus_given = bool(data.get("bonus_given", false))
	talked = (data.get("talked", {}) as Dictionary).duplicate()
	gifts_base = int(data.get("gifts_base", 0))
	evening_day = int(data.get("evening_day", -1))
	announced_week = int(data.get("announced_week", -1))
	opened_week = int(data.get("opened_week", -1))
	history = (data.get("history", []) as Array).duplicate(true)
