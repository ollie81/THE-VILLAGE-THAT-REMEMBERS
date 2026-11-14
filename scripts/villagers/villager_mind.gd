class_name VillagerMind
extends RefCounted
## Everything a villager carries inside: memories and how they feel about
## others. Milestone 2 adds opinions (affection and trust) that the player's
## choices and village gossip change.
## Still to come: needs (hunger, rest, social), moods, family links, ambitions.

const OPINION_LIMIT := 100.0

var owner_id: String = ""
var memory := MemoryLog.new()
## other character id -> { "familiarity": int, "affection": float, "trust": float }
var relationships: Dictionary = {}


func _init(id: String = "") -> void:
	owner_id = id


func get_familiarity(other_id: String) -> int:
	var relation: Dictionary = relationships.get(other_id, {})
	return int(relation.get("familiarity", 0))


func record_interaction(other_id: String, type: String, day: int, hour: float) -> void:
	memory.add(type, other_id, day, hour)
	var relation: Dictionary = relationships.get(other_id, {})
	relation["familiarity"] = int(relation.get("familiarity", 0)) + 1
	relationships[other_id] = relation


# --- Opinions -----------------------------------------------------------------------

## How warmly this villager feels about someone (-100..100).
func get_affection(other_id: String) -> float:
	var relation: Dictionary = relationships.get(other_id, {})
	return float(relation.get("affection", 0.0))


## How much this villager relies on someone's word (-100..100).
func get_trust(other_id: String) -> float:
	var relation: Dictionary = relationships.get(other_id, {})
	return float(relation.get("trust", 0.0))


func adjust_opinion(other_id: String, affection: float, trust: float) -> void:
	var relation: Dictionary = relationships.get(other_id, {})
	relation["affection"] = clampf(float(relation.get("affection", 0.0)) + affection, -OPINION_LIMIT, OPINION_LIMIT)
	relation["trust"] = clampf(float(relation.get("trust", 0.0)) + trust, -OPINION_LIMIT, OPINION_LIMIT)
	relationships[other_id] = relation


## A short description of the relationship, for the info card.
func opinion_label(other_id: String) -> String:
	var affection := get_affection(other_id)
	if affection >= 40.0:
		return "Close friend"
	if affection >= 15.0:
		return "Friendly"
	if affection <= -40.0:
		return "Dislikes you"
	if affection <= -15.0:
		return "Wary of you"
	if get_familiarity(other_id) < 2:
		return "Getting to know you"
	return "Neutral"


func is_hostile(other_id: String) -> bool:
	return get_affection(other_id) <= -40.0


# --- Persistence ---------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"memory": memory.to_array(), "relationships": relationships.duplicate(true)}


func from_dict(data: Dictionary) -> void:
	memory.from_array(data.get("memory", []))
	var saved: Variant = data.get("relationships", {})
	relationships = saved.duplicate(true) if saved is Dictionary else {}
