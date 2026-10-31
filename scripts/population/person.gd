class_name Person
extends RefCounted
## One person's life record: who they are, where they live, who their family
## is, and what has happened to them. Every villager has one (the five
## founders too). The record outlives the 3D villager: people who have left
## the village or died stay in the population history and family trees.
##
## Everything here is plain data so it saves to JSON as-is.

## Days in one village year: people age a year every YEAR_DAYS game days.
const YEAR_DAYS := 30

const STATUS_VISITOR := "visitor"
const STATUS_RESIDENT := "resident"
const STATUS_LEFT := "left"
const STATUS_DEAD := "dead"

const STAGE_CHILD := "child"
const STAGE_TEEN := "teen"
const STAGE_ADULT := "adult"
const STAGE_ELDER := "elder"

var id: String = ""
var first_name: String = ""
var family_name: String = ""
## "female" or "male". Used for names and body shape, nothing else.
var sex: String = "female"
## The game day of their birth (negative: born before the story began).
var birth_day: int = 0
var profession: String = ""
## Skill name -> 0..1 (see Professions.SKILLS).
var skills: Dictionary = {}
var traits: PackedStringArray = PackedStringArray()
## openness, conscientiousness, extraversion, agreeableness, neuroticism, adventure
var personality: Dictionary = {}
## { id, text, progress (0..1), done }
var ambition: Dictionary = {}
var biography: String = ""
## CharacterAppearance as a dictionary (see AppearanceCodec).
var appearance: Dictionary = {}

var status: String = STATUS_VISITOR
var founder: bool = false
## Founders keep their hand-written VillagerData.
var data_path: String = ""
## How they came: founder, traveller, invited, born, adopted.
var origin: String = "traveller"
## Who invited them (person id), if anyone.
var invited_by: String = ""
## Home location id ("home_mara", "home_s3", "camp"), "" while homeless.
var home: String = ""
var arrived_day: int = 1
var departed_day: int = -1

# --- Family -----------------------------------------------------------------------
var partner: String = ""
var partnered_day: int = -1
var married: bool = false
var parents: Array = []
var children: Array = []
## Other kin and close ties outside the parent/child line: id -> "sibling",
## "cousin", "friend"...
var relatives: Dictionary = {}

# --- Wellbeing ----------------------------------------------------------------------
## 0..100. Updated daily by SocialLife.
var happiness: float = 60.0
var unhappy_days: int = 0
var homeless_days: int = 0
var has_invited: bool = false
## Set when they've decided to go; they leave the next morning.
var leaving: bool = false


func full_name() -> String:
	return "%s %s" % [first_name, family_name] if family_name != "" else first_name


func age(today: int = -1) -> int:
	var day := today if today >= 0 else WorldClock.day
	return maxi(int(floor(float(day - birth_day) / YEAR_DAYS)), 0)


func life_stage(today: int = -1) -> String:
	return stage_for_age(age(today))


static func stage_for_age(years: int) -> String:
	if years < 13:
		return STAGE_CHILD
	if years < 18:
		return STAGE_TEEN
	if years < 60:
		return STAGE_ADULT
	return STAGE_ELDER


func is_present() -> bool:
	return status == STATUS_RESIDENT or status == STATUS_VISITOR


func is_resident() -> bool:
	return status == STATUS_RESIDENT


func trait_weight(key: String) -> float:
	return float(personality.get(key, 0.5))


func to_dict() -> Dictionary:
	return {
		"id": id, "first_name": first_name, "family_name": family_name, "sex": sex,
		"birth_day": birth_day, "profession": profession, "skills": skills.duplicate(),
		"traits": Array(traits), "personality": personality.duplicate(), "ambition": ambition.duplicate(),
		"biography": biography, "appearance": appearance.duplicate(true),
		"status": status, "founder": founder, "data_path": data_path, "origin": origin,
		"invited_by": invited_by, "home": home, "arrived_day": arrived_day, "departed_day": departed_day,
		"partner": partner, "partnered_day": partnered_day, "married": married,
		"parents": parents.duplicate(), "children": children.duplicate(), "relatives": relatives.duplicate(),
		"happiness": happiness, "unhappy_days": unhappy_days, "homeless_days": homeless_days,
		"has_invited": has_invited, "leaving": leaving,
	}


static func from_dict(d: Dictionary) -> Person:
	var p := Person.new()
	p.id = String(d.get("id", ""))
	p.first_name = String(d.get("first_name", ""))
	p.family_name = String(d.get("family_name", ""))
	p.sex = String(d.get("sex", "female"))
	p.birth_day = int(d.get("birth_day", 0))
	p.profession = String(d.get("profession", ""))
	p.skills = _dict(d.get("skills"))
	p.traits = PackedStringArray(d.get("traits", []))
	p.personality = _dict(d.get("personality"))
	p.ambition = _dict(d.get("ambition"))
	p.biography = String(d.get("biography", ""))
	p.appearance = _dict(d.get("appearance"))
	p.status = String(d.get("status", STATUS_RESIDENT))
	p.founder = bool(d.get("founder", false))
	p.data_path = String(d.get("data_path", ""))
	p.origin = String(d.get("origin", "traveller"))
	p.invited_by = String(d.get("invited_by", ""))
	p.home = String(d.get("home", ""))
	p.arrived_day = int(d.get("arrived_day", 1))
	p.departed_day = int(d.get("departed_day", -1))
	p.partner = String(d.get("partner", ""))
	p.partnered_day = int(d.get("partnered_day", -1))
	p.married = bool(d.get("married", false))
	p.parents = _array(d.get("parents"))
	p.children = _array(d.get("children"))
	p.relatives = _dict(d.get("relatives"))
	p.happiness = float(d.get("happiness", 60.0))
	p.unhappy_days = int(d.get("unhappy_days", 0))
	p.homeless_days = int(d.get("homeless_days", 0))
	p.has_invited = bool(d.get("has_invited", false))
	p.leaving = bool(d.get("leaving", false))
	return p


static func _dict(value: Variant) -> Dictionary:
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


static func _array(value: Variant) -> Array:
	return (value as Array).duplicate() if value is Array else []
