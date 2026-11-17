class_name FurniturePiece
extends UsableObject
## One piece of furniture in the world: its look, something solid to bump
## into, and what tapping it does: sleep in a bed, sit on a seat, open a chest
## or wardrobe (real storage), read from a bookshelf, switch a lamp on and
## off. While you're arranging, tapping it picks it up instead.

var record: Dictionary
var type: StringName
var info: Dictionary
var _light: OmniLight3D
var _shade: MeshInstance3D
var interactable: Interactable


func setup(furniture_record: Dictionary) -> FurniturePiece:
	record = furniture_record
	type = StringName(String(record["type"]))
	info = FurnitureCatalog.info(type)
	name = String(type).to_pascal_case()
	return self


func _ready() -> void:
	add_to_group("furniture")
	var built := FurnitureCatalog.build(type, colours())
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	mesh.mesh = (built[0] as MeshBuilder).build(Materials.vertex_color())
	add_child(mesh)
	if not (built[1] as Array).is_empty():
		var body := StaticBody3D.new()
		body.name = "Body"
		body.collision_layer = 1
		add_child(body)
		for box in built[1]:
			var shape := CollisionShape3D.new()
			var b := BoxShape3D.new()
			b.size = box[1]
			shape.shape = b
			shape.position = box[0]
			body.add_child(shape)
	prompt = func(): return _prompt()
	verb = func(): return _verb()
	use = func(actor): interact(actor)
	interactable = Interactable.new()
	var size: Vector2 = info.get("size", Vector2.ONE)
	interactable.radius = clampf(maxf(size.x, size.y) * 0.5 + 0.6, 0.9, 1.8)
	interactable.handler = self
	interactable.interacted.connect(func(actor): use.call(actor))
	add_child(interactable)
	if type == &"lamp":
		_light = OmniLight3D.new()
		_light.position = Vector3(0, 1.45, 0)
		_light.light_color = Color(1.0, 0.82, 0.55)
		_light.light_energy = 1.2
		_light.omni_range = 4.5
		add_child(_light)
		_update_lamp()


## Colours that make a piece its own (the rug's and bed's cloth, from its id).
func colours() -> Dictionary:
	var cloths := [Color(0.62, 0.3, 0.26), Color(0.32, 0.45, 0.6), Color(0.45, 0.55, 0.3), Color(0.6, 0.45, 0.25), Color(0.55, 0.38, 0.55)]
	return {"cloth": cloths[absi(int(record.get("id", 0))) % cloths.size()]}


func id() -> int:
	return int(record["id"])


func is_own() -> bool:
	return Furnishings.instance == null or Furnishings.instance.is_players_place(String(record.get("place", "")))


func _arranging() -> bool:
	return FurnishMode.instance != null and FurnishMode.instance.arranging and is_own()


func _verb() -> String:
	if _arranging():
		return "Pick up" if bool(info.get("carry", false)) else "Move"
	match String(info.get("use", "")):
		"sleep":
			return "Sleep"
		"sit":
			return "Sit"
		"storage":
			return "Open"
		"read":
			return "Read"
		"light":
			return "Turn off" if lamp_on() else "Light"
	return "Look"


func _prompt() -> String:
	var title := String(info.get("name", "Furniture"))
	if _arranging():
		return "%s %s  (then place it where you like)" % ["Pick up the" if bool(info.get("carry", false)) else "Move the", title.to_lower()]
	match String(info.get("use", "")):
		"sleep":
			return ("Sleep until morning" if PlayerController.is_night() else "Your bed  (sleep at night, or have a nap)") if is_own() else "%s  (not yours to sleep in)" % title
		"sit":
			return "Sit on the %s" % title.to_lower()
		"storage":
			return "%s  (%d of %d stored)" % [title, Furnishings.stored_total(record), int(info.get("holds", 0))]
		"read":
			return "Read a book from the shelf"
		"light":
			return "Turn the lamp off" if lamp_on() else "Light the lamp"
	return title


func interact(actor) -> void:
	if _arranging():
		FurnishMode.instance.pick_up(self)
		return
	match String(info.get("use", "")):
		"sleep":
			if not is_own():
				GameManager.notify("That's not your bed.")
			elif Interiors.instance and Interiors.instance.is_inside():
				Interiors.instance._sleep(actor, self)
			else:
				GameManager.notify("A bed is for indoors. Take it into your house.")
		"sit":
			if actor and actor.has_method("sit"):
				var s: Array = FurnitureCatalog.seat(type)
				actor.sit({"position": global_transform * (s[0] as Vector3), "yaw": global_rotation.y, "height": float(s[1])})
		"storage":
			if not is_own():
				GameManager.notify("That's someone else's.")
			elif StoragePanel.instance:
				StoragePanel.instance.open(self)
		"read":
			if Interiors.instance:
				Interiors.instance._read_book(actor)
		"light":
			record["on"] = not lamp_on()
			_update_lamp()
			Sounds.play("pickup", global_position, -10.0)
		_:
			GameManager.notify("A lovely %s." % String(info.get("name", "piece")).to_lower())


func lamp_on() -> bool:
	return bool(record.get("on", true))


func _update_lamp() -> void:
	if _light:
		_light.visible = lamp_on()
