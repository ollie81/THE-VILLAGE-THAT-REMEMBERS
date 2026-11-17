extends Node
## Villagers' voices.
##
## SPOKEN uses the device's own text-to-speech engine (Android, Windows,
## macOS, Linux with speech-dispatcher), so villagers say their actual lines.
## Each person gets a voice from the installed ones and their own pitch and
## pace from their sex, age and temperament.
## BABBLE plays a short synthesized murmur shaped like the line (one blip
## per syllable, in the speaker's own pitch range) for devices without
## speech, or for players who prefer it. OFF is silent.
##
## Offline: everything is generated on the device, nothing is downloaded.

enum Mode { SPOKEN, BABBLE, OFF }
const MODE_NAMES: Array[String] = ["Spoken", "Babble", "Off"]
const SETTINGS_PATH := "user://voices.cfg"
## Lines from villagers further than this from the camera aren't voiced.
const HEARING_DISTANCE := 16.0
const MIX_RATE := 22050

var mode: int = Mode.SPOKEN
var volume: float = 0.8

var _tts_voices: Array = []
var _player_2d: AudioStreamPlayer
var _babble_cache: Dictionary = {}


func _ready() -> void:
	if DisplayServer.has_method("tts_get_voices") and _tts_supported():
		_tts_voices = DisplayServer.tts_get_voices()
	_load()
	if mode == Mode.SPOKEN and not has_speech():
		mode = Mode.BABBLE
	_player_2d = AudioStreamPlayer.new()
	_player_2d.name = "VoicePlayer"
	add_child(_player_2d)


static func _tts_supported() -> bool:
	if not bool(ProjectSettings.get_setting("audio/general/text_to_speech", false)) or DisplayServer.get_name() == "headless":
		return false
	# Linux needs speech-dispatcher; without it Godot logs an error on every query.
	if OS.get_name() == "Linux":
		return FileAccess.file_exists("/usr/bin/speech-dispatcher") or FileAccess.file_exists("/usr/bin/spd-say")
	return true


## True if the device can speak (it has at least one text-to-speech voice).
func has_speech() -> bool:
	return not _tts_voices.is_empty()


func set_mode(value: int) -> void:
	mode = clampi(value, 0, Mode.size() - 1)
	stop()
	_save()


# --- Who sounds like what ---------------------------------------------------------

## { pitch (0.5..2), rate (0.5..2), base_hz, seed } for a speaker. Anything
## with `data` (villagers) or the player.
func voice_of(speaker) -> Dictionary:
	var sex := "female"
	var age := 30
	var extraversion := 0.5
	var calm := 0.5
	var key := "player"
	if speaker != null and speaker.get("person") != null:
		var person: Person = speaker.person
		sex = person.sex
		age = person.age()
		extraversion = person.trait_weight("extraversion")
		calm = 1.0 - person.trait_weight("neuroticism")
		key = person.id
	elif speaker != null and speaker.get("data") != null:
		key = String(speaker.data.id)
		age = speaker.data.age
		sex = "male" if key in ["elias", "tomas"] else "female"
	elif speaker == GameManager.player:
		sex = "male"
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	# Wide, person-specific ranges, so two women or two men still sound
	# clearly different even on a phone with a single voice.
	var pitch := rng.randf_range(1.0, 1.35) if sex == "female" else rng.randf_range(0.68, 0.95)
	if age < 13:
		pitch = rng.randf_range(1.45, 1.65)
	elif age < 17:
		pitch = lerpf(1.45, pitch, (age - 13) / 4.0)
	elif age > 60:
		pitch -= 0.1
	var rate := rng.randf_range(0.9, 1.1) + (extraversion - 0.5) * 0.3 + (0.5 - calm) * 0.12
	if age > 60:
		rate -= 0.15
	elif age < 13:
		rate += 0.1
	var base_hz := 120.0 * pitch / 0.82 if sex == "male" else 205.0 * pitch / 1.18
	if age < 13:
		base_hz = 290.0 * pitch / 1.55
	return {"pitch": clampf(pitch, 0.5, 2.0), "rate": clampf(rate, 0.7, 1.4), "base_hz": base_hz, "seed": hash(key), "sex": sex}


## Known voice codes in Android's speech engines (Google and Samsung): which
## are women's and which men's. Their names otherwise don't say.
const GOOGLE_VOICES := {
	"iob": "female", "iog": "female", "iol": "male", "iom": "male", "sfg": "female", "tpc": "female", "tpd": "male", "tpf": "female",
	"gba": "female", "gbb": "male", "gbc": "female", "gbd": "male", "gbg": "female", "rjs": "male",
	"aua": "female", "aub": "male", "auc": "female", "aud": "male",
	"ena": "female", "enc": "female", "end": "male", "ene": "male",
}


## "female", "male" or "" (unknown) for a device voice.
static func voice_sex(voice: Dictionary) -> String:
	var name := (String(voice.get("name", "")) + " " + String(voice.get("id", ""))).to_lower()
	for code in GOOGLE_VOICES:
		if name.contains("-x-" + code):
			return GOOGLE_VOICES[code]
	if name.contains("smtf"):
		return "female"
	if name.contains("smtm"):
		return "male"
	if name.contains("female") or name.contains("woman"):
		return "female"
	if name.contains("male") or name.contains("man "):
		return "male"
	return ""


## English voices that work offline, if the device has any.
func english_voices() -> Array:
	var english: Array = _tts_voices.filter(func(v): return String(v.get("language", "")).to_lower().begins_with("en"))
	var pool: Array = english if not english.is_empty() else _tts_voices.duplicate()
	var offline: Array = pool.filter(func(v): return not String(v.get("id", v.get("name", ""))).to_lower().contains("network"))
	return offline if not offline.is_empty() else pool


## A text-to-speech voice for this speaker: one of the device's voices of
## their sex if it has any, each person keeping their own.
func tts_voice_id(speaker) -> String:
	var pool := english_voices()
	if pool.is_empty():
		return ""
	var voice := voice_of(speaker)
	var matching: Array = pool.filter(func(v): return voice_sex(v) == voice["sex"])
	if matching.is_empty():
		matching = pool.filter(func(v): return voice_sex(v) == "")
	if matching.is_empty():
		matching = pool
	# Hand voices out in turn among people of the same sex (in a stable
	# order), so nobody shares a voice until every voice is in use.
	var key := _speaker_key(speaker)
	var same: Array = []
	for villager in GameManager.villagers:
		if voice_of(villager)["sex"] == voice["sex"]:
			same.append(_speaker_key(villager))
	same.sort()
	var rank := same.find(key)
	if rank < 0:
		rank = absi(int(voice["seed"]))
	return String(matching[rank % matching.size()].get("id", ""))


static func _speaker_key(speaker) -> String:
	if speaker != null and speaker.get("data") != null:
		return String(speaker.data.id)
	return "player"


## e.g. "12 voices (5 women's, 6 men's)" for the settings screen.
func voices_summary() -> String:
	var pool := english_voices()
	if pool.is_empty():
		return "No speech voices on this device."
	var women := pool.filter(func(v): return voice_sex(v) == "female").size()
	var men := pool.filter(func(v): return voice_sex(v) == "male").size()
	return "%d voice%s found (%d women's, %d men's)." % [pool.size(), "" if pool.size() == 1 else "s", women, men]


## Plays a few villagers' voices one after another (Settings → Test voices).
func test_voices() -> void:
	var lines := ["[happy]Good morning! The bread's still warm.", "Mind the mud by the well, it's deep today.",
		"[laughing]Bet you can't catch me!", "[happy]Welcome back. We missed you."]
	# Two women and two men if the village has them, so the difference shows.
	var women: Array = GameManager.villagers.filter(func(v): return voice_of(v)["sex"] == "female")
	var men: Array = GameManager.villagers.filter(func(v): return voice_of(v)["sex"] == "male")
	var speakers: Array = women.slice(0, 2) + men.slice(0, 2)
	var delay := 0.0
	for i in speakers.size():
		var who = speakers[i]
		var line: String = lines[i % lines.size()]
		get_tree().create_timer(delay).timeout.connect(func():
			if is_instance_valid(who):
				speak_queued(who, "%s here. %s" % [who.data.display_name, line]))
		delay += 2.8


## Like speak(), but waits for the previous line instead of cutting it off.
func speak_queued(speaker, text: String) -> void:
	if mode == Mode.SPOKEN and has_speech():
		var voice := voice_of(speaker)
		DisplayServer.tts_speak(clean_text(text), tts_voice_id(speaker), int(volume * 100.0), float(voice["pitch"]), float(voice["rate"]))
	elif mode != Mode.OFF:
		_play_babble(speaker, clean_text(text))


# --- Speaking ----------------------------------------------------------------------

## Says `text` in `speaker`'s voice if they're close enough to hear (or
## `always` for the conversation partner).
func speak(speaker, text: String, always: bool = false) -> void:
	if mode == Mode.OFF or text.strip_edges() == "":
		return
	if not always and speaker is Node3D:
		var camera := (speaker as Node3D).get_viewport().get_camera_3d()
		if camera and camera.global_position.distance_to((speaker as Node3D).global_position) > HEARING_DISTANCE:
			return
	var clean := clean_text(text)
	if mode == Mode.SPOKEN and has_speech():
		var voice := voice_of(speaker)
		DisplayServer.tts_stop()
		DisplayServer.tts_speak(clean, tts_voice_id(speaker), int(volume * 100.0), float(voice["pitch"]), float(voice["rate"]))
		return
	_play_babble(speaker, clean)


func stop() -> void:
	if has_speech():
		DisplayServer.tts_stop()
	if _player_2d:
		_player_2d.stop()


static func clean_text(text: String) -> String:
	var parts := DialoguePanel.split_expression(text)
	var out: String = parts[1]
	if out.begins_with("@") and out.find(" ") > 0:
		out = out.substr(out.find(" ") + 1)
	return out.replace("...", ", ").strip_edges()


# --- Babble ------------------------------------------------------------------------

func _play_babble(speaker, text: String) -> void:
	var stream := babble(speaker, text)
	if speaker is Node3D and not GameManager.is_in_conversation():
		var player := AudioStreamPlayer3D.new()
		player.stream = stream
		player.unit_size = 6.0
		player.volume_db = linear_to_db(volume)
		(speaker as Node3D).add_child(player)
		player.position = Vector3(0, 1.5, 0)
		player.finished.connect(player.queue_free)
		player.play()
	else:
		_player_2d.stream = stream
		_player_2d.volume_db = linear_to_db(volume)
		_player_2d.play()


## A murmur shaped like `text`: one soft voiced blip per syllable with a
## little melody (questions rise, exclamations are brighter), in the
## speaker's pitch range. Cached per speaker and line.
func babble(speaker, text: String) -> AudioStreamWAV:
	var voice := voice_of(speaker)
	var key := "%d|%s" % [int(voice["seed"]), text]
	if _babble_cache.has(key):
		return _babble_cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var syllables := clampi(_count_syllables(text), 1, 14)
	var syllable_time := 0.11 / float(voice["rate"])
	var gap := 0.025
	var samples_per := int(syllable_time * MIX_RATE)
	var gap_samples := int(gap * MIX_RATE)
	var total := syllables * (samples_per + gap_samples)
	var data := PackedByteArray()
	data.resize(total * 2)
	var base: float = voice["base_hz"]
	var rising := text.ends_with("?")
	var bright := text.ends_with("!")
	var phase := 0.0
	var index := 0
	for s in syllables:
		var t := float(s) / maxf(syllables - 1, 1)
		var contour := 1.0 + 0.12 * sin(t * PI) + (0.18 * t if rising else -0.08 * t)
		var hz := base * contour * (1.0 + rng.randf_range(-0.07, 0.07)) * (1.06 if bright else 1.0)
		# A vowel colour per syllable: the second harmonic's weight.
		var vowel := rng.randf_range(0.15, 0.55)
		for i in samples_per:
			var x := float(i) / samples_per
			var envelope := sin(PI * x) * (1.0 - 0.3 * x)
			phase += TAU * hz / MIX_RATE
			var value := sin(phase) * 0.6 + sin(phase * 2.0) * vowel * 0.35 + sin(phase * 3.0) * 0.08
			_write(data, index, value * envelope * 0.5)
			index += 1
		for i in gap_samples:
			_write(data, index, 0.0)
			index += 1
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	if _babble_cache.size() > 64:
		_babble_cache.clear()
	_babble_cache[key] = stream
	return stream


static func _write(data: PackedByteArray, index: int, value: float) -> void:
	data.encode_s16(index * 2, int(clampf(value, -1.0, 1.0) * 32000.0))


static func _count_syllables(text: String) -> int:
	var count := 0
	var previous_vowel := false
	for c in text.to_lower():
		var vowel := c in "aeiouy"
		if vowel and not previous_vowel:
			count += 1
		previous_vowel = vowel
	return maxi(1, int(count * 0.6))


# --- Settings ----------------------------------------------------------------------

func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		mode = int(config.get_value("voices", "mode", Mode.SPOKEN))
		volume = float(config.get_value("voices", "volume", 0.8))


func _save() -> void:
	var config := ConfigFile.new()
	config.set_value("voices", "mode", mode)
	config.set_value("voices", "volume", volume)
	config.save(SETTINGS_PATH)
