class_name PopulationDirector
extends Node
## Gives the people in Population a body in the world and moves them through
## village life: travellers walking in over the bridge, the player welcoming
## or turning them away, newcomers moving into homes, and villagers who
## decide to leave walking off down the road.
##
## Never spawns several people at once: characters are built one by one on a
## worker thread (CharacterBuildQueue) and appear as they become ready.

static var instance: PopulationDirector

## Off the map to the east, past the camp: where travellers come from.
const ENTRY_POINT := Vector3(60.0, 0.0, 1.0)
## First traveller arrives on this day; later ones by chance.
const FIRST_ARRIVAL_DAY := 2
## Hours of the day when a traveller may turn up.
const ARRIVAL_HOURS := Vector2i(9, 15)
## A traveller nobody speaks to moves on after waiting this many days.
const VISITOR_PATIENCE_DAYS := 2

## Tests switch this off so the population only changes when they say so.
static var auto_arrivals: bool = true

var navigation: VillageNavigation
var villagers_root: Node3D
var build_queue: CharacterBuildQueue
var rng := RandomNumberGenerator.new()

var _arrival_hour: int = -1
var _arrival_day: int = -1
## People waiting for a body (staggered spawning after a load).
var _spawning: Dictionary = {}


func _ready() -> void:
	name = "PopulationDirector"
	instance = self
	rng.randomize()
	build_queue = CharacterBuildQueue.new()
	build_queue.name = "CharacterBuildQueue"
	add_child(build_queue)
	WorldClock.hour_changed.connect(_on_hour_changed)
	WorldClock.day_changed.connect(_on_day_changed)
	Population.person_changed.connect(_on_person_changed)
	if StructureManager.instance:
		StructureManager.instance.structure_completed.connect(_on_structure_completed)
	_register_cottage_homes()
	_link_founders()
	_spawn_saved_people()
	_plan_arrival()


func _exit_tree() -> void:
	if instance == self:
		instance = null


func get_villager(person: Person):
	return GameManager.get_villager(StringName(person.id))


# --- Setup -------------------------------------------------------------------------------

func _link_founders() -> void:
	for villager in GameManager.villagers:
		var person := Population.get_person(String(villager.get_villager_id()))
		if person:
			villager.person = person


## Residents (and a waiting traveller) from a save get their bodies back, one
## at a time.
func _spawn_saved_people() -> void:
	for person: Person in Population.residents(true):
		if person.founder or GameManager.get_villager(StringName(person.id)) != null:
			continue
		_spawn(person, false)


func _register_cottage_homes() -> void:
	if StructureManager.instance == null:
		return
	for structure in StructureManager.instance.structures():
		if structure.get_type() == &"cottage" and structure.is_complete():
			_register_home(structure)


func _register_home(structure) -> void:
	var door: Vector3 = structure.door_point()
	VillageLayout.register_location(structure.home_id(), [door], [structure.global_position], true,
		"the cottage by %s" % ("the woods" if door.x < 0.0 else "the fields"))


func _on_structure_completed(structure) -> void:
	if structure.get_type() != &"cottage":
		return
	_register_home(structure)
	Population.housing_changed.emit()
	var moved := Population.rehouse_campers()
	if not moved.is_empty():
		GameManager.notify("%s moved out of the camp into the new cottage." % _names(moved))


# --- Bodies ----------------------------------------------------------------------------

## Builds this person's character on the worker thread, then spawns them.
## Travellers appear at the edge of the map and walk in; everyone else
## appears where their timetable says they should be.
func _spawn(person: Person, walk_in: bool) -> void:
	if _spawning.has(person.id):
		return
	_spawning[person.id] = true
	var look := AppearanceCodec.from_dict(person.appearance)
	build_queue.request(look, _on_meshes_ready.bind(person, walk_in))


func _on_meshes_ready(meshes: Dictionary, person: Person, walk_in: bool) -> void:
	_spawning.erase(person.id)
	if not person.is_present() or GameManager.get_villager(StringName(person.id)) != null:
		return
	var villager := Villager.new()
	villager.person = person
	villager.data = PersonGenerator.make_visitor_data(person) if person.status == Person.STATUS_VISITOR else PersonGenerator.make_data(person)
	villager.navigation = navigation
	villager.prebuilt_meshes = meshes
	if walk_in:
		villager.spawn_at = ENTRY_POINT + Vector3(0, 0, rng.randf_range(-2.0, 2.0))
	villager.departed.connect(_on_villager_departed)
	villagers_root.add_child(villager)
	var saved := SaveService.villager_state(person.id)
	if not saved.is_empty():
		villager.apply_save_data(saved)


func is_spawning() -> bool:
	return not _spawning.is_empty() or build_queue.is_busy()


# --- Arrivals ----------------------------------------------------------------------------

func _plan_arrival() -> void:
	_arrival_day = WorldClock.day
	_arrival_hour = rng.randi_range(ARRIVAL_HOURS.x, ARRIVAL_HOURS.y)


func _on_day_changed(_day: int) -> void:
	Population.advance_day(rng)
	_plan_arrival()
	for person: Person in Population.visitors():
		if WorldClock.day - person.arrived_day >= VISITOR_PATIENCE_DAYS:
			_visitor_moves_on(person)


func _on_hour_changed(hour: int) -> void:
	if hour == 7:
		_send_off_leavers()
	if auto_arrivals and WorldClock.day == _arrival_day and hour == _arrival_hour:
		if rng.randf() < arrival_chance():
			bring_traveller()


## How likely someone turns up today. A free bed, a growing reputation and
## invitations from residents all help; a full village, a waiting traveller
## or a crowded camp keep people away.
func arrival_chance() -> float:
	if WorldClock.day < FIRST_ARRIVAL_DAY or not Population.has_room_for_more():
		return 0.0
	if not Population.visitors().is_empty() or _spawning.size() > 0:
		return 0.0
	if not Population.invitations.is_empty():
		return 1.0
	if WorldClock.day == FIRST_ARRIVAL_DAY:
		return 1.0
	var housing := Population.housing_summary()
	var camp_free := Population.CAMP_CAPACITY - int(housing["camping"])
	if int(housing["free"]) <= 0 and camp_free <= 0:
		return 0.0
	var population := Population.count()
	var chance := 0.65 if population < 12 else 0.45 if population < 25 else 0.3
	if int(housing["free"]) <= 0:
		chance *= 0.4
	return chance


## Generates a traveller (or an invited relative) and sends them walking in.
func bring_traveller() -> Person:
	var relative: Person = null
	var relation := ""
	if not Population.invitations.is_empty():
		var invitation: Dictionary = Population.invitations.pop_front()
		relative = Population.get_person(String(invitation["inviter"]))
		relation = String(invitation["relation"])
		if relative == null or not relative.is_resident():
			relative = null
			relation = ""
	var person := PersonGenerator.create(rng, Population.new_id(), Population.taken_first_names(),
		Population.appearances(), relative, relation)
	Population.add(person)
	Population.log_event("visitor", "%s, a %s, came over the bridge." % [person.full_name(), Professions.label(person.profession).to_lower()], [person.id])
	_spawn(person, true)
	if relative:
		GameManager.notify("%s's %s %s is walking over the bridge." % [relative.first_name, relation, person.first_name])
	else:
		GameManager.notify("A traveller is crossing the bridge: %s, a %s." % [person.first_name, Professions.label(person.profession).to_lower()])
	return person


## Adds a newcomer who already lives here (no walk-in, no welcome), placed
## where their timetable says. For tests, tools and future scripted events.
func settle_newcomer() -> Person:
	var person := PersonGenerator.create(rng, Population.new_id(), Population.taken_first_names(), Population.appearances())
	Population.add(person)
	Population.make_resident(person)
	_spawn(person, false)
	return person


func queue_invitation(inviter: Person, relation: String) -> void:
	inviter.has_invited = true
	Population.invitations.append({"inviter": inviter.id, "relation": relation})
	Population.log_event("invitation", "%s sent for their %s." % [inviter.first_name, relation], [inviter.id])
	GameManager.notify("%s has written to their %s, asking them to come and live here." % [inviter.first_name, relation])


func pending_invitations() -> int:
	return Population.invitations.size()


# --- Welcome or turn away ---------------------------------------------------------------

## The player said yes: they move in and start living by their timetable.
func welcome(villager) -> Array[String]:
	var person: Person = villager.person
	Population.make_resident(person)
	villager.become_resident(PersonGenerator.make_data(person))
	villager.mind.adjust_opinion(GameManager.PLAYER_ID, 25.0, 15.0)
	villager.mind.memory.add("deed", GameManager.PLAYER_ID, WorldClock.day, WorldClock.time_of_day,
		DialogueService.pack_deed("welcomed me into the village", 25.0))
	_neighbours_react(person, true)
	if person.relatives.size() > 0:
		for id in person.relatives:
			var kin := Population.get_person(String(id))
			var kin_villager = GameManager.get_villager(StringName(String(id))) if kin else null
			if kin_villager:
				kin_villager.mind.adjust_opinion(GameManager.PLAYER_ID, 15.0, 10.0)
	var home := Population.homes().filter(func(h): return h["id"] == person.home)
	var where := "I'll put up a tent at the camp until there's a proper bed." if person.home == Population.CAMP_ID \
		else "%s, you say? I'll go and find my bed." % (String(home[0]["label"]) if not home.is_empty() else "My new home")
	GameManager.notify("%s joined the village. Population: %d." % [person.first_name, Population.count()])
	return ["[laughing]Thank you! You won't regret it." if person.trait_weight("extraversion") > 0.5 else "[happy]Thank you. Truly.", "[happy]" + where]


## The player said no: they leave, and the villagers have opinions about it.
func turn_away(villager) -> Array[String]:
	var person: Person = villager.person
	Population.reject(person)
	_neighbours_react(person, false)
	villager.leave(ENTRY_POINT)
	return ["[sad]I understand. I'll be on my way, then." if person.trait_weight("agreeableness") > 0.4 else "[angry]Fine. Your loss."]


## Kind villagers approve of a welcome and are hurt by a refusal; wary ones
## feel the opposite, a little. Relatives take a refusal personally.
func _neighbours_react(newcomer: Person, welcomed: bool) -> void:
	for villager in GameManager.villagers:
		var other: Person = villager.person
		if other == null or other == newcomer or not other.is_resident():
			continue
		var kind := other.trait_weight("agreeableness") - 0.45
		var delta := kind * 10.0 if welcomed else -kind * 12.0
		if newcomer.relatives.has(other.id):
			delta = 15.0 if welcomed else -30.0
		if absf(delta) < 1.0:
			continue
		villager.mind.adjust_opinion(GameManager.PLAYER_ID, delta, delta * 0.5)
		villager.mind.memory.add("deed", GameManager.PLAYER_ID, WorldClock.day, WorldClock.time_of_day,
			DialogueService.pack_deed(("welcomed %s into the village" if welcomed else "turned %s away") % newcomer.first_name, delta))


func _visitor_moves_on(person: Person) -> void:
	person.status = Person.STATUS_LEFT
	person.departed_day = WorldClock.day
	Population.log_event("moved_on", "%s waited, but nobody spoke to them, so they moved on." % person.full_name(), [person.id])
	var villager = get_villager(person)
	if villager:
		villager.leave(ENTRY_POINT)
	GameManager.notify("%s gave up waiting and left the village." % person.first_name)


# --- Leaving ---------------------------------------------------------------------------

## People who decided to go set off in the morning.
func _send_off_leavers() -> void:
	for person: Person in Population.residents():
		if person.leaving and not person.founder:
			send_away(person)


func send_away(person: Person) -> void:
	Population.depart(person)
	var villager = get_villager(person)
	if villager:
		villager.leave(ENTRY_POINT)
	GameManager.notify("%s packed their things and left the village." % person.first_name)


func _on_villager_departed(villager) -> void:
	# The record stays in Population (history, family trees).
	if GameManager.selected_villager == villager:
		GameManager.select_villager(null)


func _on_person_changed(person: Person) -> void:
	var villager = get_villager(person)
	if villager and person.is_resident() and not villager.is_visitor():
		villager.set_home(person.home if person.home != "" else Population.CAMP_ID)


static func _names(people_list: Array) -> String:
	var names: Array = people_list.map(func(p: Person): return p.first_name)
	if names.size() <= 1:
		return "".join(names)
	return "%s and %s" % [", ".join(names.slice(0, names.size() - 1)), names[-1]]
