class_name Treasure
extends Node3D
## Three old chests hidden in the woods around the village, for explorers.
## Each opens once (saved) and holds something useful.

const REWARDS := [
	{"items": {&"stone": 8, &"herbs": 3}, "text": "Under the moss: a stash of cut stone and dried herbs."},
	{"items": {&"wood": 10, &"food": 4}, "text": "Someone's forgotten supplies: seasoned planks and preserved food."},
	{"items": {&"wood": 6, &"stone": 6, &"food": 6}, "text": "An old traveller's chest, still full. What luck!"},
]

static var instance: Treasure
var spots: Array[Vector3] = []


func _ready() -> void:
	name = "Treasure"
	instance = self
	spots = find_spots()
	for i in spots.size():
		_add_chest(i, spots[i])


func _exit_tree() -> void:
	if instance == self:
		instance = null


## Quiet spots in the woods, well away from the village, one per direction.
static func find_spots() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for angle in [2.3, 3.6, 5.2]:
		for r in [48.0, 44.0, 40.0, 52.0]:
			var p := Vector3(cos(angle) * r, 0, sin(angle) * r)
			if VillageLayout.blocking_reason(p.x, p.z, 1.0, 0.5) == "":
				out.append(VillageLayout.ground_point(p.x, p.z))
				break
	return out


static func found() -> int:
	var n := 0
	for i in REWARDS.size():
		if GameState.get_flag(StringName("treasure_%d" % i)):
			n += 1
	return n


func _add_chest(index: int, at: Vector3) -> void:
	var holder := UsableObject.new()
	holder.name = "Chest_%d" % index
	holder.position = at
	var flag := StringName("treasure_%d" % index)
	holder.prompt = func(): return "An empty old chest" if GameState.get_flag(flag) else "An old chest, half hidden in the moss"
	holder.verb = func(): return "Look" if GameState.get_flag(flag) else "Open"
	holder.use = func(_actor): _open(index, holder)
	add_child(holder)
	var b := MeshBuilder.new(index + 3)
	b.add_box_at(Vector3(0, 0.25, 0), Vector3(0.9, 0.5, 0.6), Color(0.45, 0.3, 0.18))
	b.add_box_at(Vector3(0, 0.52, 0), Vector3(0.94, 0.08, 0.64), Color(0.38, 0.25, 0.15))
	for sx in [-0.3, 0.3]:
		b.add_box_at(Vector3(sx, 0.3, 0), Vector3(0.06, 0.56, 0.66), Color(0.55, 0.5, 0.3))
	b.add_box_at(Vector3(0, 0.38, 0.31), Vector3(0.1, 0.12, 0.03), Color(0.8, 0.7, 0.3))
	b.add_blob_at(Vector3(-0.2, 0.56, -0.1), Vector3(0.3, 0.06, 0.25), Color(0.35, 0.55, 0.28), 6, 3, 0.3)
	var mesh := MeshInstance3D.new()
	mesh.mesh = b.build(Materials.vertex_color())
	holder.add_child(mesh)
	var interactable := Interactable.new()
	interactable.radius = 1.2
	interactable.handler = holder
	interactable.interacted.connect(func(actor): holder.use.call(actor))
	holder.add_child(interactable)
	NatureSpawner.clear_area(at, 1.2)


func _open(index: int, _holder) -> void:
	var flag := StringName("treasure_%d" % index)
	if GameState.get_flag(flag):
		GameManager.notify("Empty now. There are %d old chests in the woods; you've found %d." % [REWARDS.size(), found()])
		return
	GameState.set_flag(flag)
	var reward: Dictionary = REWARDS[index]
	for resource in reward["items"]:
		GameState.add(resource, int(reward["items"][resource]))
	Sounds.play("built", null, -2.0)
	GameManager.notify("%s  (+%s)  [%d / %d chests found]" % [reward["text"], GameState.cost_text(reward["items"]), found(), REWARDS.size()])
