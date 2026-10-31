# The Village That Remembers

*Your actions never disappear.*

A 3D civilisation and life simulation for Android, built with Godot 4 and GDScript.
You arrive in a small village of five people who each have their own personality, daily
routine and memory of you.

**Current state: Milestone 1, the first playable village.** See [Status](#status) for what has been
verified.

| Morning | Village View |
| --- | --- |
| ![Exploring in the morning](docs/screenshots/explore_morning.png) | ![Management camera](docs/screenshots/village_view.png) |
| **Night** | **Meeting a villager** |
| ![The village at night](docs/screenshots/night.png) | ![Dialogue with Mara](docs/screenshots/dialogue.png) |

### The villagers

| Front | Back |
| --- | --- |
| ![Characters from the front](docs/screenshots/characters_front.png) | ![Characters from behind](docs/screenshots/characters_back.png) |
| **Running (skeletal animation)** | **Gathering (crouch, held tools)** |
| ![Running](docs/screenshots/characters_run.png) | ![Gathering](docs/screenshots/characters_gather.png) |

Left to right: Mara, Elias, Nia, Tomas, Sera, and the player. The target art direction is
[`docs/concept/characters_concept.png`](docs/concept/characters_concept.png); see
[Characters](#characters) for how close the current models get and how to reach it.

*Screenshots are from Godot 4.3's OpenGL (Compatibility) fallback renderer on a CPU rasteriser. On
phones the Mobile renderer is used, and lighting will look slightly different.*

---

## Milestone 1 contents

| Area | What exists |
| --- | --- |
| World | Procedural low-poly terrain (flat village, hills at the edges), river valley with flowing water shader, arched wooden bridge, forest across the river, meadows, rocks, reeds, mushrooms, wind-swept grass and flowers |
| Buildings | Five homes (each with its owner's colours and personal props), meeting circle with fire pit, log benches and story stone, fenced farm with wheat/cabbage/carrot rows and a scarecrow, herb garden with raised beds and trellis, open workshop with workbench and anvil, storehouse with crates and barrels, Mara's half-built sixth house, the old "memory oak", lantern posts |
| Characters | Fully modelled 3D people: skinned meshes on a 19-bone humanoid skeleton with anatomical torso, limbs, hands with fingers, shoes, sculpted faces (eyes, brows, nose, lips, ears), layered clothing, hair and accessories. Keyframed skeletal animations (idle, walk, run, jump, work, gather, talk, wave) with cross-fading and held tools |
| Player | Walk, run, jump, smooth turning, gravity, collision with buildings, trees, villagers, river banks and world edge |
| Cameras | Third-person orbit camera with wall avoidance, a high "Village View" management camera (pan, zoom, rotate, tap a villager for their info card), and an over-the-shoulder conversation camera. Smooth blends between them |
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

## Installing on an Android phone (no setup needed)

Every push to GitHub builds an installable APK automatically (`.github/workflows/build.yml`):

1. On GitHub, open **Actions → Test and build Android APK** and pick the latest green run.
2. Under **Artifacts**, download `TheVillageThatRemembers-apk` (a zip) and unzip it on your phone.
   You can also download it on a computer and copy it across.
3. Open `TheVillageThatRemembers.apk`. Android will ask you to allow installing apps from your browser
   or file manager. Allow it, then tap **Install**.

This is a debug build for an arm64 phone (almost every phone from the last six years). It's signed
with a throwaway debug key, so installing a newer build may require uninstalling the old one first.
Uninstalling also removes the save.

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
    character_appearance.gd  Resource describing how someone looks (colours, body, clothes, hair)
    character_model.gd       Skeleton + skinned body + AnimationPlayer + held tool; set_animation()
    humanoid_rig.gd          19-bone skeleton (Godot humanoid bone names), rest pose
    humanoid_mesh_builder.gd Generates the skinned body, face, clothing, hair and accessories
    humanoid_animations.gd   Bakes the skeletal animation library (per posture)
    skinned_mesh_tool.gd     Low-level skinned geometry: lofts, ellipsoids, smooth normals
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
tools/                     Character gallery and in-game screenshot tools (see Characters)
docs/                      Screenshots and the character concept art
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

## Characters

Every person is a real 3D model built at load time from their `CharacterAppearance`:

- **Skeleton.** `HumanoidRig` has 19 bones named after Godot's `SkeletonProfileHumanoid` (`Hips`,
  `Spine`, `Chest`, `Neck`, `Head`, `LeftUpperArm`, `LeftLowerArm`, `LeftHand`, `LeftUpperLeg`, and so on).
- **Body.** `HumanoidMeshBuilder` lofts smooth cross-sections into one skinned mesh. Vertices at the
  elbows, knees, shoulders and waist are weighted between two bones so they bend instead of breaking.
  Long skirts are weighted toward the thigh on each side so they swing with the legs.
- **Animation.** `HumanoidAnimations` bakes real keyframed rotation tracks (plus a hips position track)
  into an `AnimationLibrary`. An `AnimationTree` blends idle into a walk/run mix driven by actual speed,
  sets playback rate from stride length so feet don't slide, and cross-fades into actions (jump, work,
  gather, talk, wave). Each character's posture (Tomas's stoop) is baked in.
- **Budget.** Each villager is about 3,500–4,200 triangles in one draw call, plus a small tool mesh.

### Faces

Each head is a separate skinned mesh on the same skeleton, so the body, rig and animations are
unchanged. The head is sculpted from a 30×32 grid of cross-sections with a brow ridge, eye sockets,
cheekbones, nose bridge, muzzle and chin. It also has:

- **Eyes:** eyeballs with a layered iris, pupil and catchlight; upper and lower eyelids with a lash line.
- **Features:** curved brows, a nose with nostrils, separate upper and lower lips over a mouth with
  teeth, and sculpted ears.
- **Skin:** per-vertex colour (warm cheeks, nose and chin, soft shadow around the eyes) on a dedicated
  skin material with wrapped diffuse lighting, a faint rim light and no self-shadowing.
- **Character traits:** each one comes from `CharacterAppearance` face parameters: jaw, chin,
  cheekbones, brow shape, eye size and tilt, nose, lips, wrinkles, freckles and a resting expression.
- **Expressions:** `CharacterModel.set_expression(name)` with neutral, happy, laughing, sad, angry,
  surprised and worried. These are blend shapes defined once in `FaceExpressions` and generated for
  every character, plus automatic blinking and mouth movement while speaking.
- **Dialogue tags:** a line can start with a tag such as `[laughing]` to set the face for that line.
- **Cost and caching:** about 6,000–7,000 triangles and about 3,500 vertices per head. Meshes are cached
  in `user://character_cache`, so after the first launch all five villagers load in under 20 ms.

![Expressions](docs/screenshots/faces/expressions.png)

| Conversation | Village View portrait |
| --- | --- |
| ![Talking to Elias](docs/screenshots/faces/talk_elias.png) | ![Selected villager](docs/screenshots/faces/village_view_selected.png) |

More are in `docs/screenshots/faces/`: per-character before/after comparisons, close-ups, every
conversation, and evening light. Render your own with
`godot --path . res://tools/face_gallery.tscn -- --out=/tmp/faces`.

To review character art without playing, render every character from five angles and in every
animation:

```bash
godot --path . res://tools/character_gallery.tscn -- --out=/tmp/gallery
godot --path . res://tools/game_screenshots.tscn -- --out=/tmp/shots   # in-game views
```

### Reaching the concept art

The concept art is painted, semi-realistic work: sculpted faces, cloth folds, textured leather,
individual braids. Code-generated geometry can't reach that fidelity; it needs artist-authored models.
The project is set up so they can drop in:

1. Model and texture each character in Blender (or a character creator), rigged to a humanoid skeleton.
2. Export as glTF (`.glb`) and import into Godot. In the import dialog, set the skeleton's
   *Bone Map* to `SkeletonProfileHumanoid` so the bones get the same names used here.
3. In `CharacterModel._build()`, instance the imported scene instead of calling `HumanoidMeshBuilder`.
   Keep the `Skeleton3D` named `Skeleton3D`.

The existing `HumanoidAnimations` clips then drive the imported model, or imported clips (such as
Mixamo animations retargeted through the same bone map) can replace them. The player, villager,
camera and test code don't change.

## Status

### Implemented

Everything listed under [Milestone 1 contents](#milestone-1-contents).

### Verified

Tested with **Godot 4.3-stable** (official Linux build):

- The headless smoke test passes **74/74 checks**, including the skeleton, skinning, triangle budget, animations and facial blend shapes of every villager (`godot --headless --path . res://tests/smoke_test.tscn`, exit code 0).
- A soak run through **two full in-game days at ×100 speed** produced no script or runtime errors.
- Rendered screenshots (above) in exploration and Village View, at morning, sunset and night, and during
  a conversation.

### Not yet verified

- The **Mobile (Vulkan) renderer**. The screenshots used the OpenGL fallback because this machine has no GPU.
- **Performance and touch controls on a real Android device**, and the APK export itself.
- Two engine messages, `Parameter "m" is null` (`mesh_get_surface_count`), appear only in headless mode,
  when the terrain and river meshes are freed at shutdown. They come from the dummy renderer and don't
  affect gameplay or test results.

### Known limitations

- Characters are stylised and code-generated, so they're simpler than the painted concept art. There are
  no textures, cloth folds or facial expressions yet. See [Reaching the concept art](#reaching-the-concept-art).
- Skeletal animations are hand-keyed in code (no motion capture), and feet aren't IK-planted on slopes.
- Tomas is 61 in the design brief but looks about 30 in the concept art. The game follows the brief
  (grey hair and beard).
- Changing the grass density preset applies on the next launch. Everything else applies immediately.
- Villagers do not avoid each other. They wait briefly if the player blocks their way, then carry on.
- Villagers sleep indoors (hidden). Houses have no interiors yet.
- Dialogue is greeting-level only, with memory-aware variation. There are no choices yet.

### Next milestones (not started)

Needs and emotions, personality-driven decisions, relationships between villagers, conversations with
choices whose consequences are remembered, families and generations, economy and resources, and
expanding the settlement.
