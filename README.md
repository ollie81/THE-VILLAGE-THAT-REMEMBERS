# The Village That Remembers

*Your actions never disappear.*

A 3D civilisation and life simulation for Android, built with Godot 4 and GDScript.
You arrive in a small village of five people who each have their own personality, daily
routine and memory of you.

**Current state: Milestone 1, the first playable village.** See [Status](#status) for what is
done, and what has not been checked in the engine yet.

---

## Milestone 1 contents

| Area | What exists |
| --- | --- |
| World | Procedural low-poly terrain (flat village, hills at the edges), river valley with flowing water shader, arched wooden bridge, forest across the river, meadows, rocks, reeds, mushrooms, wind-swept grass and flowers |
| Buildings | Five homes (each with its owner's colours and personal props), meeting circle with fire pit, log benches and story stone, fenced farm with wheat/cabbage/carrot rows and a scarecrow, herb garden with raised beds and trellis, open workshop with workbench and anvil, storehouse with crates and barrels, Mara's half-built sixth house, the old "memory oak", lantern posts |
| Player | Walk, run, jump, smooth turning, gravity, collision with buildings, trees, villagers, river banks and world edge. Procedural walk/run/jump/idle/talk animation |
| Cameras | Third-person orbit camera with wall avoidance, and a high "Village View" management camera (pan, zoom, rotate, tap a villager for their info card). Smooth blend between them |
| Villagers | Mara, Elias, Nia, Tomas and Sera, each with a distinct look, age, role, traits, biography, walking speed and daily schedule. They walk the village paths, work, gather, trade, chat at the fire, go home at night and come out in the morning |
| Day / night | Moving sun and moon, keyframed sky colours, custom sky shader with stars and moon, ambient and fog colour changes, glowing windows, lanterns and fire light at night. Speed up time with **T** or the *Time ×* button |
| Interaction | Walk up to a villager and press **E** (or tap *Talk*). They stop, face you and introduce themselves. On later visits they remember you ("It's been 3 days since we last talked") |
| Memory | Each villager stores conversations in a memory log with a familiarity score. It is saved to disk, so the village remembers you between sessions |
| Mobile | Mobile renderer, multi-touch joystick, look and pinch controls, Low/Medium/High graphics presets, merged meshes and chunked MultiMeshes, distance-culled detail, autosave when the app is backgrounded |

### Controls

| Action | Keyboard / mouse | Touch | Gamepad |
| --- | --- | --- | --- |
| Move | WASD / arrows | Left-side joystick | Left stick |
| Run | Shift | Push joystick to the rim | LB |
| Jump | Space | *Jump* button | A |
| Look / orbit | Hold right mouse button and drag | Drag right side of screen | Right stick |
| Zoom | Mouse wheel | Pinch | none |
| Talk | E | *Talk* button | X |
| Switch camera | Tab or C | *Village View* button | Y |
| Pan (Village View) | WASD, or drag with the left mouse button | One-finger drag | Left stick |
| Rotate (Village View) | Q / R, or drag with the right mouse button | none | Right stick |
| Select villager (Village View) | Click | Tap | none |
| Time speed | T | *Time ×* button | none |
| Menu / settings | Esc | *Menu* button | Start |

---

## Opening and running

1. Install **Godot 4.3 or newer** (standard build, not .NET): <https://godotengine.org/download>.
2. In the Project Manager choose **Import**, select this folder's `project.godot`, then **Import & Edit**.
   On first import Godot builds its `.godot/` cache. That folder is git-ignored.
3. Press **F5** (Run Project). The main scene is `res://scenes/main.tscn`.

### Automated smoke test

```bash
godot --headless --path . --import            # once, on a fresh clone (builds the .godot cache)
godot --headless --path . res://tests/smoke_test.tscn
```

The test loads the real main scene and checks that:

- the terrain, all buildings, the river, the bridge and the nature batches exist
- exactly five villagers exist, with the right ages, spread across the village
- the player stands on the ground, walks, runs faster than they walk, jumps and lands
- the camera switches to Village View and back, and the player is frozen while in Village View
- noon is bright, midnight is dark, windows glow at night, and villagers go home at night
- villagers walk around during the morning
- talking works: the villager stops, the greeting includes their name, they remember the conversation, the second greeting is different, and memory survives a JSON round trip

It exits with code `0` if every check passes and `1` otherwise. It never touches your save file.

---

## Building an Android APK

The Android export needs the Godot editor and the Android toolchain. It cannot be done from this
repository alone.

1. **One-time setup**
   - Install the Android SDK (Android Studio is the easiest way) and **OpenJDK 17**.
   - In Godot: *Editor → Editor Settings → Export → Android*, set *Java SDK Path* and *Android SDK Path*.
   - *Editor → Manage Export Templates → Download and Install* (templates matching your Godot version).
2. **Create the preset**: *Project → Export → Add… → Android*.
   - *Architectures*: enable `arm64-v8a` (add `armeabi-v7a` for very old phones).
   - *Package → Unique Name*: e.g. `com.yourname.villagethatremembers`.
   - *Screen → Orientation* is already set to *sensor landscape* in Project Settings.
   - Debug builds are signed with Godot's debug keystore automatically. For a release build, create a
     keystore (`keytool -genkey -v -keystore release.keystore -alias village -keyalg RSA -validity 10000`)
     and enter it under *Keystore → Release*.
3. **Export**: click *Export Project*, untick *Export With Debug* for release, and save
   `TheVillageThatRemembers.apk`.
   Or connect a phone with USB debugging enabled and press the Android "remote deploy" button in the
   editor's top-right corner to install and run it directly.
4. `export_presets.cfg` contains machine-specific paths and passwords, so `export_credentials.cfg` is
   git-ignored. You can commit `export_presets.cfg` itself once you've created it if you want shared presets.

---

## Project structure

```
project.godot              Engine config (Mobile renderer, autoloads, physics layer names)
scenes/main.tscn           Entry scene (one node; everything else is built in code)
data/villagers/*.tres      The five villagers: identity, looks, schedule, dialogue, personality
shaders/                   sky, water, grass
scripts/
  core/                    Autoload singletons
    game_settings.gd         Quality presets and persisted settings (GameSettings)
    input_router.gd          Input actions; merges keyboard, gamepad and touch (InputRouter)
    world_clock.gd           Shared time of day, day counter, time speed (WorldClock)
    game_manager.gd          Registry of player and villagers, camera mode, conversations (GameManager)
    save_service.gd          Offline JSON save and autosave (SaveService)
  world/
    main.gd                  Bootstraps the world, player, camera, villagers and HUD
    village_layout.gd        THE source of truth: buildings, paths, waypoints, activity spots, river, bridge
    terrain_generator.gd     Height function, terrain mesh and collision, painted paths
    mesh_builder.gd          Flat-shaded vertex-coloured primitive merging
    materials.gd             Shared materials
    building_factory.gd      Every building and prop, assembled from primitives
    village_builder.gd       Places buildings from the layout
    river_builder.gd         Water, bank walls, world bounds, bridge
    nature_spawner.gd        Chunked MultiMesh trees, grass, rocks and so on
    village_navigation.gd    AStar3D waypoint graph and activity-spot reservations
    day_night_cycle.gd       Sun and moon, sky, ambient light, fog, night lights
    fire_flicker.gd          Campfire animation
  player/
    player_controller.gd     CharacterBody3D movement
    camera_rig.gd            Exploration and management cameras
  characters/
    character_appearance.gd  Resource describing how someone looks
    character_model.gd       Procedural humanoid and state-based procedural animation
  villagers/
    villager_data.gd         Static identity resource
    villager.gd              Runtime villager: walk, perform, sleep, talk
    villager_brain.gd        Decision interface (choose_activity)
    schedule_brain.gd        Milestone 1 brain: follows the timetable
    villager_activity.gd     What and where
    villager_mind.gd         Inner state: memory and relationships (extension point)
    memory_log.gd            Episodic memory
  interaction/
    interactable.gd          Area3D component: "this can be interacted with"
    interaction_detector.gd  Player's sensor that picks the best target
    dialogue_service.gd      Builds what a villager says
  ui/                      HUD, dialogue, villager card, settings, touch controls, theme
tests/                     Headless smoke test
```

### Architecture notes

- **Built in code, configured by data.** Geometry is generated from primitives, so the project has
  no binary assets and no fragile hand-edited scenes. Characters are `.tres` resources you can edit
  in the Inspector.
- **One layout file.** `VillageLayout` describes where everything is. The terrain paints paths from
  the navigation edges, decoration avoids footprints and paths, and villagers walk the same graph.
  Moving a building there moves everything with it.
- **Brains are swappable.** `Villager` only calls `brain.choose_activity(villager, hour)`. The
  planned needs, emotions and personality-driven AI is a new `VillagerBrain` subclass, and nothing
  else has to change. `VillagerData.personality` is already authored for each villager but not read yet.
- **The mind is the extension point.** `VillagerMind` owns memories and relationships. Needs,
  emotions, family links and ambitions belong there and are saved with it.
- **Decoupled systems.** Systems talk through `GameManager` signals (`conversation_started`,
  `villager_selected`, `camera_mode_changed`) rather than holding references to each other.
- **Physics layers.** 1 world, 2 player, 3 villagers, 4 interaction, 5 boundaries (invisible walls,
  ignored by the camera).

### Performance choices for affordable phones

- Mobile renderer. One directional light, which is the sun by day and the moon by night. Moonlight
  casts no shadows. Shadow distance and atlas size scale with quality.
- Each building is **one merged mesh** plus one glow mesh. Vegetation is **chunked MultiMeshes**
  (one draw call per type per 24 m chunk, culled per chunk). Grass, flowers and pebbles are
  distance-culled and cast no shadows.
- Ambient light comes from a flat colour and sky reflections are disabled, so the sky never forces
  costly radiance updates. Sky and fog parameters update ten times a second, not every frame.
- Villagers move along waypoints without physics queries. The only per-frame raycast is the camera's
  wall check.
- Quality presets (Low/Medium/High) control shadows, render scale (75/90/100 %), MSAA, glow, grass
  density and detail distance. On mobile the default is Medium.

---

## Status

### Implemented

Everything listed under [Milestone 1 contents](#milestone-1-contents).

### Not yet verified in the engine

This milestone was written in an environment without Godot. The checks that **were** done:

- every `.gd` file parses (`gdtoolkit` 4.5 `gdparse`), and `gdlint` reports style-only findings (long lines)
- a manual review for the GDScript type-inference errors that the parser cannot catch
- scene and resource paths checked against the files on disk
- layout geometry checked by hand: paths clear of buildings, bridge gap in the river walls, spots reachable

The game has **not** yet been opened in the Godot editor, run, profiled, or installed on an Android
device. Expect a first-run pass to fix small issues such as an off-by-a-bit prop, a lighting value or
any engine-reported script error. The first things to do are:

1. Open the project in Godot 4.3+ and check the *Output* and *Debugger* panels for errors.
2. Run `godot --headless --path . res://tests/smoke_test.tscn`.
3. Play through a full day at ×20 time speed.
4. Export to a mid-range Android phone and check FPS with *Menu → Show FPS* on each quality preset.

### Known limitations

- Animations are procedural placeholders (limb swings), not authored clips. `CharacterModel.set_animation()`
  is the seam where an `AnimationTree` with imported models can be added later.
- Changing the grass density preset applies on the next launch. Everything else applies immediately.
- Villagers do not avoid each other. They wait briefly if the player blocks their way, then carry on.
- Villagers sleep indoors (hidden). Houses have no interiors yet.
- Dialogue is greeting-level only, with memory-aware variation. There are no choices yet.

### Next milestones (not started)

Needs and emotions, personality-driven decisions, relationships between villagers, conversations with
choices whose consequences are remembered, families and generations, economy and resources, and
expanding the settlement.
