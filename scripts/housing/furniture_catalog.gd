class_name FurnitureCatalog
extends RefCounted
## Every piece of furniture and decoration: its size on the floor, what it
## costs, what you can do with it, whether you can carry it in your hands and
## whether it can stand outdoors, and how it looks (built in code in the
## village's own style, so no extra model files).
##
## use: "sleep" (beds), "sit" (seats), "storage" (keeps resources), "read"
## (books), "light" (lamps switch on and off), "" (to look at).

const ITEMS := {
	&"bed": {"name": "Bed", "size": Vector2(1.6, 2.3), "cost": {&"wood": 8}, "use": "sleep", "carry": false, "outdoor": false},
	&"bed_double": {"name": "Double bed", "size": Vector2(2.2, 2.4), "cost": {&"wood": 12, &"herbs": 2}, "use": "sleep", "carry": false, "outdoor": false},
	&"chair": {"name": "Chair", "size": Vector2(0.5, 0.5), "cost": {&"wood": 2}, "use": "sit", "carry": true, "outdoor": true},
	&"stool": {"name": "Stool", "size": Vector2(0.45, 0.45), "cost": {&"wood": 1}, "use": "sit", "carry": true, "outdoor": true},
	&"settle": {"name": "Cushioned settle", "size": Vector2(1.9, 0.8), "cost": {&"wood": 8, &"herbs": 2}, "use": "sit", "carry": false, "outdoor": false},
	&"bench_seat": {"name": "Wooden bench", "size": Vector2(1.8, 0.5), "cost": {&"wood": 4}, "use": "sit", "carry": false, "outdoor": true},
	&"table": {"name": "Long table", "size": Vector2(1.5, 0.95), "cost": {&"wood": 5}, "use": "", "carry": false, "outdoor": true},
	&"table_round": {"name": "Round table", "size": Vector2(1.2, 1.2), "cost": {&"wood": 4}, "use": "", "carry": false, "outdoor": true},
	&"chest": {"name": "Storage chest", "size": Vector2(1.1, 0.55), "cost": {&"wood": 5, &"stone": 1}, "use": "storage", "carry": false, "outdoor": false, "holds": 40},
	&"wardrobe": {"name": "Wardrobe", "size": Vector2(1.2, 0.6), "cost": {&"wood": 10}, "use": "storage", "carry": false, "outdoor": false, "holds": 60},
	&"bookshelf": {"name": "Bookshelf", "size": Vector2(1.2, 0.4), "cost": {&"wood": 8}, "use": "read", "carry": false, "outdoor": false},
	&"rug": {"name": "Woven rug", "size": Vector2(2.2, 1.6), "cost": {&"herbs": 3}, "use": "", "carry": false, "outdoor": false, "flat": true},
	&"lamp": {"name": "Standing lamp", "size": Vector2(0.4, 0.4), "cost": {&"wood": 2, &"stone": 1}, "use": "light", "carry": true, "outdoor": true},
	&"plant": {"name": "Potted plant", "size": Vector2(0.5, 0.5), "cost": {&"herbs": 2, &"stone": 1}, "use": "", "carry": true, "outdoor": true},
	&"crate": {"name": "Crate", "size": Vector2(0.6, 0.6), "cost": {&"wood": 2}, "use": "storage", "carry": true, "outdoor": true, "holds": 15},
	&"barrel": {"name": "Barrel", "size": Vector2(0.65, 0.65), "cost": {&"wood": 3}, "use": "", "carry": true, "outdoor": true},
}
## The order they're listed in.
const ORDER: Array[StringName] = [&"bed", &"bed_double", &"chair", &"stool", &"settle", &"bench_seat", &"table", &"table_round",
	&"chest", &"wardrobe", &"bookshelf", &"rug", &"lamp", &"plant", &"crate", &"barrel"]

## What a house starts with (and what an older house's baked-in furniture
## becomes): [type, x, z, yaw] in the small house's room, where everything fits.
const STARTER := [[&"bed", 2.6, -1.75, 0.0], [&"chest", 2.6, 0.05, PI], [&"table", -1.4, 0.2, 0.0],
	[&"chair", -1.4, -0.65, 0.0], [&"chair", -1.4, 1.05, PI], [&"rug", 1.0, 0.6, 0.0], [&"lamp", -3.6, 2.4, 0.0]]

const WOOD := Color(0.55, 0.38, 0.22)
const WOOD_DARK := Color(0.36, 0.24, 0.14)
const WOOD_LIGHT := Color(0.7, 0.53, 0.33)


static func info(type: StringName) -> Dictionary:
	return ITEMS.get(type, {})


## Footprint on the floor after turning by `yaw` (quarter turns swap sides).
static func footprint(type: StringName, yaw: float) -> Vector2:
	var size: Vector2 = info(type).get("size", Vector2.ONE)
	var quarter := posmod(int(round(yaw / (PI * 0.5))), 2) == 1
	return Vector2(size.y, size.x) if quarter else size


## Where someone sits on a seat (local), facing +Z, and the seat's height.
## Where the hips go on a seat (local) and the seat's height: on seats with
## a backrest, close enough in front of it for the back to rest against it.
static func seat(type: StringName) -> Array:
	match type:
		&"settle":
			return [Vector3(0, 0, -0.1), 0.48]
		&"bench_seat":
			return [Vector3(0, 0, -0.08), 0.48]
		&"stool":
			return [Vector3.ZERO, 0.46]
	return [Vector3(0, 0, -0.1), 0.47]


## The look, as a MeshBuilder (local, facing +Z, standing on y = 0), plus
## collider boxes [centre, size].
static func build(type: StringName, colours: Dictionary = {}) -> Array:
	var m := MeshBuilder.new(hash(String(type)))
	var boxes: Array = []
	var wood: Color = colours.get("wood", WOOD)
	var cloth: Color = colours.get("cloth", Color(0.62, 0.3, 0.26))
	match type:
		&"bed", &"bed_double":
			var w := 1.6 if type == &"bed" else 2.2
			var l := 2.3 if type == &"bed" else 2.4
			m.add_box_at(Vector3(0, 0.28, 0), Vector3(w, 0.32, l), wood)
			m.add_box_at(Vector3(0, 0.5, 0.05), Vector3(w - 0.14, 0.16, l - 0.2), Color(0.93, 0.91, 0.86))
			m.add_box_at(Vector3(0, 0.6, 0.35), Vector3(w - 0.1, 0.07, l * 0.6), cloth)
			m.add_box_at(Vector3(0, 0.62, l * 0.5 - 0.1), Vector3(w - 0.08, 0.08, 0.12), cloth.lightened(0.2))
			var pillows := 1 if type == &"bed" else 2
			for p in pillows:
				var px := 0.0 if pillows == 1 else (p - 0.5) * 0.95
				m.add_box_at(Vector3(px, 0.64, -l * 0.5 + 0.38), Vector3(0.85 if pillows == 1 else 0.8, 0.15, 0.42), Color(0.98, 0.97, 0.94))
			m.add_box_at(Vector3(0, 0.75, -l * 0.5 + 0.06), Vector3(w, 1.05, 0.12), WOOD_DARK)
			m.add_box_at(Vector3(0, 0.4, l * 0.5 - 0.04), Vector3(w, 0.5, 0.08), WOOD_DARK)
			boxes.append([Vector3(0, 0.4, 0), Vector3(w, 0.8, l)])
		&"chair":
			m.add_box_at(Vector3(0, 0.45, 0), Vector3(0.48, 0.06, 0.46), wood)
			m.add_box_at(Vector3(0, 0.82, -0.21), Vector3(0.48, 0.68, 0.05), WOOD_DARK)
			for lx: float in [-0.2, 0.2]:
				for lz: float in [-0.19, 0.19]:
					m.add_box_at(Vector3(lx, 0.22, lz), Vector3(0.05, 0.44, 0.05), WOOD_DARK)
			boxes.append([Vector3(0, 0.25, 0), Vector3(0.45, 0.5, 0.45)])
		&"stool":
			m.add_cylinder_at(Vector3(0, 0.42, 0), 0.22, 0.22, 0.06, 10, wood)
			for i in 3:
				var a := TAU * i / 3.0
				m.add_box_at(Vector3(cos(a) * 0.14, 0.21, sin(a) * 0.14), Vector3(0.05, 0.42, 0.05), WOOD_DARK)
			boxes.append([Vector3(0, 0.22, 0), Vector3(0.4, 0.44, 0.4)])
		&"settle":
			m.add_box_at(Vector3(0, 0.25, 0), Vector3(1.9, 0.4, 0.75), wood)
			m.add_box_at(Vector3(0, 0.5, 0.05), Vector3(1.75, 0.12, 0.62), cloth)
			m.add_box_at(Vector3(0, 0.85, -0.33), Vector3(1.9, 0.8, 0.1), WOOD_DARK)
			m.add_box_at(Vector3(0, 0.8, -0.24), Vector3(1.7, 0.5, 0.1), cloth.lightened(0.12))
			for sx: float in [-1.0, 1.0]:
				m.add_box_at(Vector3(sx * 0.92, 0.62, 0), Vector3(0.1, 0.35, 0.75), WOOD_DARK)
			boxes.append([Vector3(0, 0.4, 0), Vector3(1.9, 0.8, 0.75)])
		&"bench_seat":
			m.add_box_at(Vector3(0, 0.46, 0), Vector3(1.8, 0.08, 0.45), WOOD_LIGHT)
			m.add_box_at(Vector3(0, 0.85, -0.2), Vector3(1.8, 0.28, 0.06), WOOD_LIGHT)
			for sx: float in [-0.75, 0.75]:
				m.add_box_at(Vector3(sx, 0.22, 0), Vector3(0.08, 0.44, 0.42), wood)
				m.add_box_at(Vector3(sx, 0.65, -0.2), Vector3(0.06, 0.4, 0.06), wood)
			boxes.append([Vector3(0, 0.3, 0), Vector3(1.8, 0.6, 0.45)])
		&"table":
			m.add_box_at(Vector3(0, 0.74, 0), Vector3(1.5, 0.08, 0.95), wood.lightened(0.05))
			for lx: float in [-0.65, 0.65]:
				for lz: float in [-0.38, 0.38]:
					m.add_box_at(Vector3(lx, 0.36, lz), Vector3(0.08, 0.72, 0.08), WOOD_DARK)
			m.add_cylinder_at(Vector3(0.25, 0.78, 0.1), 0.08, 0.07, 0.16, 7, Color(0.75, 0.62, 0.45))
			m.add_cylinder_at(Vector3(-0.3, 0.78, -0.12), 0.2, 0.2, 0.03, 10, Color(0.92, 0.9, 0.85))
			boxes.append([Vector3(0, 0.4, 0), Vector3(1.5, 0.8, 0.95)])
		&"table_round":
			m.add_cylinder_at(Vector3(0, 0.72, 0), 0.6, 0.6, 0.07, 14, wood.lightened(0.05))
			m.add_cylinder_at(Vector3(0, 0, 0), 0.12, 0.08, 0.72, 8, WOOD_DARK)
			m.add_cylinder_at(Vector3(0, 0, 0), 0.35, 0.3, 0.05, 10, WOOD_DARK)
			m.add_cylinder_at(Vector3(0, 0.79, 0), 0.08, 0.06, 0.2, 7, Color(0.5, 0.62, 0.75))
			m.add_blob_at(Vector3(0, 1.0, 0), Vector3(0.1, 0.08, 0.1), Color(0.9, 0.5, 0.55), 6, 3, 0.1)
			boxes.append([Vector3(0, 0.4, 0), Vector3(1.0, 0.8, 1.0)])
		&"chest", &"crate":
			if type == &"chest":
				m.add_box_at(Vector3(0, 0.27, 0), Vector3(1.1, 0.54, 0.55), WOOD_DARK)
				m.add_box_at(Vector3(0, 0.56, 0), Vector3(1.14, 0.06, 0.6), wood)
				m.add_box_at(Vector3(0, 0.42, 0.29), Vector3(0.12, 0.14, 0.04), Color(0.82, 0.7, 0.35))
				for sx: float in [-0.4, 0.4]:
					m.add_box_at(Vector3(sx, 0.3, 0.285), Vector3(0.06, 0.56, 0.02), Color(0.3, 0.3, 0.32))
				boxes.append([Vector3(0, 0.3, 0), Vector3(1.1, 0.6, 0.55)])
			else:
				m.add_box_at(Vector3(0, 0.3, 0), Vector3(0.6, 0.6, 0.6), WOOD_LIGHT)
				for y: float in [0.12, 0.48]:
					m.add_box_at(Vector3(0, y, 0), Vector3(0.62, 0.08, 0.62), wood)
				boxes.append([Vector3(0, 0.3, 0), Vector3(0.6, 0.6, 0.6)])
		&"wardrobe":
			m.add_box_at(Vector3(0, 1.0, 0), Vector3(1.2, 2.0, 0.6), wood)
			m.add_box_at(Vector3(0, 2.04, 0), Vector3(1.3, 0.08, 0.66), WOOD_DARK)
			m.add_box_at(Vector3(0, 1.05, 0.305), Vector3(0.03, 1.8, 0.02), WOOD_DARK)
			for sx: float in [-0.08, 0.08]:
				m.add_box_at(Vector3(sx, 1.1, 0.32), Vector3(0.04, 0.16, 0.04), Color(0.82, 0.7, 0.35))
			boxes.append([Vector3(0, 1.0, 0), Vector3(1.2, 2.0, 0.6)])
		&"bookshelf":
			m.add_box_at(Vector3(0, 1.0, -0.15), Vector3(1.2, 2.0, 0.08), WOOD_DARK)
			for sx: float in [-1.0, 1.0]:
				m.add_box_at(Vector3(sx * 0.57, 1.0, 0), Vector3(0.06, 2.0, 0.4), wood)
			for level in 4:
				var y := 0.1 + level * 0.5
				m.add_box_at(Vector3(0, y, 0), Vector3(1.1, 0.05, 0.38), wood)
				for b in 7:
					var colour: Color = [Color(0.6, 0.2, 0.18), Color(0.25, 0.4, 0.55), Color(0.3, 0.5, 0.3), Color(0.75, 0.62, 0.3)][(b + level) % 4]
					m.add_box_at(Vector3(-0.45 + b * 0.14, y + 0.17, 0.02), Vector3(0.1, 0.3 - float((b * 3 + level) % 3) * 0.04, 0.26), colour)
			boxes.append([Vector3(0, 1.0, 0), Vector3(1.2, 2.0, 0.4)])
		&"rug":
			m.add_box_at(Vector3(0, 0.012, 0), Vector3(2.2, 0.02, 1.6), cloth.darkened(0.1))
			m.add_box_at(Vector3(0, 0.02, 0), Vector3(1.8, 0.02, 1.2), cloth.lightened(0.1))
			m.add_box_at(Vector3(0, 0.026, 0), Vector3(1.0, 0.02, 0.5), Color(0.9, 0.78, 0.45))
		&"lamp":
			m.add_cylinder_at(Vector3(0, 0, 0), 0.18, 0.18, 0.05, 10, WOOD_DARK)
			m.add_box_at(Vector3(0, 0.75, 0), Vector3(0.05, 1.45, 0.05), WOOD_DARK)
			m.add_cylinder_at(Vector3(0, 1.4, 0), 0.24, 0.13, 0.32, 10, Color(0.98, 0.9, 0.68))
			boxes.append([Vector3(0, 0.8, 0), Vector3(0.3, 1.6, 0.3)])
		&"plant":
			m.add_cylinder_at(Vector3(0, 0, 0), 0.2, 0.24, 0.38, 10, Color(0.7, 0.36, 0.26))
			m.add_blob_at(Vector3(0, 0.6, 0), Vector3(0.3, 0.32, 0.3), Color(0.3, 0.55, 0.25), 8, 5, 0.25)
			m.add_blob_at(Vector3(0.12, 0.82, 0.05), Vector3(0.18, 0.2, 0.18), Color(0.38, 0.62, 0.3), 7, 4, 0.25)
			boxes.append([Vector3(0, 0.4, 0), Vector3(0.45, 0.8, 0.45)])
		&"barrel":
			m.add_cylinder_at(Vector3.ZERO, 0.3, 0.32, 0.85, 10, wood.darkened(0.12))
			for y: float in [0.15, 0.7]:
				m.add_cylinder_at(Vector3(0, y, 0), 0.33, 0.33, 0.05, 10, Color(0.4, 0.4, 0.42))
			boxes.append([Vector3(0, 0.42, 0), Vector3(0.62, 0.85, 0.62)])
	return [m, boxes]


## Where lying down in a bed puts you (local) and which way your head goes.
static func mattress(type: StringName) -> Vector3:
	return Vector3(0, 0.52, 0.25 if type == &"bed" else 0.2)
