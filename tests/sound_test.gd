extends Node
## Headless test of sound and music: the audio buses and volume settings,
## every sound effect, the music themes (rendered in the background, saved,
## then played and cross-faded between day and night), the fire, and the
## sounds hooked to footsteps, chopping, buttons and notices.
## Run:  godot --headless --path . res://tests/sound_test.tscn

var _failures: int = 0
var _main = null


func _ready() -> void:
	SaveService.enabled = false
	PopulationDirector.auto_arrivals = false
	Sounds.persist = false
	GameState.reset()
	_run.call_deferred()


func _check(condition: bool, description: String) -> void:
	if condition:
		print("  PASS  ", description)
	else:
		_failures += 1
		print("  FAIL  ", description)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _music_volume(stream: AudioStreamWAV) -> float:
	for player: AudioStreamPlayer in [Sounds._music_a, Sounds._music_b]:
		if player.stream == stream and player.playing:
			return player.volume_db
	return -80.0


func _run() -> void:
	print("== Sound test ==")
	# --- Buses and volumes ------------------------------------------------------------
	var buses := [Sounds.BUS_MUSIC, Sounds.BUS_EFFECTS, Sounds.BUS_AMBIENCE]
	_check(buses.all(func(b): return AudioServer.get_bus_index(b) != -1), "music, effects and ambience have their own volume")
	var effects_bus := AudioServer.get_bus_index(Sounds.BUS_EFFECTS)
	var saved_volume := float(Sounds.volumes[Sounds.BUS_EFFECTS])
	Sounds.set_volume(Sounds.BUS_EFFECTS, 0.5)
	_check(absf(AudioServer.get_bus_volume_db(effects_bus) - linear_to_db(0.5)) < 0.01, "a slider sets its volume")
	Sounds.set_volume(Sounds.BUS_EFFECTS, 0.0)
	_check(AudioServer.is_bus_mute(effects_bus), "all the way down mutes it")
	Sounds.set_volume(Sounds.BUS_EFFECTS, saved_volume)
	_check(not AudioServer.is_bus_mute(effects_bus), "and back up unmutes it")

	# --- Effects ------------------------------------------------------------------------
	var missing := []
	for sound in ["chop", "stone", "gather", "hammer", "step", "built", "pickup", "click", "notify", "open", "bird", "cricket"]:
		if not Sounds.has_effect(sound):
			missing.append(sound)
	_check(missing.is_empty(), "every sound effect exists %s" % str(missing))
	var bank := SoundBank.effects()
	_check(bank["chop"].size() == 3 and bank["step"].size() == 3 and bank["bird"].size() == 4, "chops, steps and birds come in variations")
	var silent := []
	for sound in bank:
		for stream: AudioStreamWAV in bank[sound]:
			var loud := 0
			for i in range(0, stream.data.size() - 1, 2):
				loud = maxi(loud, absi(stream.data.decode_s16(i)))
			if loud < 8000 or stream.get_length() > 2.0:
				silent.append(sound)
	_check(silent.is_empty(), "each is audible and short %s" % str(silent))
	var wind := SoundBank.wind()
	_check(absf(wind[wind.size() - 1] - wind[0]) < 0.06, "the wind loops without a click")

	# --- Music --------------------------------------------------------------------------
	# Start from nothing, as on a first launch.
	for theme in [Music.DAY, Music.NIGHT]:
		var path := Music._path(theme)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		Sounds._music.erase(theme)
	WorldClock.day = 2
	WorldClock.set_time(10.0)
	WorldClock.set_time_scale(0.0)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _frames(10)
	var t0 := Time.get_ticks_msec()
	var frames := 0
	var slowest := 0
	var last := Time.get_ticks_msec()
	while not Sounds.is_music_ready() and Time.get_ticks_msec() - t0 < 120000:
		await get_tree().process_frame
		frames += 1
		var now := Time.get_ticks_msec()
		slowest = maxi(slowest, now - last)
		last = now
	_check(Sounds.is_music_ready(), "the music is composed in %.1f s on first launch" % ((Time.get_ticks_msec() - t0) / 1000.0))
	_check(frames > 20, "in the background while the game runs (%d frames, slowest %d ms)" % [frames, slowest])
	_check(FileAccess.file_exists(Music._path(Music.DAY)) and FileAccess.file_exists(Music._path(Music.NIGHT)), "and saved for next time")
	var cached := Music.load_cached(Music.DAY)
	_check(cached != null and cached.get_length() > 30.0 and cached.loop_mode == AudioStreamWAV.LOOP_FORWARD,
		"the saved day theme loads back as a %.0f s loop" % (cached.get_length() if cached else 0.0))
	await _frames(2)
	_check(Sounds.current_theme() == Music.DAY, "the day theme plays in the morning")
	await _seconds(1.0)
	var day_stream: AudioStreamWAV = Sounds._music[Music.DAY]
	var night_stream: AudioStreamWAV = Sounds._music[Music.NIGHT]
	_check(_music_volume(day_stream) > -40.0, "fading in (%.0f dB)" % _music_volume(day_stream))
	WorldClock.set_time(21.0)
	await _frames(2)
	_check(Sounds.current_theme() == Music.NIGHT, "after dark the night theme takes over")
	await _seconds(2.0)
	_check(_music_volume(night_stream) > -40.0 and _music_volume(day_stream) < -25.0,
		"cross-fading (night %.0f dB, day %.0f dB)" % [_music_volume(night_stream), _music_volume(day_stream)])
	WorldClock.set_time(10.0)
	await _frames(2)
	_check(Sounds.current_theme() == Music.DAY, "and the day theme comes back in the morning")

	# --- The village --------------------------------------------------------------------------
	_check(Sounds._wind.playing, "the wind blows")
	var fire: AudioStreamPlayer3D = _main.find_child("FireSound", true, false)
	_check(fire != null and fire.playing and fire.stream is AudioStreamWAV and fire.bus == Sounds.BUS_AMBIENCE,
		"the fire crackles at the meeting circle")
	Sounds._creature_timer = 0.0
	await _frames(2)
	_check(Sounds._creatures.playing, "birds sing by day")

	# --- Hooked sounds ----------------------------------------------------------------------
	var player = GameManager.player
	await _frames(20)
	Sounds.history.clear()
	for i in 6:
		player._footsteps(player.walk_speed, 0.2)
	_check(Sounds.history.count("step") >= 2, "footsteps as the player walks (%d)" % Sounds.history.count("step"))
	var camera := get_viewport().get_camera_3d()
	var tree: ResourceNode = null
	for node in _main.find_children("*", "ResourceNode", true, false):
		var r := node as ResourceNode
		if r.kind == &"tree" and r.uses_left > 0 and (tree == null or r.global_position.distance_to(camera.global_position) < tree.global_position.distance_to(camera.global_position)):
			tree = r
	player.global_position = tree.global_position + Vector3(2.0, 0.5, 0.0)
	await _frames(30)
	Sounds.history.clear()
	tree.harvest(player)
	await _seconds(0.9)
	_check(Sounds.history.has("chop") and Sounds.history.has("pickup"), "chopping a tree goes thock %s (%.0f m away)" % [str(Sounds.history), tree.global_position.distance_to(camera.global_position)])
	Sounds.history.clear()
	var button := UiTheme.button("Test")
	add_child(button)
	button.pressed.emit()
	GameManager.notify("Hello")
	await _frames(2)
	_check(Sounds.history.has("click") and Sounds.history.has("notify"), "buttons click and notices chime %s" % str(Sounds.history))
	button.queue_free()
	Sounds.history.clear()
	Sounds.play("chop", camera.global_position + Vector3(200, 0, 0))
	_check(Sounds.history.is_empty(), "sounds far away aren't heard")

	print("== %s: %d failure(s) ==" % ["PASSED" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(0 if _failures == 0 else 1)
