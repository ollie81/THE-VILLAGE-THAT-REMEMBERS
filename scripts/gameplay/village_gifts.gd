class_name VillageGifts
extends Node
## What a watched ad gives the village (see AdRewards).

static var instance: VillageGifts


func _ready() -> void:
	name = "VillageGifts"
	instance = self
	AdRewards.reward_granted.connect(apply)


func _exit_tree() -> void:
	if instance == self:
		instance = null
	if AdRewards.reward_granted.is_connected(apply):
		AdRewards.reward_granted.disconnect(apply)


## Is this gift useful right now? (Returns why not, or "".)
static func blocked_reason(reward: StringName) -> String:
	match reward:
		&"harvest":
			if _growing_plots().is_empty():
				return "Plant some crops first."
		&"traveller":
			if PopulationDirector.instance == null or not Population.has_room_for_more():
				return "The village is full."
			if not Population.visitors().is_empty():
				return "A traveller is already waiting at the meeting circle."
	return ""


func apply(reward: StringName) -> void:
	match reward:
		&"caravan":
			GameState.add(&"wood", 8)
			GameState.add(&"stone", 5)
			GameState.add(&"food", 6)
			GameManager.notify("A merchant's caravan stopped by and left 8 wood, 5 stone and 6 food.")
		&"harvest":
			var plots := _growing_plots()
			for plot in plots:
				plot.grow(PlacedStructure.CROP_HOURS)
			GameManager.notify("A blessed harvest! %d field%s ripened overnight." % [plots.size(), "" if plots.size() == 1 else "s"])
		&"feast":
			for villager in GameManager.villagers:
				villager.mind.adjust_opinion(GameManager.PLAYER_ID, 3.0, 1.0)
				if villager.person:
					villager.person.happiness = minf(villager.person.happiness + 15.0, 100.0)
					villager.person.unhappy_days = 0
			Population.log_event("feast", "The village shared a feast.", [])
			GameManager.notify("A village feast! Everyone is a little happier tonight.")
		&"traveller":
			if PopulationDirector.instance:
				PopulationDirector.instance.bring_traveller()


static func _growing_plots() -> Array:
	if StructureManager.instance == null:
		return []
	return StructureManager.instance.structures().filter(func(s):
		return s.get_type() == &"farm_plot" and s.is_complete() and s.is_planted() and not s.is_ripe())
