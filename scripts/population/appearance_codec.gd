class_name AppearanceCodec
extends RefCounted
## Converts CharacterAppearance to and from JSON-friendly dictionaries so
## generated people can be saved and rebuilt identically.


static func to_dict(look: CharacterAppearance) -> Dictionary:
	var out := {}
	for property in look.get_property_list():
		if not (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var key := String(property["name"])
		var value: Variant = look.get(key)
		if value is Color:
			var c: Color = value
			out[key] = {"color": [c.r, c.g, c.b, c.a]}
		elif value is PackedStringArray:
			out[key] = Array(value)
		elif value is Dictionary:
			out[key] = (value as Dictionary).duplicate(true)
		else:
			out[key] = value
	return out


static func from_dict(data: Dictionary) -> CharacterAppearance:
	var look := CharacterAppearance.new()
	var known := {}
	for property in look.get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			known[String(property["name"])] = true
	for key in data:
		if not known.has(String(key)):
			continue
		var value: Variant = data[key]
		var current: Variant = look.get(key)
		if value is Dictionary and (value as Dictionary).has("color"):
			var c: Array = value["color"]
			look.set(key, Color(float(c[0]), float(c[1]), float(c[2]), float(c[3])))
		elif current is PackedStringArray:
			look.set(key, PackedStringArray(value as Array))
		elif current is float:
			look.set(key, float(value))
		elif current is int:
			look.set(key, int(value))
		else:
			look.set(key, value)
	return look
