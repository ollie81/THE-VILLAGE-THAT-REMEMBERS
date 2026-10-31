class_name LineBank
extends RefCounted
## Things villagers say about what's happening, in several tones, so each
## person sounds like themselves and nobody repeats the same line. Lines can
## use {player}, {name}, {other}, {thing}, {place}, {time}.
##
## Tones: warm (likes you), cool (dislikes you), grumpy (blunt people),
## shy (quiet people), cheerful (outgoing people), child, plain.

const LINES := {
	# --- Reactions to the player -------------------------------------------------
	"wave": {
		"warm": ["[happy]Hello there!", "[laughing]Hi! Good to see you!", "[happy]There you are!"],
		"cheerful": ["[laughing]Hey! Over here!", "[happy]Hello, hello!"],
		"shy": ["[happy]Oh! ...Hi.", "[happy]Hello."],
		"grumpy": ["Yes, yes, hello.", "Mm. Hello."],
		"cool": ["...", "[worried]What do you want?"],
		"child": ["[laughing]Hiiii!", "[laughing]Hello! Hello!"],
		"plain": ["[happy]Hello!", "[happy]Morning to you too."],
	},
	"bow": {
		"warm": ["[happy]Oh, how polite!", "[laughing]Ha! At your service too."],
		"cheerful": ["[laughing]Your Majesty!", "[laughing]Ooh, so fancy!"],
		"shy": ["[surprised]Oh! Um. *bows back*"],
		"grumpy": ["We're not at court, you know."],
		"cool": ["Hmph."],
		"child": ["[laughing]Are you a knight?!"],
		"plain": ["[happy]And a good day to you."],
	},
	"cheer": {
		"warm": ["[laughing]Yes! Whatever it is, I'm happy too!", "[happy]That's the spirit!"],
		"cheerful": ["[laughing]Woo! Hooray!"],
		"shy": ["[happy]...Yay."],
		"grumpy": ["What are we cheering about?"],
		"cool": ["Someone's pleased with themselves."],
		"child": ["[laughing]Yaaay!"],
		"plain": ["[happy]Good news, is it?"],
	},
	"dance": {
		"warm": ["[laughing]Look at you go!", "[laughing]Ha! Teach me that one!"],
		"cheerful": ["[laughing]Music! Somebody get a fiddle!", "[laughing]Ooh, I can't resist!"],
		"shy": ["[surprised]Oh my...", "[happy]*taps foot quietly*"],
		"grumpy": ["Some of us are trying to work.", "Is that... dancing?"],
		"cool": ["[worried]People are watching, you know."],
		"child": ["[laughing]Me too! Me too!"],
		"plain": ["[laughing]Ha! Not bad at all."],
	},
	"sit_near": {
		"warm": ["[happy]Sit with me a while.", "[happy]Nice to rest together, isn't it?"],
		"cheerful": ["[laughing]Pull up a log! Have you heard the latest?"],
		"shy": ["[happy]...It's peaceful here."],
		"grumpy": ["Plenty of room. Don't take all of it."],
		"cool": ["[worried]Oh. You're sitting here."],
		"child": ["[laughing]Can I sit on your lap? Just kidding!"],
		"plain": ["[happy]A good spot to rest."],
	},
	"slept_outside": {
		"warm": ["[worried]Did you sleep outside? You should have knocked, I'd have found you a blanket!"],
		"cheerful": ["[laughing]Slept under the stars, did you? Very romantic. Very cold."],
		"shy": ["[worried]I saw you sleeping in the grass... are you alright?"],
		"grumpy": ["Sleeping in the dirt. Build yourself a house."],
		"cool": ["Saw you sleeping out there like a stray."],
		"child": ["[laughing]You slept OUTSIDE? Like a fox?"],
		"plain": ["[worried]Sleeping outdoors? You'll catch a chill."],
	},
	# --- Passing by -------------------------------------------------------------
	"greet_morning": {
		"warm": ["[happy]Morning! Sleep well?", "[happy]Good morning, {player}!"],
		"cheerful": ["[laughing]Morning! Beautiful day for it!", "[happy]Up early, I see!"],
		"shy": ["[happy]Morning.", "[happy]Oh, good morning."],
		"grumpy": ["Morning. Too early for talking.", "Mm. Morning."],
		"cool": ["...Morning."],
		"child": ["[laughing]Morning! I'm going to play by the river!"],
		"plain": ["[happy]Good morning."],
	},
	"greet_day": {
		"warm": ["[happy]Hello again!", "[happy]Nice to see you about."],
		"cheerful": ["[laughing]There's my favourite newcomer!", "[happy]Busy day?"],
		"shy": ["[happy]Hi."],
		"grumpy": ["Busy. Can't stop."],
		"cool": ["Hm."],
		"child": ["[laughing]Bet you can't catch me!", "[laughing]Hi! Hi!"],
		"plain": ["[happy]Afternoon."],
	},
	"greet_evening": {
		"warm": ["[happy]Coming to the fire tonight?", "[happy]Evening! Long day?"],
		"cheerful": ["[laughing]Evening! The stories start soon!"],
		"shy": ["[happy]Good evening."],
		"grumpy": ["Evening. My feet hurt."],
		"cool": ["Evening."],
		"child": ["[worried]I don't want to go to bed yet!"],
		"plain": ["[happy]Good evening."],
	},
	"busy_working": {
		"warm": ["[happy]Can't stop, but hello!"],
		"cheerful": ["[laughing]Work, work, work! Then supper!"],
		"shy": ["[happy]Just... working."],
		"grumpy": ["Mind your feet, I'm working here."],
		"cool": ["Don't you have something to do?"],
		"child": ["[happy]I'm helping! Look!"],
		"plain": ["[happy]Hard at it today."],
	},
	# --- Gifts and deeds ---------------------------------------------------------
	"gift_love": {
		"warm": ["[laughing]For me? Oh, {thing} is exactly what I needed!", "[happy]You remembered! Thank you!"],
		"cheerful": ["[laughing]{thing}! You're wonderful!"],
		"shy": ["[happy]Oh... for me? Thank you. Really."],
		"grumpy": ["[happy]...Well. That's actually useful. Thanks."],
		"cool": ["[surprised]Oh. That's... kind of you. Thank you."],
		"child": ["[laughing]For ME?! Thank you thank you!"],
		"plain": ["[happy]{thing}! Thank you, that's very kind."],
	},
	"gift_ok": {
		"warm": ["[happy]That's sweet of you, thank you."],
		"cheerful": ["[happy]Ooh, a present! Thanks!"],
		"shy": ["[happy]Thank you."],
		"grumpy": ["What am I meant to do with {thing}? ...Thanks, I suppose."],
		"cool": ["I'll take it. Thanks."],
		"child": ["[happy]Thanks! What is it for?"],
		"plain": ["[happy]Thank you, that's thoughtful."],
	},
	"compliment": {
		"warm": ["[laughing]Stop it, you!", "[happy]You always know what to say."],
		"cheerful": ["[laughing]I know! But it's nice to hear."],
		"shy": ["[happy]Oh... nobody's ever said that."],
		"grumpy": ["[surprised]Huh. Well. Thank you."],
		"cool": ["Flattery won't fix things."],
		"child": ["[laughing]I know I'm the best!"],
		"plain": ["[happy]That's kind of you to say."],
	},
	"joke_good": {
		"warm": ["[laughing]Ha! That's terrible. I love it.", "[laughing]Oh, you're funny!"],
		"cheerful": ["[laughing]Hahaha! I'm telling everyone that one!"],
		"shy": ["[laughing]*giggles*"],
		"grumpy": ["[laughing]...Ha. Alright, that was funny."],
		"cool": ["Hm. Funny."],
		"child": ["[laughing]Again! Tell it again!"],
		"plain": ["[laughing]Ha! Good one."],
	},
	"joke_bad": {
		"warm": ["[happy]I... don't get it. But thanks for trying!"],
		"cheerful": ["[surprised]Was that the end?"],
		"shy": ["[worried]Oh. Um. Ha?"],
		"grumpy": ["No."],
		"cool": ["Was that meant to be funny?"],
		"child": ["[worried]I don't get it."],
		"plain": ["[surprised]Was that a joke?"],
	},
	"insult": {
		"warm": ["[sad]I thought we were friends.", "[sad]Why would you say that?"],
		"cheerful": ["[angry]Wow. Rude!", "[sad]That hurt, you know."],
		"shy": ["[sad]...", "[sad]I'll just go."],
		"grumpy": ["[angry]Say that again and see what happens.", "[angry]Charming. Get lost."],
		"cool": ["[angry]I knew you were trouble."],
		"child": ["[sad]I'm telling my mum!"],
		"plain": ["[angry]That's uncalled for."],
	},
	"prank": {
		"warm": ["[surprised]Hey! ...Alright, you got me.", "[laughing]Oh, you rascal!"],
		"cheerful": ["[laughing]Ha! I'll get you back for that!"],
		"shy": ["[worried]Eek!"],
		"grumpy": ["[angry]Grow up."],
		"cool": ["[angry]You think that's funny?"],
		"child": ["[laughing]Again! Do it again!"],
		"plain": ["[surprised]Hey!"],
	},
	"caught_stealing": {
		"warm": ["[sad]You're... taking my things? I trusted you.", "[angry]I saw that!"],
		"cheerful": ["[angry]Oi! Thief!"],
		"shy": ["[worried]That's... that's mine..."],
		"grumpy": ["[angry]Thief! Put it back!"],
		"cool": ["[angry]I knew it. A thief."],
		"child": ["[sad]That's not yours!"],
		"plain": ["[angry]Hey! That's mine!"],
	},
	"witness_bad": {
		"warm": ["[worried]I can't believe you did that.", "[sad]That wasn't like you."],
		"cheerful": ["[surprised]Did you just...?"],
		"shy": ["[worried]Oh no..."],
		"grumpy": ["[angry]I saw that."],
		"cool": ["[angry]Typical."],
		"child": ["[surprised]Ooooh, you're in trouble!"],
		"plain": ["[worried]That wasn't kind."],
	},
	"witness_good": {
		"warm": ["[happy]That was lovely of you."],
		"cheerful": ["[laughing]Aww! Look at that!"],
		"shy": ["[happy]..."],
		"grumpy": ["Hm. Not bad."],
		"cool": ["Hm."],
		"child": ["[happy]That was nice!"],
		"plain": ["[happy]Kind of you."],
	},
}


## The tone someone speaks to the player in, from who they are and how they
## feel about the player.
static func tone_of(villager) -> String:
	var person: Person = villager.person if villager.get("person") else null
	if person and person.age() < 13:
		return "child"
	var affection: float = villager.mind.get_affection(GameManager.PLAYER_ID)
	if affection <= -20.0:
		return "cool"
	var p: Dictionary = villager.data.personality
	var agreeable := float(p.get("agreeableness", 0.5))
	var social := float(p.get("extraversion", 0.5))
	if affection >= 25.0:
		return "warm"
	if agreeable < 0.38:
		return "grumpy"
	if social > 0.65:
		return "cheerful"
	if social < 0.35:
		return "shy"
	return "plain"


## A line for `situation`, in this villager's tone, avoiding what they said
## recently. Fills in {player}, {name} and any `fill` values.
static func pick(villager, situation: String, fill: Dictionary = {}) -> String:
	var options: Dictionary = LINES.get(situation, {})
	if options.is_empty():
		return ""
	var tone := tone_of(villager)
	var lines: Array = (options.get(tone, options.get("plain", [])) as Array).duplicate()
	if lines.is_empty():
		lines = options.values()[0]
	var line := _fresh(villager, lines)
	var values := {"player": "friend", "name": villager.data.display_name}
	values.merge(fill, true)
	return line.format(values)


## The least recently used of `lines` for this speaker.
static func _fresh(villager, lines: Array) -> String:
	var said: Array = villager.get_meta("recent_lines", [])
	var unused: Array = lines.filter(func(l): return not said.has(l))
	var pool: Array = unused if not unused.is_empty() else lines
	var line: String = pool[randi() % pool.size()]
	said.append(line)
	if said.size() > 24:
		said.pop_front()
	villager.set_meta("recent_lines", said)
	return line
