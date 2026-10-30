class_name VillagerData
extends Resource
## Static identity of a villager, authored as a .tres file in data/villagers.
## Runtime state (memories, relationships, mood) lives in VillagerMind instead,
## so this resource never changes while the game runs.

@export var id: StringName = &""
@export var display_name: String = ""
@export var age: int = 30
@export var role: String = ""
@export var traits: PackedStringArray = PackedStringArray()
@export_multiline var biography: String = ""
@export var appearance: CharacterAppearance

@export_group("Daily life")
## Location id of this villager's home (see VillageLayout).
@export var home_location: String = ""
@export var walk_speed: float = 1.6
## Entries: { "hour": float, "activity": String, "location": String,
## optional "label": String, optional "anim": String }.
## Activities: sleep, rest, work, gather, trade, explore, socialize, wander.
@export var schedule: Array = []
## Places this villager likes to stroll to during "wander".
@export var wander_locations: PackedStringArray = PackedStringArray()

@export_group("Dialogue")
@export var first_meeting_lines: PackedStringArray = PackedStringArray()
@export var returning_lines: PackedStringArray = PackedStringArray()
## activity kind -> a line about what they are doing right now.
@export var activity_comments: Dictionary = {}

@export_group("Future systems")
## Personality weights (0..1) reserved for the decision-making system planned
## after Milestone 1. Authored now so every villager has a stable identity;
## nothing reads them yet.
@export var personality: Dictionary = {}
