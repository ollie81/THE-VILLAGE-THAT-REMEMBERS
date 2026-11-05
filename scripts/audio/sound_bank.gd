class_name SoundBank
extends RefCounted
## The recipes for every sound effect and ambient loop (see Synth).
## Kept apart from the Sounds autoload so tools and tests can render them.


static func effects() -> Dictionary:
	var result := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	var add := func(sound: String, samples: PackedFloat32Array) -> void:
		if not result.has(sound):
			result[sound] = []
		result[sound].append(Synth.to_stream(Synth.normalize(samples, 0.75)))
	for v in 3:
		# Axe into wood: a woody thump plus a short bright crack.
		var chop := Synth.thump(140.0 + v * 15.0, 0.35)
		Synth.mix(chop, Synth.envelope(Synth.noise(0.12, 0.55, rng), 0.001, 0.03), 0.0, 0.8)
		add.call("chop", chop)
		# Pick on stone: sharp click and a gritty tail.
		var stone := Synth.envelope(Synth.noise(0.3, 0.9, rng), 0.0005, 0.04)
		Synth.mix(stone, Synth.envelope(Synth.sweep(2400.0 + v * 300, 1800.0, 0.08), 0.0005, 0.03), 0.0, 0.6)
		Synth.mix(stone, Synth.thump(220.0, 0.2), 0.0, 0.4)
		add.call("stone", stone)
		# Rustling leaves.
		add.call("gather", Synth.envelope(Synth.noise(0.35, 0.25 + v * 0.05, rng), 0.05, 0.12))
		# Hammer on a nail: a ringing tap.
		var hammer := Synth.envelope(Synth.sweep(1500.0 + v * 120, 1450.0, 0.25, 0.0005), 0.0005, 0.06)
		Synth.mix(hammer, Synth.thump(180.0, 0.18), 0.0, 0.7)
		add.call("hammer", hammer)
		# Footsteps on grass: a soft, low brush.
		add.call("step", Synth.envelope(Synth.noise(0.12, 0.12 + v * 0.03, rng), 0.004, 0.035))
	# Something done: a little rising chime.
	var built := Synth.buffer(1.4)
	for i in 3:
		Synth.mix(built, Synth.bell(Synth.midi_hz([72.0, 76.0, 79.0][i]), 1.0), i * 0.12, 0.5)
	add.call("built", built)
	# Picking something up: two quick plucks.
	var pickup := Synth.buffer(0.5)
	Synth.mix(pickup, Synth.envelope(Synth.pluck(Synth.midi_hz(79.0), 0.4, 0.9, rng), 0.002, 0.15), 0.0, 0.6)
	Synth.mix(pickup, Synth.envelope(Synth.pluck(Synth.midi_hz(84.0), 0.35, 0.9, rng), 0.002, 0.15), 0.07, 0.6)
	add.call("pickup", pickup)
	# Buttons: a soft wooden tick.
	add.call("click", Synth.envelope(Synth.thump(600.0, 0.06), 0.0005, 0.02))
	# A notice or new request: a gentle two-note bell.
	var notify := Synth.buffer(1.2)
	Synth.mix(notify, Synth.bell(Synth.midi_hz(76.0), 0.9), 0.0, 0.5)
	Synth.mix(notify, Synth.bell(Synth.midi_hz(81.0), 0.9), 0.15, 0.4)
	add.call("notify", notify)
	# Opening a conversation: a soft pluck.
	add.call("open", Synth.envelope(Synth.pluck(Synth.midi_hz(67.0), 0.5, 0.6, rng), 0.002, 0.2))
	# Bird calls (several kinds) and a cricket chirp.
	for kind in 4:
		var bird := Synth.buffer(0.8)
		var notes := 2 + kind
		for n in notes:
			var base := 2600.0 + kind * 500.0 + rng.randf_range(-200, 200)
			Synth.mix(bird, Synth.sweep(base, base * rng.randf_range(1.1, 1.5), rng.randf_range(0.06, 0.12)), n * 0.13, 0.7)
		add.call("bird", bird)
	var cricket := Synth.buffer(0.6)
	for n in 6:
		Synth.mix(cricket, Synth.envelope(Synth.sweep(4200.0, 4300.0, 0.03, 0.002), 0.001, 0.02), n * 0.05 + (0.25 if n >= 3 else 0.0), 0.5)
	add.call("cricket", cricket)
	return result


## A seamless loop of soft wind (slowly swelling filtered noise).
static func wind() -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var seconds := 12.0
	var out := Synth.seamless(Synth.noise(seconds + 0.5, 0.04, rng), 0.5)
	for i in out.size():
		var t := float(i) / Synth.RATE
		out[i] *= 0.6 + 0.4 * sin(TAU * t / seconds) * sin(TAU * t * 2.0 / seconds + 1.0)
	return Synth.normalize(out, 0.5)


## A crackling, looping fire for the meeting circle (3D, fades with distance).
static func fire() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var seconds := 6.0
	var out := Synth.seamless(Synth.noise(seconds + 0.3, 0.08, rng), 0.3)
	for i in out.size():
		out[i] *= 0.35
	for pop in 40:
		var crack := Synth.envelope(Synth.noise(0.05, 0.8, rng), 0.0005, 0.008)
		Synth.mix_wrapped(out, crack, rng.randf_range(0.0, seconds), rng.randf_range(0.3, 1.0))
	return Synth.to_stream(Synth.normalize(out, 0.6), true)
