class_name SocialLife
extends Node
## Villagers' lives between themselves, ticked by game time:
## - every hour, people near each other get to know each other; friendships
##   and romances grow from that, shaped by personality.
## - every day, everyone weighs up how happy they are (a home, friends, a
##   partner, work that suits them, how the player treats them), works
##   towards their ambition, and may decide to invite family or to leave.

const MEET_DISTANCE := 6.0
const FRIEND_AFFECTION := 30.0
const ROMANCE_AFFECTION := 55.0
const MARRIAGE_AFFECTION := 70.0
const MARRIAGE_AFTER_DAYS := 8
const UNHAPPY := 30.0
const HAPPY := 70.0
const RELATIONS: Array[String] = ["sibling", "cousin", "friend", "parent", "child"]

static var instance: SocialLife

var rng := RandomNumberGenerator.new()


func _ready() -> void:
	name = "SocialLife"
	instance = self
	rng.randomize()
	WorldClock.hour_changed.connect(func(_h): hourly())
	WorldClock.day_changed.connect(func(_d): daily())


func _exit_tree() -> void:
	if instance == self:
		instance = null


# --- Hourly: getting to know each other ------------------------------------------

func hourly() -> void:
	var present: Array = []
	for villager in GameManager.villagers:
		if villager.person and villager.person.is_resident() and villager.visible and not villager.is_leaving():
			present.append(villager)
	for i in present.size():
		for j in range(i + 1, present.size()):
			var a = present[i]
			var b = present[j]
			if a.global_position.distance_to(b.global_position) <= MEET_DISTANCE:
				spend_time(a, b, 1.0)


## Two people spent an hour near each other. How much they warm to each
## other depends on how well their personalities fit.
func spend_time(a, b, hours: float) -> void:
	var pa: Person = a.person
	var pb: Person = b.person
	var fit := compatibility(pa, pb)
	var gain := (1.0 + 3.0 * fit) * hours
	a.mind.adjust_opinion(String(pb.id), gain, gain * 0.6)
	b.mind.adjust_opinion(String(pa.id), gain, gain * 0.6)
	a.mind.record_interaction(String(pb.id), "time_together", WorldClock.day, WorldClock.time_of_day)
	b.mind.record_interaction(String(pa.id), "time_together", WorldClock.day, WorldClock.time_of_day)
	var ab: float = a.mind.get_affection(String(pb.id))
	var ba: float = b.mind.get_affection(String(pa.id))
	if ab >= ROMANCE_AFFECTION and ba >= ROMANCE_AFFECTION and Population.can_partner(pa, pb) \
			and rng.randf() < 0.15 * (0.5 + fit):
		if Population.form_partnership(pa, pb):
			GameManager.notify("%s and %s have fallen for each other." % [pa.first_name, pb.first_name])


## 0..1: kind, sociable people get on with most; similar people get on best.
static func compatibility(a: Person, b: Person) -> float:
	var difference := 0.0
	for key in ["openness", "extraversion", "conscientiousness", "adventure"]:
		difference += absf(a.trait_weight(key) - b.trait_weight(key))
	var kindness := (a.trait_weight("agreeableness") + b.trait_weight("agreeableness")) * 0.5
	return clampf(1.0 - difference / 4.0 * 1.4 + (kindness - 0.5) * 0.6, 0.0, 1.0)


func friends_of(villager) -> Array:
	var out: Array = []
	for other_id in villager.mind.relationships:
		if String(other_id) == GameManager.PLAYER_ID:
			continue
		if villager.mind.get_affection(String(other_id)) >= FRIEND_AFFECTION:
			out.append(String(other_id))
	return out


# --- Daily: happiness, ambitions, decisions ------------------------------------------

func daily() -> void:
	for villager in GameManager.villagers.duplicate():
		var person: Person = villager.person
		if person == null or not person.is_resident():
			continue
		_update_happiness(villager, person)
		_progress_ambition(villager, person)
		_maybe_marry(person)
		_decide(villager, person)


func _update_happiness(villager, person: Person) -> void:
	var happiness := 50.0
	if person.home == Population.CAMP_ID or person.home == "":
		person.homeless_days += 1
		happiness -= 8.0 + minf(person.homeless_days * 2.0, 20.0)
	else:
		person.homeless_days = 0
		happiness += 10.0
	happiness += minf(friends_of(villager).size() * 5.0, 20.0)
	if person.partner != "":
		happiness += 10.0
	var skill := String(Professions.info(person.profession)["skill"])
	happiness += float(person.skills.get(skill, 0.4)) * 10.0
	happiness += clampf(villager.mind.get_affection(GameManager.PLAYER_ID) * 0.15, -15.0, 15.0)
	if bool(person.ambition.get("done", false)):
		happiness += 10.0
	happiness -= person.trait_weight("neuroticism") * 8.0
	person.happiness = clampf(happiness, 0.0, 100.0)
	person.unhappy_days = person.unhappy_days + 1 if person.happiness < UNHAPPY else 0


func _progress_ambition(villager, person: Person) -> void:
	if person.ambition.is_empty() or bool(person.ambition.get("done", false)):
		return
	var progress := float(person.ambition.get("progress", 0.0))
	match String(person.ambition.get("id", "")):
		"master_craft":
			progress += 0.04 * (0.5 + person.trait_weight("conscientiousness"))
		"friends":
			progress = friends_of(villager).size() / 3.0
		"partner":
			progress = 1.0 if person.partner != "" else progress
		"home":
			progress = 1.0 if person.home != Population.CAMP_ID and person.home != "" else 0.0
		"family":
			progress = 1.0 if person.has_invited else progress
		"see_growth":
			progress = Population.count() / 20.0
		"wander":
			progress += 1.0 / 15.0
	person.ambition["progress"] = clampf(progress, 0.0, 1.0)
	if progress >= 1.0:
		person.ambition["done"] = true
		Population.log_event("ambition", "%s achieved a dream: to %s." % [person.first_name, String(person.ambition["text"])], [person.id])
		if String(person.ambition["id"]) == "wander":
			# Rested and ready for the road again.
			if not person.founder:
				person.leaving = true
				GameManager.notify("%s feels the road calling again, and will leave in the morning." % person.first_name)
		else:
			GameManager.notify("%s's dream came true: to %s." % [person.first_name, String(person.ambition["text"])])


func _maybe_marry(person: Person) -> void:
	var partner := Population.get_person(person.partner)
	if partner == null or person.married or person.id > partner.id:
		return
	if WorldClock.day - person.partnered_day < MARRIAGE_AFTER_DAYS:
		return
	var a = GameManager.get_villager(StringName(person.id))
	var b = GameManager.get_villager(StringName(partner.id))
	if a == null or b == null:
		return
	if a.mind.get_affection(partner.id) >= MARRIAGE_AFFECTION and b.mind.get_affection(person.id) >= MARRIAGE_AFFECTION \
			and rng.randf() < 0.25:
		Population.marry(person, partner)
		GameManager.notify("Wedding at the meeting circle! %s and %s are married." % [person.first_name, partner.first_name])


## Unhappy people leave after a few bad days; happy ones may send for family.
func _decide(villager, person: Person) -> void:
	if person.founder:
		return
	if person.unhappy_days >= 3 and not person.leaving:
		var chance := 0.35 + person.trait_weight("adventure") * 0.3 - person.trait_weight("agreeableness") * 0.1
		if rng.randf() < chance:
			person.leaving = true
			Population.log_event("leaving", "%s is unhappy and decided to leave." % person.first_name, [person.id])
			GameManager.notify("%s is unhappy here and will leave tomorrow morning. Talk to them?" % person.first_name)
			return
	if person.happiness >= HAPPY and not person.has_invited and Population.has_room_for_more() \
			and int(Population.housing_summary()["free"]) > 0 and PopulationDirector.instance \
			and Population.invitations.size() < 2:
		var chance := 0.12 + (0.2 if String(person.ambition.get("id", "")) == "family" else 0.0)
		if rng.randf() < chance:
			var relation := RELATIONS[rng.randi_range(0, RELATIONS.size() - 1)]
			if relation == "parent" and person.age() > 45:
				relation = "sibling"
			if relation == "child" and person.age() < 38:
				relation = "cousin"
			PopulationDirector.instance.queue_invitation(person, relation)
