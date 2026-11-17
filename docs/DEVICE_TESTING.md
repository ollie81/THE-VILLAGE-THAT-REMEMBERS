# Real-device testing

The APK is built by CI on every push (GitHub → Actions → the run → *Artifacts* →
`TheVillageThatRemembers-apk`). Headless tests and screenshots on a PC don't prove
something works on a phone: this list is what to try on the phone.

## Reporting a problem

1. When something goes wrong, open **Menu → Report a problem** (near the bottom of
   Settings) and tap **Copy**.
2. Paste it into your message, with what you did, what happened and what you
   expected. A screenshot or screen recording helps a lot.

The report holds: the build (version and commit, so we know which APK you have), the
phone, Android version, screen size, renderer (Vulkan, or OpenGL if the phone fell
back), frame rate now and the lowest in the last minute, memory, the day and goal,
where you are and what you're standing next to, villagers, buildings, hens,
resources, when the game last saved, and the last 30 errors and warnings from the
game's log file (`user://logs/godot.log`, kept for the last 3 launches).

Saves are written to a temporary file first and the previous save is kept as a
backup, so if the phone closes the game mid-save the next launch loads the backup.

## Checklist

"Automated" says what the headless tests already check. Everything still needs a
look on the phone.

| Area | Try on the phone | Automated (test) |
|---|---|---|
| **Hens** | Build a coop (day 3, or after a farm plot). Three hens walk, peck, sit, go to the feeder after you Feed (1 herb), run from you, don't walk through posts or into the river. Next morning: 3 eggs in the nest, Collect gives 3 food. Close the app fully and reopen: eggs still there. | Hens move, vary, stay in run, flee; feeding, laying, collecting; eggs and feeding saved (quality, build) |
| **Tools** | Chop (axe), Mine (pickaxe), Build at a site (hammer), Plant (hoe), draw water at a well (watering can), Fish (rod). Each is in the right hand, the right way up, a sensible size; put away after. | Tool shown for each job, on the right hand bone, put away after (quality) |
| **Journal** | Tap the goal card (top left): Journal opens, scrolls, Close works. It says the next step, what's needed, where, which tool, the reward; progress changes as you play. | Contents, opening by tap on the card (quality, guide) |
| **Tips** | Tips appear one at a time, at sensible moments; Got it closes them; they don't come back. | Order and dismissal (quality) |
| **Houses** | Build a cottage, tap Enter, look round: kitchen, bedroom (behind a wall), dining/living. You start standing by the door, can walk everywhere, can't walk through furniture, can leave. Use bed, hearth, chest, window seat, books. Save, close, reopen: same room. | Doors, layout, spawn clear of furniture, usable furniture, same room each time (home, quality) |
| **Villagers** | People look different, walk about, go home at night, talk. Over several days new people arrive and you can see them in the village. | Schedules, conversations, arrivals, visibility (life, population, home) |
| **Activities** | Farm, fish, trade (day 3), cook at your hearth, craft at the workshop, find the chests, build, fight thornlings after the first week. | Each one (build, quality, adventure, retention) |
| **Phone** | Touch: stick, camera drag, pinch, buttons all respond; nothing hidden under a notch or rounded corner. Frame rate feels smooth (Settings → Show FPS). Phone doesn't get very hot. Pause the app and come back: no lost progress. | — (needs a real phone) |
