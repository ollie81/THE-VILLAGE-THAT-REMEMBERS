class_name VillagerActivity
extends RefCounted
## What a villager intends to do, and where. Produced by a VillagerBrain and
## carried out by Villager.

const DEFAULT_ANIMATIONS := {
	"work": &"work",
	"gather": &"gather",
	"trade": &"talk",
	"socialize": &"talk",
}

var kind: StringName = &"wander"
var location_id: String = ""
var label: String = ""
var animation: StringName = &""
var start_hour: float = 0.0


static func from_entry(entry: Dictionary) -> VillagerActivity:
	var activity := VillagerActivity.new()
	activity.kind = StringName(String(entry.get("activity", "wander")))
	activity.location_id = String(entry.get("location", ""))
	activity.label = String(entry.get("label", ""))
	activity.animation = StringName(String(entry.get("anim", "")))
	activity.start_hour = float(entry.get("hour", 0.0))
	return activity


## Identity used to detect when the brain changes its mind.
func key() -> String:
	return "%s@%s@%.2f" % [kind, location_id, start_hour]


func get_animation() -> StringName:
	if animation != &"":
		return animation
	return DEFAULT_ANIMATIONS.get(String(kind), &"idle")


func is_sleep() -> bool:
	return kind == &"sleep"


func is_wander() -> bool:
	return kind == &"wander" or location_id == ""


func describe(location_label: String) -> String:
	if label != "":
		return label
	match kind:
		&"sleep":
			return "Sleeping at home"
		&"rest":
			return "Resting at home"
		&"socialize":
			return "Chatting at the meeting circle"
		&"wander":
			return "Strolling around the village"
		&"gather":
			return "Gathering at %s" % location_label
		&"explore":
			return "Exploring %s" % location_label
		&"trade":
			return "Trading at %s" % location_label
	return "Working at %s" % location_label
