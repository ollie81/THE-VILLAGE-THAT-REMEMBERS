extends Node3D
## Developer tool: every animal's head close up (side, front, top) with its
## eyes, for tuning AnimalSpecies "eyes". --bones marks the head bones instead;
## ONLY=dog,cat limits it to some species.

var out := ""
var list := {}
func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.6, 0.75, 0.9)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = 0.8
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.7, 0.4, 0)
	add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 40
	add_child(cam)
	list = AnimalSpecies.SPECIES.duplicate()
	list[&"wolf"] = {"model": "Wolf", "scale": 0.2, "yaw": -PI * 0.5, "head_bone": "Bone.003", "eyes": Monster.KINDS[&"wolf"]["eyes"]}
	for species in list:
		var info: Dictionary = list[species]
		var holder := Node3D.new()
		add_child(holder)
		var model: Node3D = (load(AnimalSpecies.DIR + String(info["model"]) + ".fbx") as PackedScene).instantiate()
		model.scale = Vector3.ONE * float(info["scale"])
		model.rotation.y = float(info["yaw"])
		holder.add_child(model)
		await get_tree().process_frame
		var sk: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
		var bone := sk.find_bone(String(info.get("head_bone", "Head")))
		var to_holder := holder.global_transform.affine_inverse() * sk.global_transform
		var hp := to_holder * sk.get_bone_global_rest(bone).origin
		var marks: Array = []
		if OS.get_cmdline_user_args().has("--bones"):
			marks.append([hp, Color.RED])
			for c in sk.get_bone_children(bone):
				marks.append([to_holder * sk.get_bone_global_rest(c).origin, Color.BLUE])
		else:
			var pts := AnimalSpecies.eye_points(info, sk, to_holder)
			if not pts.is_empty():
				marks.append([pts[0], Color.BLACK, pts[2]])
				marks.append([pts[1], Color.BLACK, pts[2]])
		if not OS.get_cmdline_user_args().has("--bones"):
			for mk in marks:
				var eye := AnimalSpecies.make_eye(float(mk[2]), 1.0 if mk == marks[0] else -1.0)
				eye.position = mk[0]
				holder.add_child(eye)
			marks = []
		for mk in marks:
			var s := MeshInstance3D.new()
			var sm := SphereMesh.new()
			var r: float = float(mk[2]) if mk.size() > 2 else 0.03
			sm.radius = r
			sm.height = r * 2
			s.mesh = sm
			var mat := StandardMaterial3D.new()
			mat.albedo_color = mk[1]
			mat.no_depth_test = OS.get_cmdline_user_args().has("--bones")
			s.material_override = mat
			s.position = mk[0]
			holder.add_child(s)
		var size := maxf(0.5, hp.y * 0.6)
		var only := OS.get_environment("ONLY")
		if only != "" and not String(species) in only.split(","):
			holder.queue_free()
			continue
		for view in [["side", Vector3(1, 0.05, 0.15)], ["front", Vector3(0.35, 0.1, 1)], ["top", Vector3(0.05, 1, 0.3)]]:
			cam.position = hp + (view[1] as Vector3).normalized() * size * 1.6
			cam.look_at(hp)
			for k in 3:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [out, species, view[0]])
		holder.queue_free()
	get_tree().quit()
