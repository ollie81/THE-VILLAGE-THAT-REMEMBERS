class_name Professions
extends RefCounted
## What villagers do for a living: where they work, the tool they carry, the
## skill it uses, how they feel about the jobs the player can ask for, and
## the daily timetable built from it (shaped by their personality).

const SKILLS: Array[String] = [
	"farming", "building", "herbalism", "crafting", "trade", "woodcutting", "stonework", "fishing", "cooking", "weaving",
]

## id -> { name, skill, places: [[location, label, anim]], tool, accessories
## (likely extras), tasks: {build, wood, stone, farm} preference 0..1 }
const CATALOG := {
	"farmer": {"name": "Farmer", "skill": "farming", "tool": "hoe", "accessories": ["straw_hat", "suspenders"],
		"places": [["farm", "Tending the fields", "work"], ["farm", "Weeding the rows", "gather"]],
		"tasks": {"farm": 0.9, "build": 0.4, "wood": 0.4, "stone": 0.3}},
	"builder": {"name": "Builder", "skill": "building", "tool": "hammer", "accessories": ["tool_belt"],
		"places": [["build_site", "Framing walls at the building site", "work"], ["workshop", "Cutting beams at the workshop", "work"]],
		"tasks": {"build": 0.9, "wood": 0.5, "stone": 0.5, "farm": 0.2}},
	"herbalist": {"name": "Herbalist", "skill": "herbalism", "tool": "basket", "accessories": ["apron", "flower"],
		"places": [["garden", "Picking herbs in the garden", "gather"], ["forest_edge", "Looking for wild herbs", "gather"]],
		"tasks": {"farm": 0.7, "wood": 0.3, "build": 0.2, "stone": 0.1}},
	"craftsman": {"name": "Craftsperson", "skill": "crafting", "tool": "hammer", "accessories": ["apron", "glasses"],
		"places": [["workshop", "Carving at the workshop", "work"], ["workshop", "Mending tools", "work"]],
		"tasks": {"build": 0.6, "wood": 0.5, "stone": 0.3, "farm": 0.2}},
	"trader": {"name": "Trader", "skill": "trade", "tool": "ledger", "accessories": ["satchel", "scarf"],
		"places": [["storage", "Counting stock at the storehouse", "trade"], ["plaza", "Bartering at the meeting circle", "trade"]],
		"tasks": {"wood": 0.4, "stone": 0.3, "farm": 0.3, "build": 0.3}},
	"woodcutter": {"name": "Woodcutter", "skill": "woodcutting", "tool": "hammer", "accessories": ["backpack", "cloak"],
		"places": [["woodlot", "Felling trees in the woodlot", "work"], ["woodlot", "Splitting logs", "work"]],
		"tasks": {"wood": 0.95, "build": 0.5, "stone": 0.4, "farm": 0.2}},
	"stonemason": {"name": "Stonemason", "skill": "stonework", "tool": "hammer", "accessories": ["tool_belt", "headband"],
		"places": [["quarry", "Cutting stone at the quarry", "work"], ["build_site", "Laying stone at the building site", "work"]],
		"tasks": {"stone": 0.95, "build": 0.7, "wood": 0.3, "farm": 0.1}},
	"fisher": {"name": "Fisher", "skill": "fishing", "tool": "basket", "accessories": ["wide_hat", "satchel"],
		"places": [["riverbank", "Fishing at the riverbank", "gather"], ["bridge", "Casting lines from the bridge", "gather"]],
		"tasks": {"farm": 0.5, "wood": 0.4, "stone": 0.2, "build": 0.3}},
	"cook": {"name": "Cook", "skill": "cooking", "tool": "basket", "accessories": ["apron", "headwrap"],
		"places": [["storage", "Cooking at the storehouse", "work"], ["garden", "Gathering vegetables", "gather"]],
		"tasks": {"farm": 0.7, "wood": 0.4, "build": 0.2, "stone": 0.1}},
	"weaver": {"name": "Weaver", "skill": "weaving", "tool": "", "accessories": ["scarf", "earrings"],
		"places": [["workshop", "Weaving at the workshop", "work"], ["plaza", "Spinning yarn at the meeting circle", "work"]],
		"tasks": {"farm": 0.4, "build": 0.3, "wood": 0.2, "stone": 0.1}},
}


static func ids() -> Array:
	return CATALOG.keys()


static func info(profession: String) -> Dictionary:
	return CATALOG.get(profession, CATALOG["farmer"])


static func label(profession: String) -> String:
	return String(info(profession)["name"])


## The profession that best uses someone's strongest skill.
static func best_for(skills: Dictionary) -> String:
	var best := "farmer"
	var best_value := -1.0
	for id in CATALOG:
		var value := float(skills.get(String(CATALOG[id]["skill"]), 0.0))
		if value > best_value:
			best_value = value
			best = String(id)
	return best


## A daily timetable for this person. Early risers and hard workers start
## sooner, sociable people spend lunch and evenings at the meeting circle,
## quieter ones rest at home.
static func schedule_for(person: Person, rng: RandomNumberGenerator) -> Array:
	var job := info(person.profession)
	var places: Array = job["places"]
	var conscientious := person.trait_weight("conscientiousness")
	var social := person.trait_weight("extraversion")
	var wake := snappedf(lerpf(8.0, 6.0, conscientious) + rng.randf_range(-0.25, 0.25), 0.25)
	var bedtime := snappedf(lerpf(21.5, 23.0, social) + rng.randf_range(-0.25, 0.25), 0.25)
	var schedule: Array = []
	var first: Array = places[0]
	var second: Array = places[places.size() - 1]
	schedule.append({"hour": wake, "activity": "work", "location": first[0], "label": first[1], "anim": first[2]})
	if social > 0.45:
		schedule.append({"hour": 12.0 + rng.randf_range(-0.25, 0.25), "activity": "socialize", "location": "plaza",
			"label": "Eating lunch at the meeting circle"})
	else:
		schedule.append({"hour": 12.0 + rng.randf_range(-0.25, 0.25), "activity": "rest", "location": "home",
			"label": "Eating lunch at home"})
	schedule.append({"hour": 13.0, "activity": "work", "location": second[0], "label": second[1], "anim": second[2]})
	schedule.append({"hour": lerpf(16.5, 18.0, conscientious), "activity": "wander", "location": "",
		"label": "Strolling around the village"})
	if social > 0.35:
		schedule.append({"hour": 19.0 + rng.randf_range(0.0, 0.5), "activity": "socialize", "location": "plaza",
			"label": "Chatting at the meeting circle"})
	else:
		schedule.append({"hour": 19.0 + rng.randf_range(0.0, 0.5), "activity": "rest", "location": "home",
			"label": "Reading by the fire at home"})
	schedule.append({"hour": bedtime, "activity": "sleep", "location": "home"})
	return schedule


## How keen they are on a job the player asks for (0..1).
static func task_preference(person: Person, kind: StringName) -> float:
	var tasks: Dictionary = info(person.profession)["tasks"]
	return float(tasks.get(String(kind), 0.3))
