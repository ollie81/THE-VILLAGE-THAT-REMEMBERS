class_name HouseDesigns
extends RefCounted
## The houses the player can build: four sizes, three architectural styles,
## and the choices that make each one theirs (walls, roof, door, windows,
## floor). A house's design is saved on its structure record ("design").

## Sizes, smallest first: each can be expanded into the next.
const SIZES: Array[StringName] = [&"house", &"house_medium", &"house_large", &"manor"]

## Footprint (outside walls, metres), storeys outside, and the inside's size.
const SIZE_INFO := {
	&"house": {"label": "Small house", "w": 6.0, "d": 4.4, "storeys": 1, "inside": Vector2(8.0, 6.0)},
	&"house_medium": {"label": "Medium house", "w": 8.0, "d": 6.2, "storeys": 1, "inside": Vector2(10.0, 8.0)},
	&"house_large": {"label": "Large house", "w": 10.0, "d": 8.0, "storeys": 1, "inside": Vector2(12.0, 10.0)},
	&"manor": {"label": "Manor", "w": 13.6, "d": 9.6, "storeys": 2, "inside": Vector2(16.0, 12.0)},
}

const STYLES := ["timber", "stone", "painted"]
const STYLE_LABELS := {"timber": "Timber-framed", "stone": "Stone", "painted": "Painted boards"}

## Colour choices for each part (names shown in the Design panel).
const WALLS := [
	["Cream", Color(0.9, 0.84, 0.72)], ["Honey", Color(0.88, 0.74, 0.5)], ["Rose", Color(0.86, 0.66, 0.6)],
	["Sage", Color(0.7, 0.78, 0.64)], ["Sky", Color(0.66, 0.76, 0.84)], ["Grey stone", Color(0.62, 0.6, 0.57)],
	["Lavender", Color(0.74, 0.68, 0.84)], ["Mint", Color(0.66, 0.86, 0.76)],
]
const ROOFS := [
	["Terracotta", Color(0.64, 0.29, 0.2)], ["Slate", Color(0.32, 0.34, 0.38)], ["Thatch", Color(0.76, 0.62, 0.34)],
	["Teal", Color(0.3, 0.52, 0.5)], ["Plum", Color(0.42, 0.26, 0.36)],
	["Copper", Color(0.66, 0.42, 0.24)], ["Mossy", Color(0.36, 0.48, 0.26)],
]
const DOORS := [
	["Oak", Color(0.42, 0.28, 0.16)], ["Red", Color(0.62, 0.2, 0.16)], ["Green", Color(0.26, 0.44, 0.28)],
	["Blue", Color(0.24, 0.36, 0.56)], ["Black", Color(0.14, 0.12, 0.11)],
	["Gilded", Color(0.8, 0.64, 0.26)],
]
## Extra paints unlocked with Village Credits in the Shop (everything else is
## free, as it always was). key -> {index: unlock id}.
const PREMIUM := {
	"wall": {6: "paint_lavender", 7: "paint_mint"},
	"roof": {5: "paint_copper", 6: "paint_mossy"},
	"door": {5: "paint_gilded"},
}
const PAINT_UNLOCKS := [
	{"id": "paint_lavender", "name": "Lavender wall paint", "price": 25},
	{"id": "paint_mint", "name": "Mint wall paint", "price": 25},
	{"id": "paint_copper", "name": "Copper roof tiles", "price": 30},
	{"id": "paint_mossy", "name": "Mossy roof", "price": 30},
	{"id": "paint_gilded", "name": "Gilded front door", "price": 20},
]


## Whether choice `index` of `key` can be picked (premium paints need unlocking).
static func is_unlocked(key: String, index: int) -> bool:
	var id := String((PREMIUM.get(key, {}) as Dictionary).get(index, ""))
	return id == "" or (VillageCredits.instance != null and VillageCredits.instance.owns(id))


## Steps `by` through `count` choices of `key`, skipping locked ones.
static func _next_unlocked(key: String, current: int, by: int, count: int) -> int:
	var i := current
	for _n in count:
		i = posmod(i + (1 if by >= 0 else -1), count)
		if is_unlocked(key, i):
			return i
	return current
const WINDOWS := ["shutters", "arched", "lattice"]
const WINDOW_LABELS := {"shutters": "With shutters", "arched": "Arched", "lattice": "Lattice panes"}
const FLOORS := ["planks", "stone", "tiles", "carpet"]
const FLOOR_LABELS := {"planks": "Oak planks", "stone": "Flagstones", "tiles": "Red tiles", "carpet": "Wool carpet"}


static func is_house(type: StringName) -> bool:
	return type in SIZES


static func size_info(type: StringName) -> Dictionary:
	return SIZE_INFO.get(type, SIZE_INFO[&"house"])


## The next size up, or "" for the manor.
static func next_size(type: StringName) -> StringName:
	var i := SIZES.find(type)
	return SIZES[i + 1] if i >= 0 and i < SIZES.size() - 1 else &""


## The look a house starts with (and older saves get): close to the small
## houses the game always had.
static func default_design() -> Dictionary:
	return {"style": "timber", "wall": 0, "roof": 3, "door": 0, "window": "shutters", "floor": "planks"}


## A design made safe: every key present and every choice in range.
static func normalized(design: Variant) -> Dictionary:
	var d := default_design()
	if design is Dictionary:
		for key in d:
			if (design as Dictionary).has(key):
				d[key] = design[key]
	if not String(d["style"]) in STYLES:
		d["style"] = "timber"
	d["wall"] = clampi(int(d["wall"]), 0, WALLS.size() - 1)
	d["roof"] = clampi(int(d["roof"]), 0, ROOFS.size() - 1)
	d["door"] = clampi(int(d["door"]), 0, DOORS.size() - 1)
	if not String(d["window"]) in WINDOWS:
		d["window"] = "shutters"
	if not String(d["floor"]) in FLOORS:
		d["floor"] = "planks"
	return d


## The design on a structure record (normalised).
static func of(record: Dictionary) -> Dictionary:
	return normalized(record.get("design", {}))


static func wall_color(d: Dictionary) -> Color:
	return WALLS[int(d["wall"])][1]


static func roof_color(d: Dictionary) -> Color:
	return ROOFS[int(d["roof"])][1]


static func door_color(d: Dictionary) -> Color:
	return DOORS[int(d["door"])][1]


## Every choice in the Design panel, in order: [key, label, option labels].
static func options() -> Array:
	return [
		["style", "Style", STYLES.map(func(s): return STYLE_LABELS[s])],
		["wall", "Walls", WALLS.map(func(w): return w[0])],
		["roof", "Roof", ROOFS.map(func(r): return r[0])],
		["door", "Door", DOORS.map(func(o): return o[0])],
		["window", "Windows", WINDOWS.map(func(w): return WINDOW_LABELS[w])],
		["floor", "Floor inside", FLOORS.map(func(f): return FLOOR_LABELS[f])],
	]


## The design with one choice moved forward (+1) or back (-1).
static func step(d: Dictionary, key: String, by: int) -> Dictionary:
	var out := d.duplicate()
	match key:
		"style":
			out["style"] = STYLES[posmod(STYLES.find(String(d["style"])) + by, STYLES.size())]
		"wall":
			out["wall"] = _next_unlocked("wall", int(d["wall"]), by, WALLS.size())
		"roof":
			out["roof"] = _next_unlocked("roof", int(d["roof"]), by, ROOFS.size())
		"door":
			out["door"] = _next_unlocked("door", int(d["door"]), by, DOORS.size())
		"window":
			out["window"] = WINDOWS[posmod(WINDOWS.find(String(d["window"])) + by, WINDOWS.size())]
		"floor":
			out["floor"] = FLOORS[posmod(FLOORS.find(String(d["floor"])) + by, FLOORS.size())]
	return out


## The label of the current choice for `key`.
static func choice_label(d: Dictionary, key: String) -> String:
	match key:
		"style":
			return STYLE_LABELS[String(d["style"])]
		"wall":
			return WALLS[int(d["wall"])][0]
		"roof":
			return ROOFS[int(d["roof"])][0]
		"door":
			return DOORS[int(d["door"])][0]
		"window":
			return WINDOW_LABELS[String(d["window"])]
		"floor":
			return FLOOR_LABELS[String(d["floor"])]
	return ""
