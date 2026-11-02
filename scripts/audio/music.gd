class_name Music
extends RefCounted
## The village's music, composed and played by the game itself.
##
## Day: a plucked melody wandering over a pentatonic scale, warm pad chords
## (I - vi - IV - V in C) and a soft bass, at an easy walking tempo.
## Night: music-box bells over slower, softer minor chords.
## Each theme is a seamless loop, rendered once (in the background) and saved
## so later launches start the music instantly.

const DAY := "day"
const NIGHT := "night"
const CACHE_DIR := "user://music_cache"
## Bump when the composition changes, so old saved loops are replaced.
const VERSION := 3


static func render(theme: String) -> PackedFloat32Array:
	return _night() if theme == NIGHT else _day()


static func _day() -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1201
	var bpm := 76.0
	var beat := 60.0 / bpm
	var bar := beat * 4.0
	# C, Am, F, G - twice, the second time with a little variation.
	var chords := [[60, 64, 67], [57, 60, 64], [53, 57, 60], [55, 59, 62],
		[60, 64, 67], [57, 60, 64], [53, 57, 62], [55, 59, 62]]
	var bars := chords.size() * 2
	var length := bars * bar
	var out := Synth.buffer(length)
	var scale := [60, 62, 64, 67, 69, 72, 74, 76]
	var note_index := 2
	for b in bars:
		var chord: Array = chords[b % chords.size()]
		var start := b * bar
		Synth.mix_wrapped(out, Synth.pad(chord, bar + 1.0, 0.6, 1.2), start, 0.22)
		# Bass on beats one and three.
		for half in 2:
			Synth.mix_wrapped(out, Synth.envelope(Synth.pluck(Synth.midi_hz(float(chord[0]) - 12.0), beat * 2.2, 0.2, rng), 0.005, 0.9),
				start + half * beat * 2.0, 0.35)
		# Melody: eighth notes with rests, moving in small steps.
		var step := 0.0
		while step < 4.0:
			var length_beats: float = [0.5, 0.5, 1.0, 1.0, 1.5][rng.randi_range(0, 4)]
			if rng.randf() < 0.72:
				note_index = clampi(note_index + rng.randi_range(-2, 2), 0, scale.size() - 1)
				var note: int = scale[note_index]
				# Lean on chord tones on strong beats.
				var classes: Array = chord.map(func(n): return int(n) % 12)
				if fmod(step, 2.0) == 0.0 and not classes.has(note % 12) and rng.randf() < 0.6:
					note = int(chord[rng.randi_range(0, 2)]) + 12
				var pluck := Synth.pluck(Synth.midi_hz(float(note)), beat * 2.5, 0.75, rng)
				Synth.mix_wrapped(out, Synth.envelope(pluck, 0.003, 1.1), start + step * beat, 0.28)
			step += length_beats
	out = Synth.echo(out, beat * 0.75, 0.35, 0.3)
	return Synth.normalize(out, 0.7)


static func _night() -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2207
	var bpm := 58.0
	var beat := 60.0 / bpm
	var bar := beat * 4.0
	# Am, F, C, G, Am, Dm, F, E (soft minor, a little longing).
	var chords := [[57, 60, 64], [53, 57, 60], [48, 52, 55], [55, 59, 62],
		[57, 60, 64], [50, 53, 57], [53, 57, 60], [52, 56, 59]]
	var bars := chords.size()
	var length := bars * bar
	var out := Synth.buffer(length)
	var scale := [69, 71, 72, 74, 76, 79, 81]
	var note_index := 2
	for b in bars:
		var chord: Array = chords[b]
		var start := b * bar
		Synth.mix_wrapped(out, Synth.pad(chord, bar + 2.0, 1.5, 1.8), start, 0.26)
		var step := 0.0
		while step < 4.0:
			var length_beats: float = [1.0, 1.0, 1.5, 2.0][rng.randi_range(0, 3)]
			if rng.randf() < 0.6:
				note_index = clampi(note_index + rng.randi_range(-2, 2), 0, scale.size() - 1)
				Synth.mix_wrapped(out, Synth.bell(Synth.midi_hz(float(scale[note_index])), beat * 3.0), start + step * beat, 0.22)
			step += length_beats
	out = Synth.echo(out, beat, 0.45, 0.4)
	return Synth.normalize(out, 0.6)


# --- Saved loops ---------------------------------------------------------------------------

static func _path(theme: String) -> String:
	return "%s/%s_v%d.pcm" % [CACHE_DIR, theme, VERSION]


## A loop from the save, or null.
static func load_cached(theme: String) -> AudioStreamWAV:
	var path := _path(theme)
	if not FileAccess.file_exists(path):
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 1000:
		return null
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = Synth.RATE
	stream.data = bytes
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = bytes.size() / 2
	return stream


static func save_cached(theme: String, stream: AudioStreamWAV) -> void:
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	var file := FileAccess.open(_path(theme), FileAccess.WRITE)
	if file:
		file.store_buffer(stream.data)
