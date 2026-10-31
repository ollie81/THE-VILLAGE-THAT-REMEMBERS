class_name MemoryLog
extends RefCounted
## A villager's episodic memory: a bounded list of things that happened.
## Milestone 1 records conversations with the player. Later systems will add
## gifts, conflicts, births, deaths and village events, and let memories fade
## or be shared as gossip.

const MAX_ENTRIES := 400

## Each entry: { "type": String, "subject": String, "day": int, "hour": float, "detail": String }
var entries: Array[Dictionary] = []


func add(type: String, subject: String, day: int, hour: float, detail: String = "") -> void:
	entries.append({"type": type, "subject": subject, "day": day, "hour": hour, "detail": detail})
	if entries.size() > MAX_ENTRIES:
		entries.pop_front()


func count(type: String, subject: String) -> int:
	var total := 0
	for entry in entries:
		if entry["type"] == type and entry["subject"] == subject:
			total += 1
	return total


## Most recent matching entry, or an empty dictionary.
func last(type: String, subject: String) -> Dictionary:
	for i in range(entries.size() - 1, -1, -1):
		var entry := entries[i]
		if entry["type"] == type and entry["subject"] == subject:
			return entry
	return {}


## All entries of a type about a subject, oldest first.
func find(type: String, subject: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for entry in entries:
		if entry["type"] == type and entry["subject"] == subject:
			found.append(entry)
	return found


func has_detail(type: String, subject: String, detail: String) -> bool:
	for entry in entries:
		if entry["type"] == type and entry["subject"] == subject and entry["detail"] == detail:
			return true
	return false


func to_array() -> Array:
	return entries.duplicate(true)


func from_array(data: Array) -> void:
	entries.clear()
	for item in data:
		if item is Dictionary:
			entries.append({
				"type": String(item.get("type", "")),
				"subject": String(item.get("subject", "")),
				"day": int(item.get("day", 1)),
				"hour": float(item.get("hour", 0.0)),
				"detail": String(item.get("detail", "")),
			})
