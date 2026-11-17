class_name HomeLife
extends Node
## Villagers living in houses the player built and gave them.
##
## Outside: every finished house has a front door that villagers walk to
## along the paths and up the front path (never through the house), then step
## through the doorway. Each house is a home location ("home_s<uid>").
##
## Inside: a house's rooms are their own space behind the door (built when
## the player goes in, like every interior in the game). While the player is
## in a house, everyone who is home there is in its rooms for real: they walk
## from room to room through the doorways, sit on the chairs, read at the
## shelf, cook at the hearth, tidy, chat with each other and with guests, and
## sleep in their own bed at night. Someone coming home walks in through the
## front door; someone going out walks to it. When the player isn't inside,
## the household keeps living there out of sight (nothing to draw or move,
## so a village full of homes costs nothing on a phone).
##
## The player can visit (knocking at night, when everyone's asleep), and can
## invite a friend over to their own house.

signal changed

static var instance: HomeLife

const WALK_SPEED_FACTOR := 0.75
const ARRIVE := 0.12
## How long they keep doing one thing indoors (seconds, while you watch).
const DO_MIN := 14.0
const DO_MAX := 32.0
## Invitations: how long a friend stays (game hours) and visiting hours.
const INVITE_HOURS := 2.5
const INVITE_FROM := 7.0
const INVITE_UNTIL := 21.0
## Friendship from the player's visits and invitations.
const VISIT_AFFECTION := 3.0
const INVITE_AFFECTION := 6.0
const SEATS := ["chair", "stool", "settle", "bench_seat"]

## What giving a house brings:
## - friendship: a big boost with the new owner (and their household);
const GIVE_AFFECTION := 15.0
const GIVE_AFFECTION_FAMILY := 8.0
## - a thank-you when they first come home: credits and something from their trade;
const THANKS_CREDITS := 15
## - happier people (added to their daily happiness, by house size);
const HOUSE_HAPPINESS := {"house": 6.0, "house_medium": 8.0, "house_large": 10.0, "manor": 12.0}
## - and every few days, a small gift from their work.
const GIFT_EVERY_DAYS := 3
const TRADE_GIFTS := {
	"farmer": {&"food": 4}, "fisher": {&"food": 4}, "cook": {&"food": 5}, "herbalist": {&"herbs": 3},
	"woodcutter": {&"wood": 6}, "builder": {&"wood": 4, &"stone": 2}, "stonemason": {&"stone": 5},
	"craftsman": {&"wood": 3, &"stone": 2}, "trader": {&"food": 2, &"herbs": 2}, "weaver": {&"herbs": 2, &"food": 2},
}
const DEFAULT_GIFT := {&"food": 2, &"wood": 2}

## Lines for home life, picked so the same person doesn't repeat themselves.
const WELCOME_PLAYER := {
	"close": ["You're here! Come in, come in.", "I was hoping you'd drop by.", "Sit anywhere, you know you're welcome."],
	"friendly": ["Oh, hello! Come in.", "Nice of you to visit.", "Mind the step, and come on in."],
	"neutral": ["Oh. Hello there.", "Can I help you with something?", "Come in, I suppose."],
	"wary": ["...What do you want?", "Make it quick, please."],
}
const WELCOME_GUEST := ["Come in! I'll put the kettle on.", "There you are. Sit, sit.", "Good to see you. Make yourself at home.",
	"Ah, just in time. I was getting bored of my own company."]
const GUEST_THANKS := ["Thanks for having me.", "What a lovely place.", "I brought nothing but gossip, I'm afraid.",
	"It's so cosy in here."]
const HOME_CHAT := ["Did you hear the hens got out again?", "The bread came out right this time.", "My back's aching from the fields.",
	"I keep meaning to fix that shutter.", "Have you been out to the windmill lately?", "I dreamt about the river last night.",
	"Quiet day. I like quiet days.", "The new house still smells of fresh wood.", "Who keeps leaving the gate open?",
	"I think it'll rain tomorrow.", "Tell me everything.", "Ha! No, really?", "That's what I said!", "Mm. Pass the tea?"]
const INVITE_THANKS := ["Thanks for inviting me!", "So this is your place. It's lovely.", "I've been looking forward to this."]

## While the player is in a house: its home id, type and room place.
var room_home: String = ""
var room_type: StringName = &""
var room_place: String = ""
## villager -> { path: PackedVector2Array, i, plan: Dictionary, timer, out: bool }
var _agents: Dictionary = {}
## furniture id -> villager (who is using it right now)
var _claims: Dictionary = {}
var _rng := RandomNumberGenerator.new()
## villager id -> { home, until (absolute hours), arrived }
var invites: Dictionary = {}
## villager id -> day the player last visited them at home (friendship once a day)
var visited: Dictionary = {}
var _recent_lines: Array = []
var _check_timer: float = 0.0


func _ready() -> void:
	name = "HomeLife"
	instance = self
	_rng.randomize()
	if Interiors.instance:
		Interiors.instance.entered.connect(_on_player_entered)
		Interiors.instance.left.connect(_on_player_left)
	if StructureManager.instance:
		StructureManager.instance.structure_completed.connect(func(_s): register_all())
		StructureManager.instance.structure_moved.connect(func(_s): register_all())
		StructureManager.instance.structure_removed.connect(_on_structure_removed)
	Population.housing_changed.connect(register_all)
	Population.house_given.connect(_on_house_given)
	WorldClock.day_changed.connect(_on_day_changed)
	register_all()  # before the villagers are placed


func _exit_tree() -> void:
	if instance == self:
		instance = null


# --- Homes outside ----------------------------------------------------------------------

static func is_house_home(home_id: String) -> bool:
	return HouseDesigns.is_house(StringName(String(Population.house_record(home_id).get("type", ""))))


static func home_available(home_id: String) -> bool:
	var record := Population.house_record(home_id)
	return not record.is_empty() and bool(record.get("complete", false)) and VillageLayout.get_locations().has(home_id)


static func structure_of(home_id: String) -> PlacedStructure:
	var record := Population.house_record(home_id)
	if record.is_empty() or StructureManager.instance == null:
		return null
	for s in StructureManager.instance.structures():
		if s.record == record:
			return s
	return null


## The house's door: threshold (in the doorway), step (just outside),
## approach (down the front path) and the way the house faces. {} if none.
static func door_of(home_id: String) -> Dictionary:
	if not home_id.begins_with("home_s"):
		return {}
	return door_of_structure(structure_of(home_id))


static func door_of_structure(s) -> Dictionary:
	if s == null or not is_instance_valid(s) or not HouseDesigns.is_house(s.get_type()):
		return {}
	var front: Vector3 = (s.global_transform.basis * Vector3(0, 0, 1)).normalized()
	var half := float(s.get_info()["footprint"].y) * 0.5
	var c: Vector3 = s.global_position
	return {"threshold": c + front * (half - 0.15), "step": c + front * (half + 1.2), "approach": c + front * (half + 3.2), "yaw": s.rotation.y}


## Points to walk from `a` to `b` around the house `home_id` (never through
## it): nothing if the straight line misses it, else a corner or two of the
## house's surroundings (on the side nearer `a`).
static func around(home_id: String, a: Vector3, b: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	var s := structure_of(home_id)
	if s == null:
		return out
	var fp: Vector2 = s.get_info()["footprint"]
	var hx := fp.x * 0.5 + 1.0
	var hz := fp.y * 0.5 + 1.0
	var inv: Transform3D = s.global_transform.affine_inverse()
	var la: Vector3 = inv * a
	var lb: Vector3 = inv * b
	var pa := Vector2(la.x, la.z)
	var pb := Vector2(lb.x, lb.z)
	var box := [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(hx, hz), Vector2(-hx, hz)]
	var hits := absf(la.x) < hx and absf(la.z) < hz
	for i in 4:
		if Geometry2D.segment_intersects_segment(pa, pb, box[i], box[(i + 1) % 4]) != null:
			hits = true
	if not hits:
		return out
	var side := 1.0 if la.x >= 0.0 else -1.0
	var corners: Array = []
	if la.z < -hz + 0.5:
		corners.append(Vector3(side * hx, 0, -hz))
	corners.append(Vector3(side * hx, 0, hz))
	if lb.z < -hz + 0.5:
		corners.append(Vector3(side * hx, 0, -hz))
	for c in corners:
		var w: Vector3 = s.global_transform * c
		out.append(Vector3(w.x, 0.0, w.z))
	return out


## Makes every finished house a place villagers can walk to.
func register_all() -> void:
	if StructureManager.instance == null:
		return
	for s in StructureManager.instance.structures():
		if not HouseDesigns.is_house(s.get_type()):
			continue
		var home_id := Population.cottage_home_id(s.record)
		var door := door_of_structure(s)
		if s.is_complete() and not door.is_empty() and not s.is_queued_for_deletion():
			VillageLayout.register_location(home_id, [door["step"]], [s.global_position], true, _label(s.record))
	changed.emit()


func _label(record: Dictionary) -> String:
	if Population.is_given_house(record):
		return Population.house_label(record)
	return "your house"


## Where `villager` goes when they go home: their home, or (while their house
## is being expanded) where they lived before, or the camp.
static func home_for(villager) -> String:
	var home: String = villager.data.home_location
	if not is_house_home(home) or home_available(home):
		return home if VillageLayout.get_locations().has(home) or home == Population.CAMP_ID else Population.CAMP_ID
	var record := Population.house_record(home)
	var previous: Dictionary = record.get("previous_homes", {}) if record.get("previous_homes", {}) is Dictionary else {}
	var back := String(previous.get(String(villager.data.id), ""))
	if back != "" and VillageLayout.get_locations().has(back) and not is_house_home(back):
		return back
	return Population.CAMP_ID


func _on_structure_removed(structure) -> void:
	if structure == null or not HouseDesigns.is_house(structure.get_type()):
		return
	var home_id := Population.cottage_home_id(structure.record)
	var moved: Array = []
	if Population.is_given_house(structure.record):
		moved = Population.rehouse_from(home_id, structure.record)
		Population.home_owners.erase(home_id)
		Population.housing_changed.emit()
	VillageLayout.unregister_location(home_id)
	for id in invites.keys():
		if String(invites[id]["home"]) == home_id:
			invites.erase(id)
	if not moved.is_empty():
		GameManager.notify("%s moved back to their old home." % ", ".join(moved.map(func(p): return p.first_name)))


# --- What a house brings --------------------------------------------------------------------

static func trade_gift(person: Person) -> Dictionary:
	return TRADE_GIFTS.get(person.profession, DEFAULT_GIFT) if person else DEFAULT_GIFT


func _on_house_given(record: Dictionary, person: Person) -> void:
	var home_id := Population.cottage_home_id(record)
	for id in Population.residents_of(home_id):
		var villager = GameManager.get_villager(StringName(String(id)))
		if villager == null:
			continue
		var boost := GIVE_AFFECTION if String(id) == person.id else GIVE_AFFECTION_FAMILY
		villager.mind.adjust_opinion(GameManager.PLAYER_ID, boost, boost * 0.6)
		villager.mind.record_interaction(GameManager.PLAYER_ID, "gave_house", WorldClock.day, WorldClock.time_of_day)
		GameManager.opinion_changed.emit(villager, villager.mind.get_affection(GameManager.PLAYER_ID), villager.mind.get_trust(GameManager.PLAYER_ID))
	var owner = GameManager.get_villager(StringName(person.id))
	if owner:
		owner.say("A house of our own? Thank you! I'll never forget this.")


## The first time the new owner comes home, they thank you: credits and
## something from their trade (once per household and house).
func _thank_for_house(villager, home_id: String) -> void:
	var record := Population.house_record(home_id)
	if record.is_empty() or not Population.is_given_house(record) or String(Population.home_owners.get(home_id, "")) != String(villager.data.id):
		return
	var thanked: Array = record.get("thanked", []) if record.get("thanked", []) is Array else []
	if thanked.has(String(villager.data.id)):
		return
	thanked.append(String(villager.data.id))
	record["thanked"] = thanked
	var gift := trade_gift(villager.person)
	_give(gift)
	if VillageCredits.instance:
		VillageCredits.instance.earn(THANKS_CREDITS, "house_thanks_%s_%s" % [home_id, String(villager.data.id)])
	GameManager.notify("%s settled into the house and left you a thank-you: +%d Village Credits and %s." % [
		villager.data.display_name, THANKS_CREDITS, GameState.cost_text(gift)])


## Every few days each household in a house you gave leaves a little
## something from their work.
func _on_day_changed(day: int) -> void:
	if StructureManager.instance == null:
		return
	for record: Dictionary in GameState.structures:
		if not Population.is_given_house(record) or not bool(record.get("complete", false)):
			continue
		var home_id := Population.cottage_home_id(record)
		var owner := Population.get_person(String(Population.home_owners.get(home_id, "")))
		if owner == null or not owner.is_resident() or day - int(record.get("gift_day", day)) < GIFT_EVERY_DAYS:
			continue
		record["gift_day"] = day
		var gift := trade_gift(owner)
		_give(gift)
		GameManager.notify("%s left you a gift from their %s: %s." % [owner.first_name, Professions.label(owner.profession).to_lower() + "'s work", GameState.cost_text(gift)])


static func _give(items: Dictionary) -> void:
	CreditRewards.quiet = true
	for r in items:
		GameState.add(r, int(items[r]))
	CreditRewards.quiet = false


# --- Beds -----------------------------------------------------------------------------------

## The bed `person_id` sleeps in, in the house `home_id` (a furniture record),
## or {}. Partners share a double bed; everyone else gets one to themselves.
static func bed_for(person_id: String, home_id: String) -> Dictionary:
	var record := Population.house_record(home_id)
	if record.is_empty():
		return {}
	var beds: Array = Furnishings.records_in(Furnishings.place_of(record)).filter(
		func(f): return String(f.get("type", "")) in ["bed", "bed_double"])
	beds.sort_custom(func(a, b): return (0 if String(a["type"]) == "bed_double" else 1) < (0 if String(b["type"]) == "bed_double" else 1) \
		or ((String(a["type"]) == String(b["type"])) and int(a["id"]) < int(b["id"])))
	var slots: Array = []
	for b in beds:
		slots.append(b)
		if String(b["type"]) == "bed_double":
			slots.append(b)
	var order: Array = []
	var owner := String(Population.home_owners.get(home_id, ""))
	var members := Population.residents_of(home_id)
	if members.has(owner):
		order.append(owner)
		var p := Population.get_person(owner)
		if p and members.has(p.partner):
			order.append(p.partner)
	var rest := members.filter(func(id): return not order.has(id))
	rest.sort()
	order.append_array(rest)
	var i := order.find(person_id)
	return slots[i] if i >= 0 and i < slots.size() else {}


# --- Invitations ------------------------------------------------------------------------

## Why `villager` can't be invited to the player's house `home_id` now, or "".
func invite_reason(villager, home_id: String) -> String:
	var record := Population.house_record(home_id)
	if record.is_empty() or Population.is_given_house(record) or not home_available(home_id):
		return "Invite friends to a house of your own"
	if villager == null or villager.person == null or not villager.person.is_resident() or villager.is_leaving():
		return "They can't come"
	var hour := WorldClock.time_of_day
	if hour < INVITE_FROM or hour >= INVITE_UNTIL:
		return "It's too late to invite anyone (between %d:00 and %d:00)" % [int(INVITE_FROM), int(INVITE_UNTIL)]
	if invites.has(String(villager.data.id)):
		return "%s is already coming" % villager.data.display_name
	if villager.person.home == home_id:
		return "%s lives here" % villager.data.display_name
	return ""


func invite(villager, home_id: String) -> String:
	var why := invite_reason(villager, home_id)
	if why != "":
		return why
	invites[String(villager.data.id)] = {"home": home_id, "until": TaskSystem.absolute_hours() + INVITE_HOURS, "arrived": false}
	villager.current_activity = null
	villager._decision_timer = 0.0
	GameManager.notify("%s is on the way to your house." % villager.data.display_name)
	changed.emit()
	return ""


## An invitation turns today's plan into a visit (until it's over).
func override_activity(villager, desired: VillagerActivity) -> VillagerActivity:
	var id := String(villager.data.id)
	if not invites.has(id):
		return desired
	var inv: Dictionary = invites[id]
	if TaskSystem.absolute_hours() >= float(inv["until"]) or not home_available(String(inv["home"])):
		invites.erase(id)
		changed.emit()
		return desired
	var visit := VillagerActivity.new()
	visit.kind = &"visit"
	visit.location_id = String(inv["home"])
	visit.label = "Visiting you (you invited them)"
	visit.start_hour = -1.0
	return visit


# --- Coming home --------------------------------------------------------------------------

## A villager just went inside `home_id` (through the door, out of sight).
func arrived_inside(villager, home_id: String) -> void:
	var id := String(villager.data.id)
	if villager.person and villager.person.home == home_id:
		_thank_for_house(villager, home_id)
	if invites.has(id) and String(invites[id]["home"]) == home_id and not bool(invites[id]["arrived"]):
		invites[id]["arrived"] = true
		villager.mind.adjust_opinion(GameManager.PLAYER_ID, INVITE_AFFECTION, INVITE_AFFECTION * 0.5)
		villager.mind.record_interaction(GameManager.PLAYER_ID, "invited_home", WorldClock.day, WorldClock.time_of_day)
		GameManager.opinion_changed.emit(villager, villager.mind.get_affection(GameManager.PLAYER_ID), villager.mind.get_trust(GameManager.PLAYER_ID))
	if room_home != "" and home_id == room_home and is_house_home(home_id):
		admit(villager, true)


# --- Indoors (while the player is in a house) -------------------------------------------

func _on_player_entered(place: String) -> void:
	if not place.begins_with("house_"):
		return
	room_place = place
	room_home = "home_s" + place.substr(6)
	room_type = Furnishings.house_type(place)
	var residents_home: Array = []
	for villager in GameManager.villagers:
		if is_instance_valid(villager) and villager.state == Villager.State.INSIDE and villager.get_location_id() == room_home:
			admit(villager, false)
			residents_home.append(villager)
	_greet_player(residents_home)


func _on_player_left(_place: String) -> void:
	for villager in _agents.keys():
		if is_instance_valid(villager):
			_send_back_inside(villager)
	_agents.clear()
	_claims.clear()
	room_home = ""
	room_place = ""
	room_type = &""


## Puts `villager` in the rooms: at the front door (coming in) or already
## at what they're doing (they were home when you came in).
func admit(villager, from_door: bool) -> void:
	if villager.state != Villager.State.INSIDE:
		return
	villager.state = Villager.State.HOME
	villager.visible = true
	villager._collision.set_deferred("disabled", false)
	villager.interactable.enabled = true
	villager.model.set_detail(CharacterModel.Detail.FULL, true)
	var agent := {"path": PackedVector2Array(), "i": 0, "plan": {}, "timer": 0.0, "out": false}
	_agents[villager] = agent
	var entry := entry_point()
	var plan := choose_plan(villager)
	agent["plan"] = plan
	if from_door:
		_place(villager, entry)
		villager.rotation.y = PI
		_walk_to(villager, plan["stand"])
		if is_guest(villager):
			var line: String = INVITE_THANKS[_rng.randi_range(0, INVITE_THANKS.size() - 1)] if invites.has(String(villager.data.id)) \
				else GUEST_THANKS[_rng.randi_range(0, GUEST_THANKS.size() - 1)]
			villager.say(line)
			_host_welcomes(villager)
	else:
		_place(villager, plan["stand"])
		_start_doing(villager)


## Walks `villager` to the front door; there they step outside.
func walk_out(villager) -> void:
	if not _agents.has(villager):
		villager.exit_home()
		return
	var agent: Dictionary = _agents[villager]
	_release_claim(villager)
	_unpose(villager)
	agent["out"] = true
	agent["plan"] = {}
	_walk_to(villager, entry_point())


## Something new to do in the same house (woke up, now relaxing).
func replan(villager) -> void:
	if not _agents.has(villager):
		return
	_release_claim(villager)
	_unpose(villager)
	var plan := choose_plan(villager)
	_agents[villager]["plan"] = plan
	_walk_to(villager, plan["stand"])


## Takes `villager` out of the rooms at once (leaving the village, a task).
func release(villager, step_out: bool) -> void:
	_release_claim(villager)
	_agents.erase(villager)
	_unpose(villager)
	if step_out:
		villager.state = Villager.State.IDLE
		villager.visible = true
		villager._collision.set_deferred("disabled", false)
		villager.interactable.enabled = true
		villager._step_out_of(villager.get_location_id())


func _send_back_inside(villager) -> void:
	_release_claim(villager)
	_unpose(villager)
	var door := door_of(villager.get_location_id())
	if not door.is_empty():
		var step: Vector3 = door["step"]
		villager.global_position = VillageLayout.ground_point(step.x, step.z)
	if villager.state == Villager.State.HOME:
		villager.state = Villager.State.INSIDE
		villager.visible = false
		villager._collision.set_deferred("disabled", true)
		villager.interactable.enabled = false
	elif villager.state == Villager.State.INTERACTING:
		villager._state_before_interaction = Villager.State.INSIDE


func is_guest(villager) -> bool:
	return villager.person == null or villager.person.home != room_home


func people_inside() -> Array:
	return _agents.keys().filter(func(v): return is_instance_valid(v))


func entry_point() -> Vector2:
	var size: Vector2 = HouseDesigns.size_info(room_type)["inside"]
	return Vector2(0.0, size.y * 0.5 - 0.75)


func _place(villager, at: Vector2) -> void:
	villager.global_position = Interiors.ROOM_ORIGIN + Vector3(at.x, 0.0, at.y)


func _local(villager) -> Vector2:
	var p: Vector3 = villager.global_position - Interiors.ROOM_ORIGIN
	return Vector2(p.x, p.z)


func _process(delta: float) -> void:
	if room_home == "":
		return
	for villager in _agents.keys():
		if not is_instance_valid(villager):
			_agents.erase(villager)
			continue
		if villager.state != Villager.State.HOME or villager.is_reacting():
			continue
		_step(villager, _agents[villager], delta)
	_check_timer -= delta
	if _check_timer <= 0.0:
		_check_timer = 1.0
		_check_chats()


func _step(villager, agent: Dictionary, delta: float) -> void:
	var path: PackedVector2Array = agent["path"]
	var i: int = agent["i"]
	if i < path.size():
		var here := _local(villager)
		var to := path[i] - here
		var dist := to.length()
		if dist < ARRIVE:
			agent["i"] = i + 1
			return
		var step := minf(villager.data.walk_speed * WALK_SPEED_FACTOR * delta, dist)
		_place(villager, here + to / dist * step)
		villager._face_direction(Vector3(to.x, 0, to.y) / dist, delta)
		villager.model.set_animation(&"walk", villager.data.walk_speed * WALK_SPEED_FACTOR)
		if agent["i"] >= path.size() - 1 and dist - step < ARRIVE:
			agent["i"] = path.size()
			if bool(agent["out"]):
				_agents.erase(villager)
				villager.exit_home()
			else:
				_start_doing(villager)
		return
	_doing(villager, agent, delta)


func _walk_to(villager, target: Vector2) -> void:
	var agent: Dictionary = _agents[villager]
	agent["path"] = indoor_path(room_type, _local(villager), target)
	agent["i"] = 0


# --- What they do indoors ----------------------------------------------------------------

## Picks something to do: sleep in their bed at night; otherwise what suits
## them (the bookish read, the house-proud tidy and cook, the sociable chat
## or host, the quiet sit by themselves). Guests sit and chat.
## { kind, piece (FurniturePiece or null), stand: Vector2, look: Vector2, anim }
func choose_plan(villager) -> Dictionary:
	var person: Person = villager.person
	var asleep: bool = villager.current_activity != null and villager.current_activity.is_sleep()
	if asleep and not is_guest(villager):
		var bed := bed_for(String(villager.data.id), room_home)
		var piece := Furnishings.instance.body_of(bed) if not bed.is_empty() and Furnishings.instance else null
		if piece:
			return _furniture_plan(villager, "sleep", piece)
	var options: Array = []  # [weight, kind, piece]
	var social := person.trait_weight("extraversion") if person else 0.5
	var open := person.trait_weight("openness") if person else 0.5
	var tidy := person.trait_weight("conscientiousness") if person else 0.5
	var hour := WorldClock.time_of_day
	for piece in _pieces():
		if _claims.has(int(piece.record["id"])) and _claims[int(piece.record["id"])] != villager:
			continue
		var t := String(piece.type)
		if t in SEATS:
			options.append([1.0 + (1.0 - social) + (1.5 if is_guest(villager) else 0.0), "sit", piece])
		elif t == "bookshelf" and not is_guest(villager):
			options.append([0.4 + open * 2.0, "read", piece])
		elif t in ["chest", "wardrobe", "crate", "barrel"] and not is_guest(villager):
			options.append([0.2 + tidy * 1.2, "tidy", piece])
		elif t in ["lamp", "plant", "rug"]:
			options.append([0.4, "relax", piece])
	if not is_guest(villager) and _hearth() != Vector2.INF:
		options.append([0.3 + tidy * (1.6 if hour >= 16.5 and hour < 20.0 else 0.6), "cook", null])
	var others := people_inside().filter(func(v): return v != villager and _agents.has(v) and not (_agents[v]["plan"] as Dictionary).is_empty() \
		and String(_agents[v]["plan"].get("kind", "")) != "sleep")
	if not others.is_empty():
		options.append([0.5 + social * 2.5 + (2.0 if is_guest(villager) else 0.0), "chat", null])
	if options.is_empty():
		return {"kind": "relax", "piece": null, "stand": _free_spot_near(entry_point() + Vector2(0, -1.2), villager), "look": entry_point(), "anim": &"idle"}
	var total := 0.0
	for o in options:
		total += float(o[0])
	var roll := _rng.randf() * total
	for o in options:
		roll -= float(o[0])
		if roll <= 0.0:
			return _plan_for(villager, String(o[1]), o[2], others)
	return _plan_for(villager, String(options[0][1]), options[0][2], others)


func _plan_for(villager, kind: String, piece, others: Array) -> Dictionary:
	match kind:
		"cook":
			var h := _hearth()
			var size: Vector2 = HouseDesigns.size_info(room_type)["inside"]
			var stand := _free_spot_near(h + (Vector2(0, 1.1) if h.y < 0.0 else Vector2(1.1 if h.x < 0.0 else -1.1, 0)), villager)
			return {"kind": "cook", "piece": null, "stand": stand, "look": h, "anim": &"work", "size": size}
		"chat":
			var friend = others[_rng.randi_range(0, others.size() - 1)]
			var near := _local(friend)
			var away := (_local(villager) - near)
			away = away.normalized() if away.length() > 0.1 else Vector2(1, 0)
			var stand := _free_spot_near(near + away * 1.1, villager)
			return {"kind": "chat", "piece": null, "stand": stand, "look": near, "anim": &"talk", "with": friend}
	return _furniture_plan(villager, kind, piece)


func _furniture_plan(villager, kind: String, piece) -> Dictionary:
	var anim: StringName = {"sleep": &"sleep", "sit": &"sit", "read": &"idle", "tidy": &"gather", "relax": &"idle"}.get(kind, &"idle")
	var stand := approach_of(piece)
	var look := Vector2(piece.global_position.x - Interiors.ROOM_ORIGIN.x, piece.global_position.z - Interiors.ROOM_ORIGIN.z)
	_claims[int(piece.record["id"])] = villager
	return {"kind": kind, "piece": piece, "stand": stand, "look": look, "anim": anim}


## A clear floor spot beside `piece` (room space), in the same room.
func approach_of(piece) -> Vector2:
	var size: Vector2 = piece.info.get("size", Vector2.ONE)
	var room := HouseInterior.room_at(room_type, Vector2(piece.position.x, piece.position.z))
	var candidates := [Vector3(0, 0, size.y * 0.5 + 0.45), Vector3(size.x * 0.5 + 0.45, 0, 0), Vector3(-size.x * 0.5 - 0.45, 0, 0), Vector3(0, 0, -size.y * 0.5 - 0.45)]
	for c in candidates:
		var world: Vector3 = piece.global_transform * c
		var local := Vector2(world.x - Interiors.ROOM_ORIGIN.x, world.z - Interiors.ROOM_ORIGIN.z)
		if walkable(local) and (room == "" or HouseInterior.room_at(room_type, local) == room):
			return local
	return _free_spot_near(Vector2(piece.position.x, piece.position.z))


## Can someone stand here (inside the rooms, clear of walls and furniture)?
func walkable(at: Vector2) -> bool:
	if Furnishings.instance == null:
		return true
	var size: Vector2 = HouseDesigns.size_info(room_type)["inside"]
	if absf(at.x) > size.x * 0.5 - 0.35 or absf(at.y) > size.y * 0.5 - 0.35:
		return false
	for r in HouseInterior.blocked(room_type):
		# The entrance and doorway clearings are for walking through.
		if (r as Rect2).size.x <= 1.9 and (r as Rect2).size.y <= 1.9:
			continue
		if (r as Rect2).grow(0.2).has_point(at):
			return false
	for f in Furnishings.records_in(room_place):
		if bool(FurnitureCatalog.info(StringName(String(f["type"]))).get("flat", false)):
			continue
		var p: Array = f["pos"]
		var fs := FurnitureCatalog.footprint(StringName(String(f["type"])), float(f.get("yaw", 0.0)))
		if Rect2(Vector2(float(p[0]), float(p[2])) - fs * 0.5, fs).grow(0.15).has_point(at):
			return false
	return true


## The nearest clear spot to `at` that isn't where someone else (other than
## `who`) is standing or heading.
func _free_spot_near(at: Vector2, who = null) -> Vector2:
	if walkable(at) and not _crowded(at, who):
		return at
	for ring in range(1, 14):
		for k in 8:
			var a := k * TAU / 8.0
			var p := at + Vector2(cos(a), sin(a)) * ring * 0.3
			if walkable(p) and not _crowded(p, who):
				return p
	return entry_point()


func _crowded(at: Vector2, who) -> bool:
	for v in _agents:
		if v == who or not is_instance_valid(v):
			continue
		if _local(v).distance_to(at) < 0.8:
			return true
		var stand = (_agents[v]["plan"] as Dictionary).get("stand")
		if stand is Vector2 and (stand as Vector2).distance_to(at) < 0.8:
			return true
	return false


func _pieces() -> Array:
	var out: Array = []
	if Furnishings.instance == null:
		return out
	for f in Furnishings.records_in(room_place):
		var piece = Furnishings.instance.body_of(f)
		if piece:
			out.append(piece)
	return out


func _hearth() -> Vector2:
	var h: Array = HouseInterior.layout(room_type)["hearth"]
	return Vector2(float(h[0]), float(h[1]))


func _start_doing(villager) -> void:
	var agent: Dictionary = _agents[villager]
	var plan: Dictionary = agent["plan"]
	if plan.is_empty():
		plan = choose_plan(villager)
		agent["plan"] = plan
	agent["timer"] = _rng.randf_range(DO_MIN, DO_MAX)
	var piece = plan.get("piece")
	match String(plan["kind"]):
		"sleep":
			var mattress: Vector3 = piece.global_transform * FurnitureCatalog.mattress(piece.type)
			villager.global_position = Vector3(mattress.x, Interiors.ROOM_ORIGIN.y, mattress.z)
			# Lying on their back puts the head behind them: head on the pillow.
			villager.rotation.y = piece.global_rotation.y
			villager.model.position = Vector3(0, mattress.y - Interiors.ROOM_ORIGIN.y, 0)
		"sit":
			var s: Array = FurnitureCatalog.seat(piece.type)
			var seat: Vector3 = piece.global_transform * (s[0] as Vector3)
			villager.global_position = Vector3(seat.x, Interiors.ROOM_ORIGIN.y, seat.z)
			villager.rotation.y = piece.global_rotation.y
			villager.model.position = villager.model.seat_pose(float(s[1]))


func _doing(villager, agent: Dictionary, delta: float) -> void:
	var plan: Dictionary = agent["plan"]
	if plan.is_empty():
		_start_doing(villager)
		return
	var kind := String(plan["kind"])
	var anim: StringName = plan["anim"]
	if kind not in ["sleep", "sit"]:
		var look: Vector2 = plan["look"]
		if kind == "chat" and is_instance_valid(plan.get("with")):
			look = _local(plan["with"])
		villager._face_towards(Interiors.ROOM_ORIGIN + Vector3(look.x, 0, look.y), delta)
	if kind == "chat" or (kind == "sit" and bool(plan.get("talking", false))):
		var talking := int(villager._alive_time / 3.5 + hash(String(villager.data.id))) % 2 == 0
		if kind == "sit":
			villager.model.set_talking(talking)
		else:
			anim = &"talk" if talking else &"idle"
	villager.model.set_animation(anim)
	if kind == "sleep":
		return  # until morning (their activity changes and they walk out)
	agent["timer"] = float(agent["timer"]) - delta
	if float(agent["timer"]) <= 0.0:
		_release_claim(villager)
		_unpose(villager)
		agent["plan"] = choose_plan(villager)
		_walk_to(villager, agent["plan"]["stand"])


func _unpose(villager) -> void:
	if villager.model.position != Vector3.ZERO:
		var plan: Dictionary = _agents.get(villager, {}).get("plan", {})
		var piece = plan.get("piece")
		if piece and is_instance_valid(piece):
			var stand := approach_of(piece)
			_place(villager, stand)
		villager.model.position = Vector3.ZERO
		villager.model.set_talking(false)


func _release_claim(villager) -> void:
	for id in _claims.keys():
		if _claims[id] == villager:
			_claims.erase(id)


# --- Talking at home ---------------------------------------------------------------------

func _line(bank: Array) -> String:
	var options := bank.filter(func(l): return not _recent_lines.has(l))
	if options.is_empty():
		options = bank
	var line: String = options[_rng.randi_range(0, options.size() - 1)]
	_recent_lines.append(line)
	if _recent_lines.size() > 8:
		_recent_lines.pop_front()
	return line


## The household greets the player (once per visit), friendlier the better
## they know you; a friend you visit likes you a little more (once a day).
func _greet_player(present: Array) -> void:
	var player = GameManager.player
	if player == null:
		return
	var greeted := false
	for villager in present:
		if not _agents.has(villager) or String(_agents[villager]["plan"].get("kind", "")) == "sleep":
			continue
		var affection: float = villager.mind.get_affection(GameManager.PLAYER_ID)
		var mood := "close" if affection >= 40.0 else ("friendly" if affection >= 10.0 else ("wary" if affection <= -15.0 else "neutral"))
		if not greeted:
			villager.react(&"wave" if mood != "wary" else &"idle", 2.2, player.global_position, _line(WELCOME_PLAYER[mood]),
				&"happy" if mood in ["close", "friendly"] else &"")
			greeted = true
		var id := String(villager.data.id)
		if int(visited.get(id, -1)) != WorldClock.day and not is_guest(villager) and mood != "wary":
			visited[id] = WorldClock.day
			villager.mind.adjust_opinion(GameManager.PLAYER_ID, VISIT_AFFECTION, VISIT_AFFECTION * 0.5)
			villager.mind.record_interaction(GameManager.PLAYER_ID, "visited_home", WorldClock.day, WorldClock.time_of_day)


## Whoever lives here comes over to welcome a guest walking in.
func _host_welcomes(guest) -> void:
	for villager in people_inside():
		if villager == guest or is_guest(villager) or not _agents.has(villager):
			continue
		var plan: Dictionary = _agents[villager]["plan"]
		if String(plan.get("kind", "")) == "sleep":
			continue
		villager.react(&"wave", 2.0, guest.global_position, _line(WELCOME_GUEST), &"happy")
		_release_claim(villager)
		_unpose(villager)
		_agents[villager]["plan"] = {"kind": "chat", "piece": null, "stand": _free_spot_near(entry_point() + Vector2(1.1, -1.1), villager),
			"look": entry_point(), "anim": &"talk", "with": guest}
		_walk_to(villager, _agents[villager]["plan"]["stand"])
		return


## Now and then someone chatting says something out loud (never the same
## line twice in a row in this house), and people who spend time together
## at home grow closer.
func _check_chats() -> void:
	for villager in people_inside():
		if not _agents.has(villager):
			continue
		var plan: Dictionary = _agents[villager]["plan"]
		var chatting := String(plan.get("kind", "")) == "chat" or (String(plan.get("kind", "")) == "sit" and _seated_together(villager))
		if not chatting:
			continue
		if plan.get("kind") == "sit":
			plan["talking"] = true
		if _rng.randf() < 0.12 and Time.get_ticks_msec() - villager.last_spoke_msec > 6000:
			villager.say(_line(HOME_CHAT))
			villager.last_spoke_msec = Time.get_ticks_msec()


func _seated_together(villager) -> bool:
	for other in people_inside():
		if other != villager and _agents.has(other) and String(_agents[other]["plan"].get("kind", "")) in ["sit", "chat"] \
				and other.global_position.distance_to(villager.global_position) < 3.0:
			return true
	return false


# --- Paths through the rooms -----------------------------------------------------------

## A walk from `from` to `to` (room space) through doorways, never through a
## wall: straight across a room (rooms are rectangles), and from room to room
## by the doorway between them.
static func indoor_path(type: StringName, from: Vector2, to: Vector2) -> PackedVector2Array:
	var l := HouseInterior.layout(type)
	var rooms: Array = l["rooms"]
	var a := _room_index(rooms, from)
	var b := _room_index(rooms, to)
	var out := PackedVector2Array()
	if a == b or a < 0 or b < 0:
		out.append(to)
		return out
	# Doorways: [room_a, room_b, side_a, centre, side_b]
	var doors: Array = []
	for w in l["walls"]:
		var p := Vector2(float(w[0]), float(w[1]))
		var q := Vector2(float(w[2]), float(w[3]))
		var horizontal := absf(q.x - p.x) > absf(q.y - p.y)
		for c in w[4]:
			var centre := Vector2(float(c), p.y) if horizontal else Vector2(p.x, float(c))
			var normal := Vector2(0, 1) if horizontal else Vector2(1, 0)
			var s1 := centre + normal * 0.7
			var s2 := centre - normal * 0.7
			var r1 := _room_index(rooms, s1)
			var r2 := _room_index(rooms, s2)
			if r1 >= 0 and r2 >= 0 and r1 != r2:
				doors.append([r1, r2, s1, centre, s2])
	# Breadth-first through rooms.
	var prev := {a: null}
	var queue := [a]
	while not queue.is_empty():
		var r: int = queue.pop_front()
		if r == b:
			break
		for d in doors:
			for pair in [[d[0], d[1], d[2], d[4]], [d[1], d[0], d[4], d[2]]]:
				if int(pair[0]) == r and not prev.has(int(pair[1])):
					prev[int(pair[1])] = [r, pair[2], d[3], pair[3]]
					queue.append(int(pair[1]))
	if not prev.has(b):
		out.append(to)
		return out
	var steps: Array = []
	var at := b
	while prev[at] != null:
		var link: Array = prev[at]
		steps.push_front([link[1], link[2], link[3]])
		at = int(link[0])
	for s in steps:
		out.append(s[0])
		out.append(s[1])
		out.append(s[2])
	out.append(to)
	return out


static func _room_index(rooms: Array, at: Vector2) -> int:
	for i in rooms.size():
		if (rooms[i][1] as Rect2).grow(0.01).has_point(at):
			return i
	# Just outside every room (e.g. on a wall line): the nearest one.
	var best := -1
	var best_d := INF
	for i in rooms.size():
		var r: Rect2 = rooms[i][1]
		var c := Vector2(clampf(at.x, r.position.x, r.end.x), clampf(at.y, r.position.y, r.end.y))
		if c.distance_to(at) < best_d:
			best_d = c.distance_to(at)
			best = i
	return best


# --- Save -------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"invites": invites.duplicate(true), "visited": visited.duplicate()}


func from_dict(data: Dictionary) -> void:
	invites.clear()
	visited.clear()
	var inv = data.get("invites", {})
	if inv is Dictionary:
		for id in inv:
			var v = inv[id]
			if v is Dictionary and v.has("home") and v.has("until"):
				invites[String(id)] = {"home": String(v["home"]), "until": float(v["until"]), "arrived": bool(v.get("arrived", false))}
	var vis = data.get("visited", {})
	if vis is Dictionary:
		for id in vis:
			visited[String(id)] = int(vis[id])
