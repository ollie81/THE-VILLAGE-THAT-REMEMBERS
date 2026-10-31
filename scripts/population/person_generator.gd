class_name PersonGenerator
extends RefCounted
## Creates newcomers (travellers and invited relatives) and turns any Person
## into the VillagerData a 3D Villager needs.

const ORIGINS: Array[String] = [
	"from the coast", "from the mountain passes", "from a river town to the south", "from the eastern plains",
	"from a fishing village up north", "from the city beyond the hills", "from a farm three valleys away",
	"from a caravan that went on without me", "from the forest settlements", "from the salt marshes",
]
const AMBITIONS := {
	"master_craft": "become the best %s this valley has seen",
	"friends": "make real friends again",
	"partner": "find someone to share a home with",
	"home": "have a roof of my own",
	"family": "send for my family once I'm settled",
	"see_growth": "see this place grow into a proper town",
	"wander": "rest a while before the road calls again",
}
const TRAITS := {
	"openness": ["Curious", "Traditional"],
	"conscientiousness": ["Diligent", "Easygoing"],
	"extraversion": ["Outgoing", "Quiet"],
	"agreeableness": ["Kind", "Blunt"],
	"neuroticism": ["Anxious", "Calm"],
	"adventure": ["Restless", "Homely"],
}


## A new person. `relative` (optional) makes them family of that person:
## shared family name for kin, similar looks.
static func create(rng: RandomNumberGenerator, id: String, taken_first_names: Dictionary,
		others: Array, relative: Person = null, relation: String = "") -> Person:
	var p := Person.new()
	p.id = id
	p.sex = "female" if rng.randf() < 0.5 else "male"
	var age := _random_age(rng, relation)
	p.birth_day = WorldClock.day - age * Person.year_days - rng.randi_range(0, Person.year_days - 1)
	p.first_name = NameGenerator.first_name(rng, p.sex, taken_first_names)
	var kin := relation in ["sibling", "cousin", "parent", "child"]
	p.family_name = relative.family_name if relative and kin and relative.family_name != "" else NameGenerator.family_name(rng)
	p.personality = _personality(rng)
	p.traits = _traits(p.personality)
	p.skills = _skills(rng, _talent(rng))
	p.profession = Professions.best_for(p.skills)
	# Relatives often learned the family trade.
	if relative and kin and rng.randf() < 0.4:
		p.profession = relative.profession
		p.skills[String(Professions.info(p.profession)["skill"])] = maxf(float(p.skills.get(String(Professions.info(p.profession)["skill"]), 0.0)), 0.7)
	p.ambition = _ambition(rng, p)
	var family_look: CharacterAppearance = AppearanceCodec.from_dict(relative.appearance) if relative and kin and not relative.appearance.is_empty() else null
	var look := AppearanceGenerator.generate(rng, p.sex, age, p.profession, others, family_look)
	p.appearance = AppearanceCodec.to_dict(look)
	# Teenagers' stored look is the adult they'll grow into.
	p.look_age = maxi(age, 18)
	p.origin = "invited" if relative else "traveller"
	if relative:
		p.invited_by = relative.id
		p.relatives[relative.id] = relation
	p.biography = _biography(rng, p, relative, relation)
	p.status = Person.STATUS_VISITOR
	p.arrived_day = WorldClock.day
	return p


## A child who needs a family (adopted on arrival): their stored look is the
## adult they'll grow into.
static func create_child(rng: RandomNumberGenerator, id: String, taken_first_names: Dictionary, others: Array) -> Person:
	var p := Person.new()
	p.id = id
	p.sex = "female" if rng.randf() < 0.5 else "male"
	var age := rng.randi_range(4, 10)
	p.birth_day = WorldClock.day - age * Person.year_days - rng.randi_range(0, Person.year_days - 1)
	p.first_name = NameGenerator.first_name(rng, p.sex, taken_first_names)
	p.personality = _personality(rng)
	p.traits = _traits(p.personality)
	p.skills = _skills(rng, _talent(rng))
	for skill in p.skills:
		p.skills[skill] = snappedf(float(p.skills[skill]) * 0.4, 0.01)
	p.profession = ""
	p.ambition = {"id": "friends", "text": "make real friends", "progress": 0.0, "done": false}
	p.appearance = AppearanceCodec.to_dict(AppearanceGenerator.generate(rng, p.sex, 22, "farmer", others))
	p.look_age = 18
	p.origin = "adopted"
	p.biography = "%s lost their family to a fever in a village down the river." % p.first_name
	p.status = Person.STATUS_VISITOR
	p.arrived_day = WorldClock.day
	return p


static func _random_age(rng: RandomNumberGenerator, relation: String) -> int:
	match relation:
		"parent":
			return rng.randi_range(55, 72)
		"child":
			return rng.randi_range(14, 22)
	var roll := rng.randf()
	if roll < 0.08:
		return rng.randi_range(15, 17)
	if roll < 0.82:
		return rng.randi_range(18, 45)
	if roll < 0.94:
		return rng.randi_range(46, 59)
	return rng.randi_range(60, 72)


static func _personality(rng: RandomNumberGenerator) -> Dictionary:
	var out := {}
	for key in TRAITS:
		out[key] = snappedf(clampf(rng.randfn(0.5, 0.2), 0.05, 0.95), 0.01)
	return out


static func _traits(personality: Dictionary) -> PackedStringArray:
	# The three most pronounced sides of their character.
	var scored: Array = []
	for key in TRAITS:
		var value := float(personality.get(key, 0.5))
		scored.append([absf(value - 0.5), key, value])
	scored.sort_custom(func(a, b): return a[0] > b[0])
	var out := PackedStringArray()
	for i in 3:
		var entry: Array = scored[i]
		var names: Array = TRAITS[entry[1]]
		out.append(String(names[0] if float(entry[2]) >= 0.5 else names[1]))
	return out


## The skill a newcomer is best at. Trades the village is short of are more
## likely: word gets around that the village needs a fisher.
static func _talent(rng: RandomNumberGenerator) -> String:
	var counts := {}
	for person: Person in Population.residents(true):
		var skill := String(Professions.info(person.profession)["skill"])
		counts[skill] = int(counts.get(skill, 0)) + 1
	var weights := {}
	for skill in Professions.SKILLS:
		weights[skill] = 1.0 / (1.0 + float(counts.get(skill, 0)))
	return AppearanceGenerator._weighted(rng, weights)


static func _skills(rng: RandomNumberGenerator, talent: String) -> Dictionary:
	var out := {}
	for skill in Professions.SKILLS:
		out[skill] = snappedf(rng.randf_range(0.05, 0.45), 0.01)
	# One real talent, sometimes a second.
	out[talent] = snappedf(rng.randf_range(0.65, 0.95), 0.01)
	if rng.randf() < 0.4:
		out[Professions.SKILLS[rng.randi_range(0, Professions.SKILLS.size() - 1)]] = snappedf(rng.randf_range(0.5, 0.8), 0.01)
	return out


static func _ambition(rng: RandomNumberGenerator, p: Person) -> Dictionary:
	var weights := {
		"master_craft": 1.0 + p.trait_weight("conscientiousness"),
		"friends": 0.5 + p.trait_weight("extraversion"),
		"partner": 0.8 if p.age() >= 18 else 0.0,
		"home": 0.8,
		"family": 0.6 + p.trait_weight("agreeableness") * 0.5,
		"see_growth": 0.4 + p.trait_weight("openness") * 0.5,
		"wander": p.trait_weight("adventure") * 0.8,
	}
	var id := AppearanceGenerator._weighted(rng, weights)
	var text := String(AMBITIONS[id])
	if id == "master_craft":
		text = text % Professions.label(p.profession).to_lower()
	return {"id": id, "text": text, "progress": 0.0, "done": false}


static func _biography(rng: RandomNumberGenerator, p: Person, relative: Person, relation: String) -> String:
	var job := Professions.label(p.profession).to_lower()
	var origin := ORIGINS[rng.randi_range(0, ORIGINS.size() - 1)]
	var start := "%s came %s" % [p.first_name, origin]
	if relative:
		start = "%s came at the invitation of %s, their %s" % [p.first_name, relative.full_name(), _relation_word(relation, relative.sex)]
	return "%s. A %s by trade, %s hopes to %s." % [start, job, "she" if p.sex == "female" else "he", p.ambition.get("text", "settle down")]


static func _relation_word(relation: String, sex: String) -> String:
	match relation:
		"sibling":
			return "sister" if sex == "female" else "brother"
		"parent":
			return "daughter" if sex == "female" else "son"
		"child":
			return "mother" if sex == "female" else "father"
	return relation


# --- Villager data -------------------------------------------------------------------

## VillagerData for a generated person (founders load their own .tres).
static func make_data(p: Person) -> VillagerData:
	var data := VillagerData.new()
	data.id = StringName(p.id)
	data.display_name = p.first_name
	data.age = p.age()
	var stage := p.life_stage()
	data.role = Professions.label(p.profession)
	if stage == Person.STAGE_CHILD:
		data.role = "Child"
	elif stage == Person.STAGE_TEEN:
		data.role = "Apprentice %s" % Professions.label(p.profession).to_lower() if p.profession != "" else "Teenager"
	data.traits = p.traits
	data.biography = p.biography
	data.appearance = p.current_look()
	data.home_location = p.home if p.home != "" else "camp"
	data.personality = p.personality
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(p.id)
	var age := p.age()
	data.walk_speed = clampf(1.75 - maxf(age - 50, 0) * 0.02 + rng.randf_range(-0.1, 0.1), 1.2, 1.9)
	if stage == Person.STAGE_CHILD:
		data.walk_speed = lerpf(1.2, 1.6, clampf((age - 3.0) / 9.0, 0.0, 1.0))
	data.schedule = _child_schedule(p, rng) if stage == Person.STAGE_CHILD \
		else _teen_schedule(p, rng) if stage == Person.STAGE_TEEN else Professions.schedule_for(p, rng)
	var wander := PackedStringArray()
	for place in ["plaza", "farm", "garden", "workshop", "storage", "riverbank", "bridge", "woodlot"]:
		if rng.randf() < 0.55:
			wander.append(place)
	if wander.size() < 2:
		wander = PackedStringArray(["plaza", "storage"])
	data.wander_locations = wander
	data.first_meeting_lines = _child_first_lines(p) if stage == Person.STAGE_CHILD else _first_lines(p)
	data.returning_lines = _child_lines(p) if stage == Person.STAGE_CHILD else _returning_lines(p)
	data.activity_comments = {
		"work": "[happy]Honest work. %s" % ("I wouldn't trade it for anything." if p.trait_weight("conscientiousness") > 0.5 else "Mostly honest, anyway."),
		"gather": "There's always more out here than you'd think.",
		"socialize": "[laughing]Sit down, sit down! You're missing all the news." if p.trait_weight("extraversion") > 0.55 else "[happy]It's nice, sitting with everyone in the evening.",
		"wander": "Just stretching my legs.",
		"trade": "Everything has its price.",
	}
	return data


## Children play, tag along to a parent's work, and go to bed early.
static func _child_schedule(p: Person, rng: RandomNumberGenerator) -> Array:
	var parent := _working_parent(p)
	var help: Array = ["garden", "Helping in the garden", "gather"]
	if parent:
		var place: Array = Professions.info(parent.profession)["places"][0]
		help = [place[0], "Helping %s at %s" % [parent.first_name, VillageLayout.get_location_label(String(place[0]))], "gather"]
	var plays: Array = [["plaza", "Playing tag at the meeting circle", "jump"], ["garden", "Playing in the garden", "jump"],
		["riverbank", "Skipping stones at the river", "gather"], ["bridge", "Watching fish from the bridge", "idle"]]
	var morning: Array = plays[rng.randi_range(0, plays.size() - 1)]
	var afternoon: Array = plays[rng.randi_range(0, plays.size() - 1)]
	return [
		{"hour": 7.5, "activity": "socialize", "location": morning[0], "label": morning[1], "anim": morning[2]},
		{"hour": 9.5, "activity": "work", "location": help[0], "label": help[1], "anim": help[2]},
		{"hour": 12.0, "activity": "rest", "location": "home", "label": "Lunch at home"},
		{"hour": 13.0, "activity": "socialize", "location": afternoon[0], "label": afternoon[1], "anim": afternoon[2]},
		{"hour": 16.0, "activity": "wander", "location": "", "label": "Running around the village"},
		{"hour": 18.0, "activity": "rest", "location": "home", "label": "Supper at home"},
		{"hour": 20.0 + rng.randf_range(0.0, 0.5), "activity": "sleep", "location": "home"},
	]


## Teenagers learn their trade in the mornings and afternoons.
static func _teen_schedule(p: Person, rng: RandomNumberGenerator) -> Array:
	var job := Professions.info(p.profession if p.profession != "" else "farmer")
	var place: Array = job["places"][0]
	var learn := "Learning to be a %s" % String(job["name"]).to_lower()
	return [
		{"hour": 7.5, "activity": "work", "location": place[0], "label": learn, "anim": place[2]},
		{"hour": 12.0, "activity": "socialize", "location": "plaza", "label": "Lunch with friends at the meeting circle"},
		{"hour": 13.0, "activity": "work", "location": place[0], "label": learn, "anim": place[2]},
		{"hour": 17.0, "activity": "wander", "location": "", "label": "Wandering around the village"},
		{"hour": 19.0, "activity": "socialize", "location": "plaza", "label": "Hanging around the meeting circle"},
		{"hour": 21.5 + rng.randf_range(0.0, 0.5), "activity": "sleep", "location": "home"},
	]


static func _working_parent(p: Person) -> Person:
	for parent_id in p.parents:
		var parent: Person = Population.get_person(String(parent_id))
		if parent and parent.is_resident() and parent.profession != "":
			return parent
	return null


static func _child_first_lines(p: Person) -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("[laughing]I'm %d!" % p.age() if p.trait_weight("extraversion") > 0.4 else "...I'm %d." % p.age())
	var parent := _working_parent(p)
	if parent:
		lines.append("[happy]%s is my %s. %s's the best %s in the whole village." % [parent.first_name,
			"mum" if parent.sex == "female" else "dad", "She" if parent.sex == "female" else "He", Professions.label(parent.profession).to_lower()])
	elif p.origin == "adopted":
		lines.append("[sad]I used to live down the river. But this is home now.")
	return lines


static func _child_lines(p: Person) -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("[laughing]Bet you can't catch me!")
	if p.trait_weight("openness") > 0.55:
		lines.append("[surprised]Did you know frogs can sleep with their eyes open? Probably.")
	if p.trait_weight("neuroticism") > 0.6:
		lines.append("[worried]Is it true there are wolves in the forest?")
	lines.append("[happy]When I grow up I'm going to build the biggest house ever.")
	return lines


static func _first_lines(p: Person) -> PackedStringArray:
	var job := Professions.label(p.profession).to_lower()
	var lines := PackedStringArray()
	if p.trait_weight("extraversion") > 0.6:
		lines.append("[laughing]I'm the new %s! Well, new to you. I've been a %s for years." % [job, job])
	elif p.trait_weight("extraversion") < 0.35:
		lines.append("I'm the %s. I keep to myself, mostly." % job)
	else:
		lines.append("[happy]I work as the %s here." % job)
	lines.append("[happy]One day I'd like to %s." % String(p.ambition.get("text", "settle down")))
	return lines


static func _returning_lines(p: Person) -> PackedStringArray:
	var lines := PackedStringArray()
	if p.trait_weight("agreeableness") > 0.6:
		lines.append("[happy]If you ever need a hand, just ask me.")
	elif p.trait_weight("agreeableness") < 0.35:
		lines.append("Don't take this the wrong way, but I'm busy.")
	if p.trait_weight("adventure") > 0.65:
		lines.append("[surprised]Have you seen what's past the forest? I keep meaning to look.")
	if p.trait_weight("neuroticism") > 0.65:
		lines.append("[worried]Do you think the winter will be hard this year?")
	lines.append("[happy]This village is starting to feel like home.")
	return lines


# --- Travellers --------------------------------------------------------------------

## A traveller waits at the meeting circle by day to meet the player and
## sleeps at the camp until they've been welcomed or sent on their way.
static func make_visitor_data(p: Person) -> VillagerData:
	var data := make_data(p)
	data.home_location = Population.CAMP_ID
	data.schedule = [
		{"hour": 6.5, "activity": "wait", "location": "plaza", "label": "Waiting to meet you", "anim": "idle"},
		{"hour": 21.5, "activity": "sleep", "location": "home"},
	]
	data.wander_locations = PackedStringArray(["plaza"])
	return data


## What a traveller says when the player first speaks to them.
static func visitor_intro(p: Person) -> Array[String]:
	var lines: Array[String] = []
	var job := Professions.label(p.profession).to_lower()
	var inviter: Person = Population.get_person(p.invited_by) if p.invited_by != "" else null
	if p.trait_weight("extraversion") > 0.6:
		lines.append("[laughing]Hello there! I'm %s %s. What a lovely little village!" % [p.first_name, p.family_name])
	elif p.trait_weight("neuroticism") > 0.65:
		lines.append("[worried]Oh! Hello. I'm %s %s. I hope I'm not intruding." % [p.first_name, p.family_name])
	else:
		lines.append("[happy]Good day. My name is %s %s." % [p.first_name, p.family_name])
	if inviter:
		lines.append("[happy]%s wrote and told me there might be a place for me here. I'm their %s." % [inviter.first_name, String(p.relatives.get(inviter.id, "friend"))])
	else:
		lines.append("I've been on the road a long while. I'm a %s, and a good one." % job)
	lines.append("[happy]I'd like to %s. Would you let me stay?" % String(p.ambition.get("text", "settle down")))
	return lines


## Their answer to "Tell me more about yourself."
static func visitor_details(p: Person) -> Array[String]:
	var lines: Array[String] = []
	var best := ""
	var best_value := 0.0
	for skill in p.skills:
		if float(p.skills[skill]) > best_value:
			best_value = float(p.skills[skill])
			best = String(skill)
	lines.append("I'm %d. Most people would call me %s." % [p.age(), ", ".join(Array(p.traits).map(func(t): return String(t).to_lower()))])
	lines.append("[happy]I'm best at %s. I could be useful around here." % best)
	if p.trait_weight("agreeableness") > 0.65:
		lines.append("[happy]And I'll pitch in wherever I'm needed. I like helping.")
	elif p.trait_weight("agreeableness") < 0.35:
		lines.append("I'll do my share. Don't expect me to smile about it.")
	return lines
