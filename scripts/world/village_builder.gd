class_name VillageBuilder
extends RefCounted
## Places every structure described by VillageLayout.


static func build(parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "Village"
	for building in VillageLayout.get_buildings():
		root.add_child(BuildingFactory.create(building))
	# A lantern by the storehouse path and one on the way to the farm.
	root.add_child(BuildingFactory.create_lantern(VillageLayout.ground_point(-10.0, 3.2)))
	root.add_child(BuildingFactory.create_lantern(VillageLayout.ground_point(8.6, 8.9)))
	parent.add_child(root)
