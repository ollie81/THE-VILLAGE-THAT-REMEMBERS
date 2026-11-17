class_name VillagerBrain
extends RefCounted
## Decides what a villager wants to do. Milestone 1 ships ScheduleBrain only.
## Planned replacements (needs, emotions, personality-weighted utility AI,
## relationships) implement the same single method, so Villager never changes.


func choose_activity(_villager: Node, _hour: float) -> VillagerActivity:
	return null
