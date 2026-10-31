extends Node3D
## Entry point. Builds the world, then spawns the player, camera, villagers
## and UI, and finally restores any saved state.

const VILLAGER_DATA_PATHS: Array[String] = [
	"res://data/villagers/mara.tres",
	"res://data/villagers/elias.tres",
	"res://data/villagers/nia.tres",
	"res://data/villagers/tomas.tres",
	"res://data/villagers/sera.tres",
]
## East of the meeting circle on the bridge path, facing west toward the homes.
const PLAYER_START := Vector3(14.0, 0.0, 0.0)

var navigation: VillageNavigation
var day_night: DayNightCycle
var player: PlayerController
var camera_rig: CameraRig
var hud: Hud


func _ready() -> void:
	SaveService.apply_saved_clock()
	SaveService.apply_saved_game_state()
	SaveService.apply_saved_population()
	var world := Node3D.new()
	world.name = "World"
	add_child(world)
	TerrainGenerator.build(world)
	VillageBuilder.build(world)
	RiverBuilder.build(world)
	NatureSpawner.new().spawn(world)
	ResourceSpawner.spawn(world)
	world.add_child(StructureManager.new())
	world.add_child(WorldObjects.new())

	day_night = DayNightCycle.new()
	add_child(day_night)

	navigation = VillageNavigation.new()
	_spawn_player()
	_spawn_villagers()

	var director := PopulationDirector.new()
	director.navigation = navigation
	director.villagers_root = get_node("Villagers")
	add_child(director)
	add_child(SocialLife.new())
	add_child(PlayerSocial.new())
	add_child(VillageGifts.new())

	add_child(GossipSystem.new())
	add_child(TaskSystem.new())
	add_child(BuildMode.new())

	hud = Hud.new()
	add_child(hud)

	SaveService.apply_loaded_state()


func _spawn_player() -> void:
	player = PlayerController.new()
	player.spawn_point = VillageLayout.ground_point(PLAYER_START.x, PLAYER_START.z) + Vector3(0, 0.3, 0)
	player.position = player.spawn_point
	add_child(player)
	# Start facing the meeting circle.
	player.model.rotation.y = -PI * 0.5

	camera_rig = CameraRig.new()
	camera_rig.target = player
	add_child(camera_rig)


func _spawn_villagers() -> void:
	var villagers := Node3D.new()
	villagers.name = "Villagers"
	add_child(villagers)
	var founders: Array = []
	for path in VILLAGER_DATA_PATHS:
		var data := load(path) as VillagerData
		if data == null:
			push_error("Missing villager data: %s" % path)
			continue
		founders.append(data)
	# The founders keep their hand-written identities; their life records are
	# created once (or come from the save).
	Population.ensure_founders(founders)
	for data: VillagerData in founders:
		var person := Population.get_person(String(data.id))
		if person and not person.is_present():
			continue
		var villager := Villager.new()
		if person:
			# A copy: aging changes their looks, never the authored resource.
			data = data.duplicate()
			data.appearance = person.current_look()
			data.age = person.age()
			villager.visual_stage = AgeLook.visual_stage(person.age(), person.look_age)
		villager.data = data
		villager.navigation = navigation
		villagers.add_child(villager)
