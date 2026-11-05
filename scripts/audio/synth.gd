class_name Synth
extends RefCounted
## Small sound-making toolkit: everything the game hears is generated here,
## on the device, from a few classic techniques: plucked strings
## (Karplus-Strong), soft pads (detuned sines), filtered noise (wind, fire,
## footsteps, chopping) and chirps (birds, crickets).
##
## Buffers are PackedFloat32Array in -1..1, mono, at RATE samples a second.

const RATE := 22050


static func buffer(seconds: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(seconds * RATE))
	return out


## Mixes `source` into `target` starting at `at` seconds, scaled by `gain`.
static func mix(target: PackedFloat32Array, source: PackedFloat32Array, at: float, gain: float = 1.0) -> void:
	var start := int(at * RATE)
	var n := mini(source.size(), target.size() - start)
	for i in n:
		target[start + i] += source[i] * gain


## Mixes with wrap-around (for seamless loops).
static func mix_wrapped(target: PackedFloat32Array, source: PackedFloat32Array, at: float, gain: float = 1.0) -> void:
	var start := int(at * RATE)
	var size := target.size()
	for i in source.size():
		var j := (start + i) % size
		target[j] += source[i] * gain


static func midi_hz(note: float) -> float:
	return 440.0 * pow(2.0, (note - 69.0) / 12.0)


## A plucked string (Karplus-Strong): bright attack, warm decay.
static func pluck(hz: float, seconds: float, brightness: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := buffer(seconds)
	var period := maxi(int(RATE / hz), 2)
	var line := PackedFloat32Array()
	line.resize(period)
	for i in period:
		line[i] = rng.randf_range(-1.0, 1.0)
	var index := 0
	var damping := lerpf(0.990, 0.998, brightness)
	for i in out.size():
		var next := (index + 1) % period
		var value := (line[index] + line[next]) * 0.5 * damping
		out[i] = line[index]
		line[index] = value
		index = next
	return out


## A soft bell (two inharmonic sines, fast attack, long decay): music box.
static func bell(hz: float, seconds: float) -> PackedFloat32Array:
	var out := buffer(seconds)
	var p1 := 0.0
	var p2 := 0.0
	for i in out.size():
		var t := float(i) / RATE
		var env := minf(t * 300.0, 1.0) * exp(-t * 3.2)
		p1 += TAU * hz / RATE
		p2 += TAU * hz * 2.76 / RATE
		out[i] = (sin(p1) * 0.75 + sin(p2) * 0.25 * exp(-t * 6.0)) * env
	return out


## A warm pad chord: several detuned sines with a slow swell.
static func pad(notes: Array, seconds: float, attack: float = 1.2, release: float = 1.5) -> PackedFloat32Array:
	var out := buffer(seconds)
	var phases := PackedFloat32Array()
	var steps := PackedFloat32Array()
	for note in notes:
		for detune: float in [-0.06, 0.06]:
			phases.append(randf() * TAU)
			steps.append(TAU * midi_hz(float(note) + detune) / RATE)
	var voices := phases.size()
	for i in out.size():
		var t := float(i) / RATE
		var env := minf(t / attack, 1.0) * minf((seconds - t) / release, 1.0)
		var value := 0.0
		for v in voices:
			phases[v] += steps[v]
			value += sin(phases[v]) + 0.15 * sin(phases[v] * 2.0)
		out[i] = value / voices * env
	return out


## White noise through a one-pole low-pass (cutoff 0..1, higher = brighter).
static func noise(seconds: float, cutoff: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := buffer(seconds)
	var y := 0.0
	for i in out.size():
		y += (rng.randf_range(-1.0, 1.0) - y) * cutoff
		out[i] = y
	return out


## Shapes a buffer with an attack/decay envelope (seconds).
static func envelope(samples: PackedFloat32Array, attack: float, decay: float) -> PackedFloat32Array:
	for i in samples.size():
		var t := float(i) / RATE
		samples[i] *= minf(t / maxf(attack, 0.0001), 1.0) * exp(-t / maxf(decay, 0.0001))
	return samples


## A pitched sweep (birds, blips): from `from_hz` to `to_hz`.
static func sweep(from_hz: float, to_hz: float, seconds: float, attack: float = 0.005) -> PackedFloat32Array:
	var out := buffer(seconds)
	var phase := 0.0
	for i in out.size():
		var t := float(i) / RATE
		var x := t / seconds
		phase += TAU * lerpf(from_hz, to_hz, x) / RATE
		out[i] = sin(phase) * minf(t / attack, 1.0) * sin(PI * x)
	return out


## A low thump with a pitch drop (chopping, knocking, hammering bodies).
static func thump(hz: float, seconds: float) -> PackedFloat32Array:
	var out := buffer(seconds)
	var phase := 0.0
	for i in out.size():
		var t := float(i) / RATE
		phase += TAU * hz * (1.0 + 1.5 * exp(-t * 40.0)) / RATE
		out[i] = sin(phase) * exp(-t * 18.0)
	return out


## Echoes (a simple feedback delay) so music sounds like it's in a space.
static func echo(samples: PackedFloat32Array, delay: float, feedback: float, wet: float, wrap: bool = true) -> PackedFloat32Array:
	var d := int(delay * RATE)
	var size := samples.size()
	var out := samples.duplicate()
	for pass_index in 2:
		for i in size:
			var j := i - d
			if j < 0:
				if not wrap:
					continue
				j += size
			out[i] = samples[i] + out[j] * feedback
	for i in size:
		out[i] = samples[i] * (1.0 - wet) + out[i] * wet
	return out


## Makes a buffer loop without a click: its last `fade` seconds are
## cross-faded into its start, and the buffer gets that much shorter.
static func seamless(samples: PackedFloat32Array, fade: float) -> PackedFloat32Array:
	var n := int(fade * RATE)
	var size := samples.size() - n
	var out := samples.slice(0, size)
	for i in n:
		var w := float(i) / n
		out[i] = samples[size + i] * (1.0 - w) + samples[i] * w
	return out


## Scales so the loudest sample reaches `peak`.
static func normalize(samples: PackedFloat32Array, peak: float = 0.8) -> PackedFloat32Array:
	var top := 0.0001
	for v in samples:
		top = maxf(top, absf(v))
	var gain := peak / top
	for i in samples.size():
		samples[i] *= gain
	return samples


## Makes a playable stream (16-bit mono). `loop` loops the whole buffer.
static func to_stream(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	return stream
