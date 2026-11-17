class_name WardrobeCatalog
extends RefCounted
## Everything the player can wear. Each item changes the real character
## appearance (the same one the 3D model is built from), so what you pick is
## what the character wears in the world, with the same skeleton and
## animations.
##
## An item is free, costs Village Credits ("price"), or is unlocked by play
## ("unlock"); an item with both can be earned by play or bought early.

const TABS := ["Outfit", "Colours", "Hair", "Hats", "Extras"]

## Exclusive groups: choosing one item replaces the others in its group.
## "set" fields go straight onto the appearance; "accessory" adds one.
const ITEMS := [
	# --- Outfit shapes ---
	{"id": "shirt_trousers", "tab": "Outfit", "group": "outfit", "name": "Shirt and trousers", "set": {"tunic_length": 0.0, "sleeve_length": 1.0, "skirt_color": Color(0, 0, 0, 0)}},
	{"id": "short_sleeves", "tab": "Outfit", "group": "outfit", "name": "Short sleeves", "set": {"tunic_length": 0.0, "sleeve_length": 0.3, "skirt_color": Color(0, 0, 0, 0)}},
	{"id": "tunic", "tab": "Outfit", "group": "outfit", "name": "Tunic", "set": {"tunic_length": 0.4, "sleeve_length": 1.0, "skirt_color": Color(0, 0, 0, 0)}},
	{"id": "rolled_tunic", "tab": "Outfit", "group": "outfit", "name": "Tunic, rolled sleeves", "set": {"tunic_length": 0.4, "sleeve_length": 0.55, "skirt_color": Color(0, 0, 0, 0)}},
	{"id": "long_skirt", "tab": "Outfit", "group": "outfit", "name": "Blouse and long skirt", "price": 10, "set": {"tunic_length": 0.8, "sleeve_length": 0.8, "skirt_color": Color(0.45, 0.28, 0.35)}},
	{"id": "dress", "tab": "Outfit", "group": "outfit", "name": "Long dress", "price": 12, "set": {"tunic_length": 0.92, "sleeve_length": 0.9, "skirt_color": Color(0, 0, 0, 0)}},
	{"id": "summer_dress", "tab": "Outfit", "group": "outfit", "name": "Summer dress", "price": 12, "set": {"tunic_length": 0.75, "sleeve_length": 0.3, "skirt_color": Color(0, 0, 0, 0)}},
	# --- Hair styles ---
	{"id": "hair_short", "tab": "Hair", "group": "hair", "name": "Short", "set": {"hair_style": "short"}},
	{"id": "hair_curly", "tab": "Hair", "group": "hair", "name": "Curly", "set": {"hair_style": "curly"}},
	{"id": "hair_long", "tab": "Hair", "group": "hair", "name": "Long", "set": {"hair_style": "long"}},
	{"id": "hair_bun", "tab": "Hair", "group": "hair", "name": "Bun", "set": {"hair_style": "bun"}},
	{"id": "hair_ponytail", "tab": "Hair", "group": "hair", "name": "Ponytail", "set": {"hair_style": "ponytail"}},
	{"id": "hair_bald", "tab": "Hair", "group": "hair", "name": "Shaved", "set": {"hair_style": "bald"}},
	{"id": "hair_afro", "tab": "Hair", "group": "hair", "name": "Afro", "price": 10, "set": {"hair_style": "afro"}},
	{"id": "hair_braids", "tab": "Hair", "group": "hair", "name": "Long braids", "price": 10, "set": {"hair_style": "braids"}},
	{"id": "hair_locs", "tab": "Hair", "group": "hair", "name": "Locs", "price": 10, "set": {"hair_style": "locs"}},
	# --- Hats (one at a time) ---
	{"id": "hat_none", "tab": "Hats", "group": "hat", "name": "No hat"},
	{"id": "straw_hat", "tab": "Hats", "group": "hat", "name": "Straw hat", "accessory": "straw_hat"},
	{"id": "cap", "tab": "Hats", "group": "hat", "name": "Cap", "accessory": "cap"},
	{"id": "headband", "tab": "Hats", "group": "hat", "name": "Headband", "accessory": "headband"},
	{"id": "headwrap", "tab": "Hats", "group": "hat", "name": "Headwrap", "price": 6, "accessory": "headwrap"},
	{"id": "wide_hat", "tab": "Hats", "group": "hat", "name": "Wide-brimmed hat", "price": 8, "accessory": "wide_hat"},
	{"id": "flower_crown", "tab": "Hats", "group": "hat", "name": "Flower crown", "price": 12, "accessory": "flower_crown",
		"unlock": {"kind": "requests", "count": 3, "hint": "Help 3 villagers with their requests"}},
	# --- Extras (each on or off) ---
	{"id": "cloak", "tab": "Extras", "name": "Travelling cloak", "accessory": "cloak"},
	{"id": "backpack", "tab": "Extras", "group": "bag", "name": "Backpack", "accessory": "backpack"},
	{"id": "satchel", "tab": "Extras", "group": "bag", "name": "Satchel", "accessory": "satchel"},
	{"id": "apron", "tab": "Extras", "name": "Apron", "accessory": "apron"},
	{"id": "suspenders", "tab": "Extras", "name": "Braces", "accessory": "suspenders"},
	{"id": "flower", "tab": "Extras", "name": "Flower behind the ear", "accessory": "flower"},
	{"id": "scarf", "tab": "Extras", "name": "Scarf", "price": 6, "accessory": "scarf"},
	{"id": "glasses", "tab": "Extras", "name": "Glasses", "price": 6, "accessory": "glasses"},
	{"id": "earrings", "tab": "Extras", "name": "Earrings", "price": 6, "accessory": "earrings"},
	{"id": "necklace", "tab": "Extras", "name": "Necklace", "price": 10, "accessory": "necklace",
		"unlock": {"kind": "chests", "count": 1, "hint": "Find a hidden chest in the woods"}},
	{"id": "tool_belt", "tab": "Extras", "name": "Builder's tool belt", "accessory": "tool_belt",
		"unlock": {"kind": "buildings", "count": 3, "hint": "Finish 3 buildings"}},
	{"id": "beard", "tab": "Extras", "group": "beard", "name": "Beard", "accessory": "beard"},
	{"id": "long_beard", "tab": "Extras", "group": "beard", "name": "Long beard", "accessory": "long_beard"},
]

## What the colour swatches dye.
const COLOUR_TARGETS := [
	{"field": "shirt_color", "name": "Top"},
	{"field": "pants_color", "name": "Trousers"},
	{"field": "skirt_color", "name": "Skirt"},
	{"field": "accent_color", "name": "Cloak and trim"},
	{"field": "shoe_color", "name": "Shoes"},
	{"field": "hat_color", "name": "Hat"},
	{"field": "hair_color", "name": "Hair"},
]

## Dyes: free ones, plus rare ones that cost credits or are earned.
const DYES := [
	{"id": "linen", "color": Color(0.88, 0.84, 0.72)}, {"id": "charcoal", "color": Color(0.22, 0.22, 0.24)},
	{"id": "brown", "color": Color(0.42, 0.28, 0.17)}, {"id": "moss", "color": Color(0.36, 0.48, 0.26)},
	{"id": "forest", "color": Color(0.16, 0.34, 0.22)}, {"id": "sky", "color": Color(0.45, 0.62, 0.82)},
	{"id": "navy", "color": Color(0.17, 0.24, 0.42)}, {"id": "brick", "color": Color(0.66, 0.28, 0.2)},
	{"id": "rose", "color": Color(0.86, 0.52, 0.58)}, {"id": "mustard", "color": Color(0.82, 0.64, 0.24)},
	{"id": "lavender", "color": Color(0.62, 0.52, 0.76)}, {"id": "white", "color": Color(0.95, 0.94, 0.9)},
	{"id": "dye_crimson", "color": Color(0.72, 0.08, 0.14), "price": 6},
	{"id": "dye_royal", "color": Color(0.38, 0.16, 0.58), "price": 6},
	{"id": "dye_teal", "color": Color(0.1, 0.55, 0.55), "price": 6},
	{"id": "dye_gold", "color": Color(0.95, 0.75, 0.2), "price": 10, "unlock": {"kind": "woods", "count": 1, "hint": "Clear the west woods of thornlings"}},
]

## Hair colours (always free).
const HAIR_COLOURS := [
	Color(0.08, 0.06, 0.05), Color(0.25, 0.16, 0.1), Color(0.32, 0.2, 0.12), Color(0.5, 0.32, 0.18),
	Color(0.72, 0.5, 0.28), Color(0.88, 0.74, 0.48), Color(0.62, 0.22, 0.1), Color(0.72, 0.72, 0.7),
]


static func item(id: String) -> Dictionary:
	for entry: Dictionary in ITEMS:
		if String(entry["id"]) == id:
			return entry
	for dye: Dictionary in DYES:
		if String(dye["id"]) == id:
			return dye
	return {}


static func items_in(tab: String) -> Array:
	return ITEMS.filter(func(e): return String(e["tab"]) == tab)


## True if the player may wear `id` without paying: free, already bought, or
## unlocked by play.
static func is_owned(id: String) -> bool:
	var entry := item(id)
	if entry.is_empty():
		return false
	if int(entry.get("price", 0)) == 0 and not entry.has("unlock"):
		return true
	if VillageCredits.instance and VillageCredits.instance.owns(id):
		return true
	return entry.has("unlock") and unlock_met(entry["unlock"])


static func unlock_met(unlock: Dictionary) -> bool:
	var count := int(unlock.get("count", 1))
	match String(unlock.get("kind", "")):
		"requests":
			return int(GameState.get_flag(&"requests_done", 0)) >= count
		"chests":
			return Treasure.found() >= count
		"buildings":
			var done := 0
			for record in GameState.structures:
				if bool(record.get("complete", false)):
					done += 1
			return done >= count
		"woods":
			return Thornwood.instance != null and Thornwood.instance.times_cleared >= count
	return false


## Whether `look` is wearing item `id`.
static func is_worn(look: CharacterAppearance, id: String) -> bool:
	var entry := item(id)
	if entry.is_empty():
		return false
	if entry.has("accessory"):
		return look.has_accessory(String(entry["accessory"]))
	if entry.has("set"):
		for field in entry["set"]:
			var want: Variant = entry["set"][field]
			var have: Variant = look.get(field)
			if want is float and absf(float(have) - float(want)) > 0.01:
				return false
			if want is String and String(have) != want:
				return false
		return true
	if String(entry.get("group", "")) == "hat":  # "No hat"
		return not ITEMS.any(func(e): return String(e.get("group", "")) == "hat" and e.has("accessory") and look.has_accessory(String(e["accessory"])))
	return false


## Puts item `id` on (or, for an extra already worn, takes it off).
static func apply(look: CharacterAppearance, id: String) -> void:
	var entry := item(id)
	if entry.is_empty():
		return
	var group := String(entry.get("group", ""))
	var accessories := Array(look.accessories)
	var toggling_off := entry.has("accessory") and look.has_accessory(String(entry["accessory"])) and group != "hat"
	if group != "":
		for other: Dictionary in ITEMS:
			if String(other.get("group", "")) == group and other.has("accessory"):
				accessories.erase(String(other["accessory"]))
	if entry.has("accessory"):
		var accessory := String(entry["accessory"])
		accessories.erase(accessory)
		if not toggling_off:
			accessories.append(accessory)
	look.accessories = PackedStringArray(accessories)
	if entry.has("set"):
		for field in entry["set"]:
			if field == "skirt_color" and entry["set"][field].a > 0.0 and look.skirt_color.a > 0.0:
				continue  # keep a skirt colour the player already chose
			look.set(field, entry["set"][field])
	# The mesh builder hides hats under an afro.
	if look.hair_style == "afro":
		for hat: Dictionary in ITEMS:
			if String(hat.get("group", "")) == "hat" and hat.has("accessory") and not ["headband", "flower_crown"].has(String(hat["accessory"])):
				var trimmed := Array(look.accessories)
				trimmed.erase(String(hat["accessory"]))
				look.accessories = PackedStringArray(trimmed)


## Items (and dyes) in `look` that the player doesn't own yet.
static func unowned_in(look: CharacterAppearance, dyes_used: Array) -> Array:
	var out := []
	for entry: Dictionary in ITEMS:
		var id := String(entry["id"])
		if not is_owned(id) and (entry.has("accessory") or entry.has("set")) and is_worn(look, id):
			out.append(id)
	for dye_id in dyes_used:
		if not is_owned(String(dye_id)) and not out.has(dye_id):
			out.append(dye_id)
	return out


## What it costs to buy `ids`, and whether any can't be bought (play-only).
static func cost_of(ids: Array) -> int:
	var total := 0
	for id in ids:
		total += int(item(String(id)).get("price", 0))
	return total
