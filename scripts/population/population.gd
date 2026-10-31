extends Node
## Everyone who has ever lived in the village, and the rules of village life
## that don't need a 3D body: homes, life stages, families, statistics and the
## history of arrivals, departures, births and deaths.
##
## PopulationDirector (a scene node) gives people bodies, brings travellers
## in and lets them go; SocialLife runs friendships and decisions. Both talk
## to this autoload, which saves with the game.

signal person_added(person: Person)
signal person_changed(person: Person)
## reason: "left", "rejected", "died"
signal person_removed(person: Person, reason: String)
signal event_logged(event: Dictionary)
signal housing_changed

## Soft cap for affordable phones: no more travellers once this many live here.
const MAX_POPULATION := 50
const FOUNDER_HOME_CAPACITY := 2
const COTTAGE_CAPACITY := 4
## Tents by the bridge: shelter, not a home.
const CAMP_ID := "camp"
const CAMP_CAPACITY := 10
## Births need child-sized 3D characters, which don't exist yet. The family
## logic below works (and is tested); the village just doesn't have babies
## until this is switched on.
const BIRTHS_ENABLED := false
## Founders are protected from old age until generations are playable.
const FOUNDERS_AGE_SAFELY := true

var people: Dictionary = {}  # id -> Person
var events: Array = []       # { day, type, text, ids }
var counters := {"arrivals": 0, "departures": 0, "rejected": 0, "births": 0, "deaths": 0, "partnerships": 0, "marriages": 0}
## home id -> person id who owns it (passed on by inheritance).
var home_owners: Dictionary = {}
var next_id: int = 1
## Relatives and friends residents have sent for: { inviter, relation }.
var invitations: Array = []


func reset() -> void:
	people.clear()
	events.clear()
	home_owners.clear()
	invitations.clear()
	for key in counters:
		counters[key] = 0
	next_id = 1


func new_id() -> String:
	var id := "p%d" % next_id
	next_id += 1
	return id


func get_person(id: String) -> Person:
	return people.get(id)


func add(person: Person) -> void:
	people[person.id] = person
	person_added.emit(person)


## People living here now (residents), optionally including visitors.
func residents(include_visitors: bool = false) -> Array:
	var out: Array = []
	for person: Person in people.values():
		if person.status == Person.STATUS_RESIDENT or (include_visitors and person.status == Person.STATUS_VISITOR):
			out.append(person)
	return out


func visitors() -> Array:
	return people.values().filter(func(p: Person): return p.status == Person.STATUS_VISITOR)


func count() -> int:
	return residents().size()


func has_room_for_more() -> bool:
	return residents(true).size() < MAX_POPULATION


## First names in use by people living here (lower case), so newcomers never
## share one.
func taken_first_names() -> Dictionary:
	var out := {}
	for person: Person in residents(true):
		out[person.first_name.to_lower()] = true
	return out


func appearances() -> Array:
	var out: Array = []
	for person: Person in residents(true):
		if not person.appearance.is_empty():
			out.append(AppearanceCodec.from_dict(person.appearance))
	return out


# --- Founders ---------------------------------------------------------------------------

## Makes sure the five founders have life records (new game) without touching
## records loaded from a save.
func ensure_founders(founders: Array) -> void:
	for data: VillagerData in founders:
		var id := String(data.id)
		if people.has(id):
			continue
		var p := Person.new()
		p.id = id
		p.first_name = data.display_name
		p.family_name = ""
		p.sex = "male" if id in ["elias", "tomas"] else "female"
		p.birth_day = 1 - data.age * Person.YEAR_DAYS
		p.profession = _founder_profession(id)
		p.traits = data.traits
		p.personality = data.personality.duplicate()
		p.biography = data.biography
		p.appearance = AppearanceCodec.to_dict(data.appearance)
		p.status = Person.STATUS_RESIDENT
		p.founder = true
		p.origin = "founder"
		p.data_path = data.resource_path
		p.home = data.home_location
		p.arrived_day = 1
		p.happiness = 70.0
		p.skills = {String(Professions.info(p.profession)["skill"]): 0.85}
		p.ambition = {"id": "see_growth", "text": "see this place grow into a proper town", "progress": 0.0, "done": false}
		people[id] = p
		home_owners[p.home] = id


static func _founder_profession(id: String) -> String:
	match id:
		"mara":
			return "builder"
		"elias":
			return "farmer"
		"nia":
			return "herbalist"
		"tomas":
			return "craftsman"
	return "trader"


# --- Housing ----------------------------------------------------------------------------

## Every home with its capacity and who lives there. The camp comes last.
func homes() -> Array:
	var out: Array = []
	for owner in VillageLayout.HOUSE_OWNERS:
		out.append({"id": "home_" + owner, "label": "%s's house" % owner.capitalize(), "capacity": FOUNDER_HOME_CAPACITY, "kind": "founder"})
	for record: Dictionary in GameState.structures:
		if String(record.get("type", "")) == "cottage" and bool(record.get("complete", false)):
			out.append({"id": cottage_home_id(record), "label": "Cottage %d" % int(record["uid"]), "capacity": COTTAGE_CAPACITY, "kind": "cottage"})
	out.append({"id": CAMP_ID, "label": "the camp", "capacity": CAMP_CAPACITY, "kind": "camp"})
	for home: Dictionary in out:
		home["residents"] = residents_of(String(home["id"]))
	return out


static func cottage_home_id(record: Dictionary) -> String:
	return "home_s%d" % int(record["uid"])


func residents_of(home_id: String) -> Array:
	var out: Array = []
	for person: Person in residents():
		if person.home == home_id:
			out.append(person.id)
	return out


## Beds in real homes (not the camp): { capacity, used, free }.
func housing_summary() -> Dictionary:
	var capacity := 0
	var used := 0
	for home: Dictionary in homes():
		if String(home["kind"]) == "camp":
			continue
		capacity += int(home["capacity"])
		used += (home["residents"] as Array).size()
	return {"capacity": capacity, "used": used, "free": capacity - used, "camping": residents_of(CAMP_ID).size()}


## Finds someone a place to live: with their partner or family if there's
## room, otherwise the emptiest cottage, a founder's spare room, then the camp.
func assign_home(person: Person) -> String:
	var options := homes()
	var preferred: Array = []
	if person.partner != "" and get_person(person.partner):
		preferred.append(get_person(person.partner).home)
	for id in person.relatives:
		if get_person(String(id)):
			preferred.append(get_person(String(id)).home)
	for parent in person.parents:
		if get_person(String(parent)):
			preferred.append(get_person(String(parent)).home)
	for home_id in preferred:
		for home: Dictionary in options:
			if home["id"] == home_id and home["kind"] != "camp" and _has_space(home, person):
				return _move_in(person, String(home_id))
	var best := ""
	var best_free := 0
	for kind in ["cottage", "founder"]:
		for home: Dictionary in options:
			if home["kind"] != kind:
				continue
			var free := int(home["capacity"]) - _occupants_excluding(home, person)
			if free > best_free:
				best_free = free
				best = String(home["id"])
		if best != "":
			return _move_in(person, best)
	return _move_in(person, CAMP_ID)


func _occupants_excluding(home: Dictionary, person: Person) -> int:
	var residents_list: Array = home["residents"]
	return residents_list.size() - (1 if residents_list.has(person.id) else 0)


func _has_space(home: Dictionary, person: Person) -> bool:
	return _occupants_excluding(home, person) < int(home["capacity"])


func _move_in(person: Person, home_id: String) -> String:
	var changed := person.home != home_id
	person.home = home_id
	if home_id != CAMP_ID and not home_owners.has(home_id):
		home_owners[home_id] = person.id
	if changed:
		person_changed.emit(person)
		housing_changed.emit()
	return home_id


## Moves campers into real homes when a cottage is finished.
func rehouse_campers() -> Array:
	var moved: Array = []
	for person: Person in residents():
		if person.home == CAMP_ID or person.home == "":
			var home := assign_home(person)
			if home != CAMP_ID:
				moved.append(person)
	return moved


# --- Life stages and statistics ----------------------------------------------------------

func stats() -> Dictionary:
	var stages := {Person.STAGE_CHILD: 0, Person.STAGE_TEEN: 0, Person.STAGE_ADULT: 0, Person.STAGE_ELDER: 0}
	var jobs := {}
	var happiness := 0.0
	var living := residents()
	for person: Person in living:
		stages[person.life_stage()] += 1
		var job := Professions.label(person.profession)
		jobs[job] = int(jobs.get(job, 0)) + 1
		happiness += person.happiness
	var summary := housing_summary()
	return {
		"total": living.size(), "visitors": visitors().size(),
		"children": stages[Person.STAGE_CHILD], "teens": stages[Person.STAGE_TEEN],
		"adults": stages[Person.STAGE_ADULT], "elders": stages[Person.STAGE_ELDER],
		"occupations": jobs, "housing": summary,
		"happiness": happiness / maxf(living.size(), 1.0),
		"couples": living.filter(func(p: Person): return p.partner != "").size() / 2,
		"counters": counters.duplicate(),
	}


func log_event(type: String, text: String, ids: Array = []) -> void:
	var event := {"day": WorldClock.day, "type": type, "text": text, "ids": ids}
	events.append(event)
	if events.size() > 200:
		events.pop_front()
	event_logged.emit(event)


# --- Arrivals and departures ---------------------------------------------------------------

func make_resident(person: Person) -> void:
	person.status = Person.STATUS_RESIDENT
	person.arrived_day = WorldClock.day
	assign_home(person)
	counters["arrivals"] += 1
	log_event("arrival", "%s the %s joined the village." % [person.full_name(), Professions.label(person.profession).to_lower()], [person.id])
	person_changed.emit(person)


func reject(person: Person) -> void:
	person.status = Person.STATUS_LEFT
	person.departed_day = WorldClock.day
	counters["rejected"] += 1
	log_event("rejected", "%s was turned away." % person.full_name(), [person.id])
	person_removed.emit(person, "rejected")


func depart(person: Person) -> void:
	var was_resident := person.status == Person.STATUS_RESIDENT
	person.status = Person.STATUS_LEFT
	person.departed_day = WorldClock.day
	_pass_on_home(person)
	_end_partnership(person, "left the village")
	if was_resident:
		counters["departures"] += 1
		log_event("departure", "%s left the village." % person.full_name(), [person.id])
	person_removed.emit(person, "left")
	housing_changed.emit()


# --- Families (phase 3) ----------------------------------------------------------------------

func are_family(a: Person, b: Person) -> bool:
	if a.relatives.has(b.id) or b.relatives.has(a.id):
		return String(a.relatives.get(b.id, b.relatives.get(a.id, ""))) != "friend"
	if a.parents.has(b.id) or b.parents.has(a.id):
		return true
	for parent in a.parents:
		if b.parents.has(parent):
			return true
	return false


## Two single adults who aren't family can become partners.
func can_partner(a: Person, b: Person) -> bool:
	return a != b and a.is_resident() and b.is_resident() and a.partner == "" and b.partner == "" \
		and a.age() >= 18 and b.age() >= 18 and absi(a.age() - b.age()) <= 15 and not are_family(a, b)


func form_partnership(a: Person, b: Person) -> bool:
	if not can_partner(a, b):
		return false
	a.partner = b.id
	b.partner = a.id
	a.partnered_day = WorldClock.day
	b.partnered_day = WorldClock.day
	counters["partnerships"] += 1
	log_event("partnership", "%s and %s are now together." % [a.first_name, b.first_name], [a.id, b.id])
	# Move in together if there's room.
	var home_a := homes().filter(func(h): return h["id"] == a.home)
	if not home_a.is_empty() and home_a[0]["kind"] != "camp" and _has_space(home_a[0], b):
		_move_in(b, a.home)
	else:
		var home_b := homes().filter(func(h): return h["id"] == b.home)
		if not home_b.is_empty() and home_b[0]["kind"] != "camp" and _has_space(home_b[0], a):
			_move_in(a, b.home)
	person_changed.emit(a)
	person_changed.emit(b)
	return true


func marry(a: Person, b: Person) -> bool:
	if a.partner != b.id or a.married:
		return false
	a.married = true
	b.married = true
	counters["marriages"] += 1
	log_event("marriage", "%s and %s were married at the meeting circle." % [a.first_name, b.first_name], [a.id, b.id])
	person_changed.emit(a)
	person_changed.emit(b)
	return true


func _end_partnership(person: Person, reason: String) -> void:
	var other := get_person(person.partner)
	if other:
		other.partner = ""
		other.married = false
		log_event("separation", "%s's partner %s %s." % [other.first_name, person.first_name, reason], [other.id, person.id])
		person_changed.emit(other)
	person.partner = ""


func can_have_child(a: Person, b: Person) -> bool:
	return a.partner == b.id and a.age() < 48 and b.age() < 48 and residents_of(a.home).size() < _capacity_of(a.home)


func _capacity_of(home_id: String) -> int:
	for home: Dictionary in homes():
		if home["id"] == home_id:
			return int(home["capacity"])
	return 0


## A child born to two partners: looks drawn from both parents, the family
## name of one, living in the parents' home.
func register_birth(a: Person, b: Person, rng: RandomNumberGenerator) -> Person:
	var child := Person.new()
	child.id = new_id()
	child.sex = "female" if rng.randf() < 0.5 else "male"
	child.birth_day = WorldClock.day
	child.first_name = NameGenerator.first_name(rng, child.sex, taken_first_names())
	child.family_name = a.family_name if a.family_name != "" else b.family_name
	child.parents = [a.id, b.id]
	child.origin = "born"
	child.status = Person.STATUS_RESIDENT
	child.home = a.home
	child.arrived_day = WorldClock.day
	child.personality = {}
	for key in a.personality:
		child.personality[key] = snappedf(clampf(lerpf(float(a.personality[key]), float(b.personality.get(key, 0.5)), rng.randf()) + rng.randf_range(-0.15, 0.15), 0.05, 0.95), 0.01)
	child.traits = PersonGenerator._traits(child.personality)
	child.skills = {}
	child.profession = ""
	var look_a := AppearanceCodec.from_dict(a.appearance)
	var look_b := AppearanceCodec.from_dict(b.appearance)
	var base := look_a if rng.randf() < 0.5 else look_b
	var look := AppearanceGenerator.generate(rng, child.sex, 0, "farmer", [], base)
	look.skin_color = look_a.skin_color.lerp(look_b.skin_color, rng.randf_range(0.3, 0.7))
	look.eye_color = look_a.eye_color if rng.randf() < 0.5 else look_b.eye_color
	look.work_tool = ""
	child.appearance = AppearanceCodec.to_dict(look)
	a.children.append(child.id)
	b.children.append(child.id)
	add(child)
	counters["births"] += 1
	log_event("birth", "%s and %s welcomed a baby, %s." % [a.first_name, b.first_name, child.first_name], [child.id, a.id, b.id])
	return child


## Takes a child (or anyone younger) into a family.
func adopt(parents_list: Array, child: Person) -> void:
	for parent: Person in parents_list:
		if not parent.children.has(child.id):
			parent.children.append(child.id)
		if not child.parents.has(parent.id):
			child.parents.append(parent.id)
	if not parents_list.is_empty():
		child.home = (parents_list[0] as Person).home
		child.family_name = (parents_list[0] as Person).family_name
	log_event("adoption", "%s was adopted by %s." % [child.first_name, " and ".join(parents_list.map(func(p): return p.first_name))], [child.id])
	person_changed.emit(child)


func siblings(person: Person) -> Array:
	var out: Array = []
	for other: Person in people.values():
		if other == person:
			continue
		for parent in person.parents:
			if other.parents.has(parent) and not out.has(other.id):
				out.append(other.id)
	for id in person.relatives:
		if String(person.relatives[id]) == "sibling" and not out.has(id):
			out.append(id)
	return out


func ancestors(person: Person, depth: int = 4) -> Array:
	var out: Array = []
	if depth <= 0:
		return out
	for parent_id in person.parents:
		var parent := get_person(String(parent_id))
		if parent:
			out.append(parent.id)
			out.append_array(ancestors(parent, depth - 1))
	return out


func descendants(person: Person, depth: int = 4) -> Array:
	var out: Array = []
	if depth <= 0:
		return out
	for child_id in person.children:
		var child := get_person(String(child_id))
		if child:
			out.append(child.id)
			out.append_array(descendants(child, depth - 1))
	return out


## A person's family as a nested dictionary (parents up, children down).
func family_tree(person: Person, depth: int = 3) -> Dictionary:
	var node := {"id": person.id, "name": person.full_name(), "partner": person.partner, "parents": [], "children": []}
	if depth <= 0:
		return node
	for parent_id in person.parents:
		var parent := get_person(String(parent_id))
		if parent:
			node["parents"].append({"id": parent.id, "name": parent.full_name()})
	for child_id in person.children:
		var child := get_person(String(child_id))
		if child:
			node["children"].append(family_tree(child, depth - 1))
	return node


## Death: the record stays (family trees, memories); the home passes on.
func die(person: Person, cause: String = "old age") -> void:
	person.status = Person.STATUS_DEAD
	person.departed_day = WorldClock.day
	_pass_on_home(person)
	_end_partnership(person, "passed away")
	counters["deaths"] += 1
	log_event("death", "%s passed away (%s), aged %d." % [person.full_name(), cause, person.age()], [person.id])
	person_removed.emit(person, "died")
	housing_changed.emit()


## Inheritance: a home someone owned passes to their partner, then their
## eldest child living here, then anyone else living in it.
func _pass_on_home(person: Person) -> void:
	for home_id in home_owners.keys():
		if home_owners[home_id] != person.id:
			continue
		var heir := ""
		var partner := get_person(person.partner)
		if partner and partner.is_resident():
			heir = partner.id
		else:
			var eldest_birth := 1 << 30
			for child_id in person.children:
				var child := get_person(String(child_id))
				if child and child.is_resident() and child.birth_day < eldest_birth:
					eldest_birth = child.birth_day
					heir = child.id
		if heir == "":
			for other_id in residents_of(String(home_id)):
				if other_id != person.id:
					heir = String(other_id)
					break
		if heir == "":
			home_owners.erase(home_id)
		else:
			home_owners[home_id] = heir
			log_event("inheritance", "%s now keeps %s." % [get_person(heir).first_name, _home_label(String(home_id))], [heir])


func _home_label(home_id: String) -> String:
	for home: Dictionary in homes():
		if home["id"] == home_id:
			return String(home["label"])
	return home_id


## Called once per new day: birthdays, coming of age, old age.
func advance_day(rng: RandomNumberGenerator) -> void:
	for person: Person in residents():
		var age := person.age()
		var yesterday := person.age(WorldClock.day - 1)
		if age != yesterday:
			var stage := Person.stage_for_age(age)
			if stage != Person.stage_for_age(yesterday):
				log_event("coming_of_age", "%s is now %s." % [person.first_name, "an adult" if stage == Person.STAGE_ADULT else "an elder" if stage == Person.STAGE_ELDER else "a teenager"], [person.id])
		if age >= 75 and not (person.founder and FOUNDERS_AGE_SAFELY):
			if rng.randf() < (age - 74) * 0.004:
				die(person)


# --- Persistence -----------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var records := {}
	for id in people:
		records[id] = (people[id] as Person).to_dict()
	return {"people": records, "events": events.duplicate(true), "counters": counters.duplicate(),
		"home_owners": home_owners.duplicate(), "next_id": next_id, "invitations": invitations.duplicate(true)}


func from_dict(data: Dictionary) -> void:
	reset()
	var records: Variant = data.get("people", {})
	if records is Dictionary:
		for id in records:
			people[String(id)] = Person.from_dict(records[id])
	var saved_events: Variant = data.get("events", [])
	if saved_events is Array:
		events = (saved_events as Array).duplicate(true)
	var saved_counters: Variant = data.get("counters", {})
	if saved_counters is Dictionary:
		for key in saved_counters:
			counters[String(key)] = int(saved_counters[key])
	var owners: Variant = data.get("home_owners", {})
	if owners is Dictionary:
		home_owners = (owners as Dictionary).duplicate()
	next_id = int(data.get("next_id", 1))
	var saved_invitations: Variant = data.get("invitations", [])
	if saved_invitations is Array:
		invitations = (saved_invitations as Array).duplicate(true)
