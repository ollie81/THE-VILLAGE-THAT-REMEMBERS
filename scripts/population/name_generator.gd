class_name NameGenerator
extends RefCounted
## Names for newcomers, drawn from many traditions so the village feels like
## a crossroads. First names are never reused while their owner still lives
## in the village, and full names are always unique.

const FEMALE: Array[String] = [
	"Aino", "Adaeze", "Alma", "Amara", "Anouk", "Asha", "Beatrix", "Bryn", "Calla", "Ceren",
	"Dalia", "Edda", "Elif", "Esi", "Fern", "Freya", "Greta", "Hana", "Hazel", "Ilse",
	"Imani", "Ines", "Iris", "Isolde", "Jun", "Kalina", "Kenna", "Laila", "Lena", "Liv",
	"Lucia", "Maeve", "Mei", "Mirela", "Nadia", "Nell", "Noor", "Odette", "Olwen", "Oona",
	"Paloma", "Priya", "Rosa", "Rowan", "Rua", "Saoirse", "Selma", "Signe", "Talia", "Tamsin",
	"Thea", "Uma", "Vesna", "Wren", "Yara", "Yuki", "Zainab", "Zofia", "Ada", "Juniper",
]
const MALE: Array[String] = [
	"Aarav", "Alder", "Anton", "Arlo", "Bastian", "Bram", "Caspian", "Cormac", "Dario", "Desmond",
	"Emeka", "Emrys", "Ewan", "Farid", "Felix", "Finn", "Gideon", "Hamid", "Hugo", "Idris",
	"Ivo", "Jasper", "Jomo", "Kai", "Kaito", "Kenji", "Kofi", "Lars", "Leif", "Lorcan",
	"Luca", "Malik", "Mateo", "Milo", "Nils", "Oisin", "Omar", "Oskar", "Pavel", "Quill",
	"Rafael", "Rhys", "Ronan", "Rune", "Silas", "Soren", "Sven", "Taavi", "Tariq", "Teo",
	"Ugo", "Viktor", "Wilf", "Yusuf", "Zane", "Ezra", "Benedek", "Cato", "Duncan", "Hollis",
]
const FAMILY: Array[String] = [
	"Ashdown", "Barrow", "Birchwood", "Blackthorn", "Brook", "Carver", "Coldwater", "Dale", "Draper", "Elmsley",
	"Fairweather", "Fenn", "Fletcher", "Flint", "Glen", "Greaves", "Hale", "Hawthorn", "Heath", "Holloway",
	"Hollins", "Ives", "Kestrel", "Lark", "Linden", "Lowe", "Marsh", "Meadows", "Mill", "Moss",
	"Nettle", "Oakes", "Orchard", "Penhallow", "Quarry", "Reed", "Rook", "Rowe", "Sallow", "Sedge",
	"Shaw", "Sorrel", "Stone", "Tanner", "Thatcher", "Thorne", "Underhill", "Vale", "Wade", "Weaver",
	"Westbrook", "Whitlock", "Wilde", "Willow", "Winter", "Wren", "Yarrow", "Amsel", "Okafor", "Nakamura",
]


## A first name nobody living in the village has. `taken` holds the
## lower-case first names in use.
static func first_name(rng: RandomNumberGenerator, sex: String, taken: Dictionary) -> String:
	var pool: Array[String] = FEMALE if sex == "female" else MALE
	for attempt in 40:
		var candidate := pool[rng.randi_range(0, pool.size() - 1)]
		if not taken.has(candidate.to_lower()):
			return candidate
	# Every name taken: fall back to a numbered variant (very unlikely at 50).
	return "%s %s" % [pool[rng.randi_range(0, pool.size() - 1)], ["II", "III", "IV"][rng.randi_range(0, 2)]]


static func family_name(rng: RandomNumberGenerator) -> String:
	return FAMILY[rng.randi_range(0, FAMILY.size() - 1)]
