extends SceneTree
## Developer tool: renders the music themes and every sound effect to WAV
## files and prints loudness and loop-seam figures.
## Run: godot --headless --path . -s res://tools/sound_check.gd -- --out=/some/dir
func _init() -> void:
	var out := "user://sounds"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	for theme in [Music.DAY, Music.NIGHT]:
		var t0 := Time.get_ticks_msec()
		var samples := Music.render(theme)
		var ms := Time.get_ticks_msec() - t0
		_report("music_" + theme, samples, ms)
		var seam := absf(samples[samples.size() - 1] - samples[0])
		print("    loop seam jump: %.4f (a click would be > 0.1)" % seam)
		Synth.to_stream(samples).save_to_wav(out.path_join("music_%s.wav" % theme))
	var effects := SoundBank.effects()
	for name in effects:
		var i := 0
		for stream: AudioStreamWAV in effects[name]:
			_report_stream("%s_%d" % [name, i], stream)
			stream.save_to_wav(out.path_join("%s_%d.wav" % [name, i]))
			i += 1
	_report_stream("wind", Synth.to_stream(SoundBank.wind(), true))
	Synth.to_stream(SoundBank.wind()).save_to_wav(out.path_join("wind.wav"))
	var fire: AudioStreamWAV = SoundBank.fire()
	_report_stream("fire", fire)
	fire.loop_mode = AudioStreamWAV.LOOP_DISABLED
	fire.save_to_wav(out.path_join("fire.wav"))
	quit()


func _report_stream(name: String, stream: AudioStreamWAV) -> void:
	var s := PackedFloat32Array()
	var data := stream.data
	s.resize(data.size() / 2)
	for i in s.size():
		s[i] = data.decode_s16(i * 2) / 32768.0
	_report(name, s, 0)

func _report(name: String, s: PackedFloat32Array, ms: int) -> void:
	var peak := 0.0
	var sum := 0.0
	for v in s:
		peak = maxf(peak, absf(v))
		sum += v * v
	print("%s: %.1f s, rendered in %d ms, peak %.2f, loudness (RMS) %.3f" % [name, s.size() / float(Synth.RATE), ms, peak, sqrt(sum / s.size())])
