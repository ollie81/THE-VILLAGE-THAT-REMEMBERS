class_name AnimalSpecies
extends RefCounted
## Every kind of animal: its model (Quaternius Farm Animals and Animal Pack
## Vol.2, CC0), how big it is in the world, which way the model faces, its
## animations, how it moves, where it lives and what it costs.
##
## scale/yaw were measured from each model's skeleton: the farm animals face
## +Z, the dog, cat and wolf face +X (so they're turned a quarter).
## Animals without a walk animation (sheep, pig, pug) walk with a bobbing,
## swaying gait done in code.

const DIR := "res://assets/quaternius/animals/"

const SPECIES := {
	&"horse": {"name": "Horse", "model": "Horse", "scale": 0.27, "yaw": 0.0, "walk": 1.4, "run": 5.5,
		"idle": "Idle", "walk_anim": "Walk", "run_anim": "Run", "home": "stable", "price": 40,
		"eats": true, "skittish": 0.2, "sound": "neigh", "names": ["Bramble", "Clover", "Juniper", "Ember", "Willow"],
		"radius": 0.7, "about": "A riding horse. Needs a stable."},
	&"cow": {"name": "Cow", "model": "Cow", "scale": 0.26, "yaw": 0.0, "walk": 0.9, "run": 3.0,
		"idle": "Idle", "walk_anim": "WalkSlow", "run_anim": "Run", "home": "pen", "price": 25,
		"eats": true, "skittish": 0.1, "sound": "moo", "milk": true, "names": ["Daisy", "Buttercup", "Bella", "Hazel", "Poppy"],
		"radius": 0.7, "about": "Gives milk every day (2 food). Lives in a pen."},
	&"sheep": {"name": "Sheep", "model": "Sheep", "scale": 0.22, "yaw": 0.0, "walk": 0.8, "run": 3.2,
		"idle": "Idle", "walk_anim": "", "run_anim": "Jump", "home": "pen", "price": 15,
		"eats": true, "skittish": 0.7, "sound": "baa", "names": ["Woolly", "Cotton", "Fluff", "Nimbus", "Pebble"],
		"radius": 0.5, "about": "A friendly sheep. Lives in a pen."},
	&"pig": {"name": "Pig", "model": "Pig", "scale": 0.17, "yaw": 0.0, "walk": 0.8, "run": 2.8,
		"idle": "Idle", "walk_anim": "", "run_anim": "Jump", "home": "pen", "price": 15,
		"eats": true, "skittish": 0.4, "sound": "oink", "names": ["Truffle", "Rosie", "Biscuit", "Porky", "Acorn"],
		"radius": 0.5, "about": "Roots about happily. Lives in a pen."},
	&"dog": {"name": "Dog", "model": "Dog", "scale": 0.14, "yaw": -PI * 0.5, "walk": 1.6, "run": 5.0,
		"idle": "Idle", "walk_anim": "Walking", "run_anim": "Walking", "home": "house", "price": 12,
		"eats": false, "skittish": 0.0, "sound": "bark", "follows": true, "names": ["Rufus", "Scout", "Biscuit", "Pepper", "Max"],
		"radius": 0.4, "about": "Follows you when you ask. Lives by your home."},
	&"pug": {"name": "Small dog", "model": "Pug", "scale": 0.19, "yaw": 0.0, "walk": 1.2, "run": 3.5,
		"idle": "Idle", "walk_anim": "", "run_anim": "Jump", "home": "house", "price": 10,
		"eats": false, "skittish": 0.0, "sound": "bark", "follows": true, "names": ["Pip", "Bean", "Nugget", "Toffee"],
		"radius": 0.3, "about": "A small dog. Follows you when you ask."},
	&"cat": {"name": "Cat", "model": "Cat", "scale": 0.092, "yaw": -PI * 0.5, "walk": 1.0, "run": 4.0,
		"idle": "Idle", "walk_anim": "Walking", "run_anim": "Walking", "home": "house", "price": 10,
		"eats": false, "skittish": 0.6, "sound": "meow", "names": ["Misty", "Tabby", "Shadow", "Ginger", "Socks"],
		"radius": 0.3, "about": "Comes and goes as it pleases. Lives by your home."},
}

## The order they're offered in the Shop.
const SHOP_ORDER: Array[StringName] = [&"dog", &"cat", &"pug", &"sheep", &"pig", &"cow", &"horse"]
## How many animals each home holds.
const CAPACITY := {"pen": 4, "stable": 2, "house": 3}


static func info(species: StringName) -> Dictionary:
	return SPECIES.get(species, {})


static func home_label(home_kind: String) -> String:
	return {"pen": "an animal pen", "stable": "a stable", "house": "your home"}.get(home_kind, home_kind)
