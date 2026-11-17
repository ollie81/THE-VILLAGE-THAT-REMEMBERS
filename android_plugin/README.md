# Village reminders (Android)

The game's own small Android plugin for the daily reminder notification.
CI copies `src/` into the Android build (`android/build/src/`) before the
Gradle export; `addons/village_reminders` adds the manifest entries (the
plugin, the receiver and the notification permission).

- `VillageNotify` (GDScript singleton `VillageNotify`): `schedule(id, title, text, delay_seconds)`,
  `cancel(id)`, `can_notify()`, `request_permission()`.
- `ReminderReceiver`: shows the notification when its time comes; tapping it opens the game.

Reminders are inexact alarms (no special permission), cleared if the phone
restarts; the game schedules the next one each time it's put away.
