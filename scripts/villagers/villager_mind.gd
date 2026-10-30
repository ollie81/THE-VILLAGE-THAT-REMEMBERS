class_name VillagerMind
extends RefCounted
## Everything a villager carries inside: memories and how well they know
## others. This is the extension point for the planned systems:
##   - needs (hunger, rest, social) and emotions/mood
##   - relationships (trust, affection, rivalry) beyond simple familiarity
##   - family links and ambitions
## Only memory and familiarity are implemented in Milestone 1.

var owner_id: String = ""
var memory := MemoryLog.new()
## other character id -> { "familiarity": int }
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


func to_dict() -> Dictionary:
	return {"memory": memory.to_array(), "relationships": relationships.duplicate(true)}


func from_dict(data: Dictionary) -> void:
	memory.from_array(data.get("memory", []))
	var saved: Variant = data.get("relationships", {})
	relationships = saved.duplicate(true) if saved is Dictionary else {}
