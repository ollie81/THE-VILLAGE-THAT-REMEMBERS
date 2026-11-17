class_name Activities
extends RefCounted
## Everything there is to do, and when it opens up. The Journal lists the
## open ones with how, where and which tool, and the locked ones with what
## opens them, so activities arrive one by one instead of all at once.

## id -> {name, how, where, tool}
const LIST := [
	{"id": "gather", "name": "Chop and mine", "how": "Walk up to any tree and tap Chop, or a rock and tap Mine. Pick herbs in the meadows.",
		"where": "Trees and rocks all round the village", "tool": "Axe and pickaxe (always with you)"},
	{"id": "help", "name": "Help the villagers", "how": "Talk to people with a ! over them and do what they ask: bring something, pass on a message, check on someone.",
		"where": "Around the village", "tool": ""},
	{"id": "build", "name": "Build", "how": "Tap Build, choose something, place it on green ground, then tap Build at the site until it's done.",
		"where": "Open ground", "tool": "Hammer"},
	{"id": "craft", "name": "Craft at the workshop", "how": "Tools, a fishing rod, a sword and shield, and later a steel edge for the sword.",
		"where": "The workshop bench", "tool": "Hammer"},
	{"id": "farm", "name": "Farm", "how": "Build a farm plot, tap Plant, water the crops at a well, and Harvest when they're ripe.",
		"where": "Your farm plots", "tool": "Hoe and watering can"},
	{"id": "hens", "name": "Keep hens", "how": "Build a chicken coop. Feed the hens (1 herb) and collect their eggs every morning (1 food each).",
		"where": "Your chicken coops", "tool": ""},
	{"id": "fish", "name": "Fish", "how": "Make a fishing rod at the workshop, stand on the river bank or the bridge and tap Fish. Tap Reel when a fish bites.",
		"where": "The river east of the village", "tool": "Fishing rod"},
	{"id": "trade", "name": "Trade", "how": "Swap what you have plenty of for what you need.",
		"where": "The market stalls by the meeting circle", "tool": ""},
	{"id": "explore", "name": "Explore", "how": "Three old chests are hidden in the woods round the village.",
		"where": "The woods beyond the houses", "tool": ""},
	{"id": "cook", "name": "Cook", "how": "Cook stew at the hearth in your house (2 food, 1 herb). Eat it to heal in a fight.",
		"where": "Your house", "tool": ""},
	{"id": "hunt", "name": "Chase off creatures", "how": "Attack, Block and Dodge appear when thornlings are near. Clear the west woods for Tomas.",
		"where": "The west woods", "tool": "Sword and shield"},
	{"id": "festival", "name": "Festivals", "how": "From the second week, a festival every week with goals and rewards.",
		"where": "The meeting circle", "tool": ""},
]


static func unlocked(id: String) -> bool:
	match id:
		"farm":
			return WorldClock.day >= 2 or GameState.objective_index >= 2
		"hens":
			return WorldClock.day >= 3 or GameState.completed_structures(&"farm_plot") > 0
		"fish":
			return bool(GameState.get_flag(&"has_tools")) or Fishing.has_rod()
		"trade":
			return TradePanel.is_open_today()
		"explore":
			return WorldClock.day >= 2
		"cook":
			return GameState.completed_structures(&"house") > 0
		"hunt":
			return PlayerCombat.is_armed()
		"festival":
			return WorldClock.day >= 8
	return true


## What opens a locked activity.
static func unlock_hint(id: String) -> String:
	match id:
		"farm":
			return "Opens on day 2."
		"hens":
			return "Opens on day 3, or once you've built a farm plot."
		"fish":
			return "Craft tools at the workshop first; then you can make a rod."
		"trade":
			return "The traders come from day %d." % TradePanel.OPENS_DAY
		"explore":
			return "Opens on day 2."
		"cook":
			return "Build your own house first."
		"hunt":
			return "Forge a sword and shield at the workshop."
		"festival":
			return "From the second week."
	return ""


## A little progress where it helps ("2 / 3 chests found").
static func progress(id: String) -> String:
	match id:
		"explore":
			return "%d / %d chests found" % [Treasure.found(), Treasure.REWARDS.size()]
		"fish":
			return "%d fish caught" % int(GameState.get_flag(&"fish_caught", 0)) if Fishing.has_rod() else "no rod yet"
		"hunt":
			var woods := Thornwood.instance
			if woods:
				return "West woods cleared %d time%s" % [woods.times_cleared, "" if woods.times_cleared == 1 else "s"]
	return ""


static func open_count() -> int:
	return LIST.filter(func(a): return unlocked(String(a["id"]))).size()
