class_name TalkBrain
extends RefCounted
## Understands what the player types to a villager, and how that villager
## answers. This is rule-based and runs on the phone: it recognises common
## kinds of message (greetings, questions about work, family, the village,
## other people, worries, the weather; compliments, insults, apologies,
## thanks; telling them your name, what you like, where you're from) by
## their words. It does not understand language in general. When it can't
## tell what was meant, the villager says so honestly and suggests what you
## can talk about, instead of pretending.
##
## Answers come from each villager's own voice (Mara is blunt, Elias gentle,
## Nia curious, Tomas slow and wise, Sera playful; newcomers get a style from
## their personality) and from what's true right now: their mood, what
## they're doing, the time, how they feel about you, and only what they
## actually remember (facts you told them and things you did, all saved).

const MAX_LENGTH := 160
## Facts kept per kind (newest win).
const MAX_LIKES := 3

## What each kind of message looks like (checked in order; the first match
## wins). Patterns run on lower-case text with punctuation removed.
const INTENTS := [
	["farewell", "\\b(bye|goodbye|good bye|see you|see ya|farewell|good night|goodnight|gotta go|got to go|i have to go|i must go|take care|later)\\b"],
	["apology", "\\b(sorry|apologi[sz]e|my fault|forgive me|my bad)\\b"],
	["insult", "\\b(stupid|idiot|ugly|i hate you|hate you|shut up|dumb|useless|loser|annoying|boring|pathetic|fool|smell)\\b"],
	["player_name", "\\b(my name is|my name s|call me|i m called|they call me|i go by)\\s+[a-z]"],
	["ask_player_name", "\\b(what s my name|what is my name|do you know my name|remember my name|who am i)\\b"],
	["ask_recall", "\\b(do you remember|remember me|what do you know about me|what do you remember|you remember)\\b"],
	["compliment", "\\b(you re|you are|you look|youre)\\s+(so\\s+|really\\s+|very\\s+)?(kind|nice|great|lovely|beautiful|pretty|handsome|amazing|wonderful|clever|smart|brave|funny|strong|wise|the best|awesome|cool|sweet|talented|good at)|\\bi like you\\b|\\bi love you\\b|\\b(great|good|nice|lovely|amazing) (work|job|house|garden|farm|cooking)\\b|\\bwell done\\b|\\bi admire\\b"],
	["thanks", "\\b(thanks|thank you|thank u|thx|cheers|appreciate it|grateful)\\b"],
	["player_like", "\\bi (really |also |do )?(like|love|enjoy|adore)\\s+[a-z]"],
	["player_from", "\\b(i m from|i am from|i come from|i grew up in)\\s+[a-z]"],
	["player_feeling", "\\b(i m|i am|im|i feel|feeling)\\s+(so\\s+|really\\s+|very\\s+|a bit\\s+)?(sad|tired|happy|lonely|bored|scared|worried|great|good|fine|ok|okay|sick|ill|hungry|angry|upset|excited|lost|exhausted)\\b"],
	["ask_help", "\\b((can|could|would|will) you help|help me|i need help|can you do something|could you do something|give me a hand)\\b"],
	["offer_help", "\\b(can i help|could i help|need (any |some )?help|help you|anything i can do|let me help|i ll help|i can help|want help)\\b"],
	["how_are_you", "\\b(how are you|how re you|how are things|how s it going|how is it going|how do you feel|are you ok|are you okay|you alright|you ok|how have you been|how s life|how is life|how are you doing|hows it going)\\b"],
	["ask_name", "\\b(what s your name|what is your name|who are you|your name)\\b"],
	["ask_activity", "\\b(what are you doing|what re you doing|what are you up to|what you up to|where are you going|are you busy|you busy)\\b"],
	["ask_job", "\\b(your job|your work|your trade|what do you do|how s work|how is work|what is your job|do you work|for a living)\\b"],
	["ask_family", "\\b(family|wife|husband|partner|children|kids|son|daughter|parents|mother|father|mum|mom|dad|married|baby|brother|sister)\\b"],
	["ask_news", "\\b(news|what s new|whats new|gossip|heard anything|anything new|what s happening|what happened|anything happen|any news)\\b"],
	["ask_worries", "\\b(worried|worry|scared|afraid|problem|trouble|upset|something wrong|what s wrong|whats wrong|bothering you|are you sad|feeling down|unhappy)\\b"],
	["ask_village", "\\b(village|this place|live here|like it here|this town|around here)\\b"],
	["ask_likes", "\\b(favou?rite|what do you like|do you like|hobby|hobbies|for fun|what makes you happy|you enjoy|do you love)\\b"],
	["weather", "\\b(weather|raining|rain|sunny|sun|cold|hot|storm|windy|snow)\\b"],
	["ask_time", "\\b(what time|time is it|is it late|getting late)\\b"],
	["joke", "\\b(joke|make me laugh|something funny|funny story)\\b"],
	["greeting", "^(hi|hello|hey|hiya|howdy|greetings|yo|good morning|good afternoon|good evening|morning|evening|afternoon|hallo|helo|heya)\\b"],
	["yes", "^(yes|yeah|yep|yup|sure|of course|ok|okay|alright|definitely|absolutely)\\b"],
	["no", "^(no|nope|nah|not really|never)\\b"],
]

## How each villager talks. Founders have their own voice; everyone else
## gets one of the general styles from their personality.
## Lines may use {you} (", <your name>" if they know it), {name}, {job}.
const VOICES := {
	"mara": {
		"greeting": ["[happy]Hey{you}. Good timing, I needed a break.", "Morning{you}. Mind the sawdust.", "[happy]There you are{you}. Grab a hammer or grab a seat."],
		"how_good": ["[happy]Good. Walls are going up, nobody's hurt. That's a good day.", "[happy]Can't complain. Well, I could, but I won't."],
		"how_ok": ["Busy. Tired. The usual.", "Fine. My shoulders say otherwise."],
		"how_bad": ["[worried]Honestly? Not great.", "[sad]I've had better days."],
		"job": ["[happy]I build. Houses, fences, the bridge when it sags. If it stands up in this village, I've had my hands on it.", "Building. Measure twice, cut once, swear three times."],
		"likes": ["[happy]A straight beam, a sharp chisel and a roof that doesn't leak. And honest people.", "Fresh-cut pine. The smell of it. Don't laugh."],
		"worries": ["[worried]The wolves past the river. And whether the old storehouse roof makes it through another storm.", "[worried]Someone's going to get hurt on that bridge one day. I keep patching it."],
		"village": ["[happy]It's small, but it's ours. Every board in it means something.", "Give it ten years. This'll be a proper town."],
		"family": ["My family's this village. Tomas taught me everything, so he counts.", "[laughing]Family? I've got Tomas grumbling at me and a hundred unfinished jobs."],
		"joke": ["[laughing]Why did the carpenter quit? Too many boring jobs. ...I'll see myself out."],
		"thanks": ["[happy]Don't mention it.", "Any time. Really."],
		"compliment": ["[surprised]Oh. Well. Thanks. I don't hear that much.", "[happy]Ha! Flattery won't get you a free fence. ...Maybe a gate."],
		"insult": ["[angry]Say that again and see what happens.", "[angry]Watch your mouth."],
		"farewell": ["[happy]Go on then. Don't trip over my timber.", "See you around{you}."],
		"unknown": ["Not sure what you mean. Ask me plainly: work, the village, the news, how I'm doing.", "[surprised]You've lost me there. Try something simpler?"],
		"cool": ["I'm busy.", "Make it quick."],
	},
	"elias": {
		"greeting": ["[happy]Ah, hello{you}. Come, sit a moment.", "[happy]Good to see you{you}. The fields can wait a minute.", "[happy]Hello, friend. You look like you could use some bread."],
		"how_good": ["[happy]Grateful, mostly. The wheat's coming up and nobody's gone hungry.", "[happy]I'm well, thank you for asking. Truly."],
		"how_ok": ["Tired, but it's a good tired. Fields don't tend themselves.", "Steady. Like the seasons."],
		"how_bad": ["[sad]Not my best day, if I'm honest. But it'll pass. Things do.", "[worried]A little heavy-hearted today."],
		"job": ["[happy]I farm. Wheat, beans, whatever the soil will give. And I make sure it gets shared.", "I grow the food. Up at dawn, down at dusk. I wouldn't trade it."],
		"likes": ["[happy]Rain on a dry field. Bread still warm from the oven. A quiet supper with friends.", "[happy]Watching things grow. Seeds, children, friendships. Same patience for all of them."],
		"worries": ["[worried]The crows, the dry spells... and whether everyone has enough put by for winter.", "[worried]I worry someone's going hungry and too proud to say."],
		"village": ["[happy]People here look after each other. That's worth more than gold.", "[happy]It's a good place. It'll be better still with you in it."],
		"family": ["[happy]Everyone here's family, in a way. I feed them like it, anyway.", "No wife, no children. Just a lot of neighbours who treat my kitchen as theirs."],
		"joke": ["[laughing]What did the farmer say when he lost his tractor? 'Where's my tractor?' ...I never said I was good at jokes."],
		"thanks": ["[happy]You're very welcome, friend.", "[happy]No thanks needed."],
		"compliment": ["[happy]That's kind of you to say. You're kind too, you know.", "[happy]Oh, now. You'll make an old farmer blush."],
		"insult": ["[sad]That wasn't very kind. I hope you're just having a bad day.", "[sad]Hm. I'll pretend I didn't hear that."],
		"farewell": ["[happy]Go well{you}. Come by for supper sometime.", "[happy]Take care of yourself."],
		"unknown": ["[surprised]I'm afraid I don't follow, friend. You can ask me about the farm, the village, or how folk are doing.", "Hm. I didn't quite catch your meaning. Say it another way?"],
		"cool": ["[sad]I'd rather not talk just now.", "Hm. Yes?"],
	},
	"nia": {
		"greeting": ["[happy]Oh, hi{you}! Look, I found a new kind of moss.", "[happy]Hello{you}! Perfect timing, I've got a question for you. ...Actually, you first.", "[laughing]Hi! Don't mind the mud, I've been digging."],
		"how_good": ["[happy]Wonderful! The chamomile's flowering and I worked out why the mint keeps wilting.", "[laughing]Really good! My head's full of ideas. Too full, probably."],
		"how_ok": ["Alright! A bit distracted. I keep thinking about root systems.", "Fine, fine. Busy brain day."],
		"how_bad": ["[worried]Honestly a bit overwhelmed. Too many things to figure out.", "[sad]Not great. One of my seedling trays died and I don't know why."],
		"job": ["[happy]I grow herbs and make remedies. Feverfew for headaches, mint for tummies, willow bark for aches. Want to know more? Everything's fascinating.", "Gardens and medicine! Half science, half guesswork, all mud."],
		"likes": ["[happy]Books, flowers, figuring out how things work. And rainy mornings, because everything smells green.", "[laughing]Ooh, so many things. Pressed flowers. Old maps. Questions with no answers yet."],
		"worries": ["[worried]That I'll mix up two plants one day and make someone ill. I check everything three times.", "[worried]The pond's been murky lately. I want to know why."],
		"village": ["[happy]I love it! There are at least forty kinds of plant within a short walk. I'm counting.", "[happy]It's full of interesting people. You included."],
		"family": ["My parents live far away, in the city. They wanted me to be a scholar. I'm a scholar of weeds now!", "[laughing]Family? My plants, mostly. I talk to them. Is that strange?"],
		"joke": ["[laughing]What do you call a fish with no eyes? A fsh! ...Sera taught me that one."],
		"thanks": ["[happy]Of course! Any time.", "[happy]Happy to help!"],
		"compliment": ["[laughing]Really? Thank you! Nobody usually notices.", "[happy]Oh! That's so nice. Now I'm going to be smiling all day."],
		"insult": ["[sad]...Oh. Okay. That hurt a bit, actually.", "[worried]Why would you say that?"],
		"farewell": ["[happy]Bye{you}! Come and see the garden later!", "[happy]See you! Oh, wait, never mind, I'll tell you next time."],
		"unknown": ["[surprised]Hmm, I'm not sure I understand. Ask me about plants, the village, the news, anything like that?", "Ooh, I don't follow. Can you put it another way?"],
		"cool": ["[worried]I... don't really want to talk right now.", "Mm. What?"],
	},
	"tomas": {
		"greeting": ["Ah. Hello{you}. Sit, if your legs are tired. Mine always are.", "Good day to you{you}.", "Hm. You again. Good. I like the company."],
		"how_good": ["Well enough. At my age, waking up is a good start.", "[happy]Content. The wood's dry and the tea's hot."],
		"how_ok": ["My knees creak and so does my chair. Otherwise, fine.", "Getting by. As one does."],
		"how_bad": ["[sad]Old bones, old sorrows. Some days they weigh more.", "[worried]Not my best day. Ask me tomorrow."],
		"job": ["I make things that last. Chairs, chests, cradles. A good joint outlives its maker.", "Craftsman. Forty years at the bench. The wood teaches patience if you let it."],
		"likes": ["Strong tea. A quiet morning. Work done properly, not quickly.", "The old songs. The smell of oak shavings. Young folk who listen."],
		"worries": ["[worried]That the young ones will forget how things used to be done. And my eyes. Getting worse.", "[worried]Change comes fast these days. Too fast, sometimes."],
		"village": ["I remember when this was three huts and a fire. Now look at it.", "A village is like a table. Every leg matters, or it wobbles."],
		"family": ["[sad]My wife passed many winters ago. Mara is like a daughter to me now. Don't tell her.", "I had a son once. He went off to the city. Writes sometimes. Not often."],
		"joke": ["Hm. A joke? When I was young, we didn't need jokes. We had weather. ...That was the joke."],
		"thanks": ["No need. It's what neighbours do.", "Mm. You're welcome."],
		"compliment": ["Hm. Kind words. I'll keep them.", "[happy]Well now. Flattery. I haven't had any of that in years."],
		"insult": ["[angry]I've been insulted by better, and by worse. Mind your manners.", "[angry]Hm. Rudeness is a poor tool. It never fits anything."],
		"farewell": ["Go on, then. Mind the step.", "Until next time{you}."],
		"unknown": ["Hm. My ears aren't what they were, and I didn't catch your meaning. Ask about my work, the old days, the village.", "I don't follow. Say it plainly, as you would to an old man."],
		"cool": ["Hm. I've nothing to say to you.", "What is it?"],
	},
	"sera": {
		"greeting": ["[laughing]Well, if it isn't my favourite customer{you}!", "[happy]Hello hello{you}! You look like someone who needs a story.", "[laughing]Ah! Just who I wanted to see!"],
		"how_good": ["[laughing]Fantastic! I sold a cracked teapot as an antique this morning. ...Kidding. Mostly.", "[happy]Brilliant! The sun's out and I've got gossip."],
		"how_ok": ["Oh, you know. Juggling. Metaphorically. Sometimes literally.", "Not bad! Could be better, could be raining."],
		"how_bad": ["[sad]Honestly? A bit homesick for the road today.", "[worried]Bit of a rubbish day, if I'm honest. Don't tell anyone, it's bad for business."],
		"job": ["[laughing]I trade! Buy low, sell with a good story. And I tell stories for free. Well. For cheap.", "Trader and storyteller! I've been to more towns than I can count. I counted. Fifty-two."],
		"likes": ["[laughing]Markets, music, roads I've never walked, and anyone who laughs at my jokes.", "[happy]Shiny things, strange coins, and a good audience."],
		"worries": ["[worried]That I'll get restless and leave again. I like it here. That's what scares me.", "[worried]Trade's been slow. Nobody's coming through on the road lately."],
		"village": ["[happy]For a place this small, it's got a lot of heart. And very little to steal. Joking!", "[laughing]Best village I've lived in. Out of... several. Many. Don't ask."],
		"family": ["[laughing]Family? Every innkeeper from here to the coast. And now this lot.", "My mother ran a stall in the river market. I learned to haggle before I could walk."],
		"joke": ["[laughing]A trader walks into a tavern. Sells it. Walks out. ...It's funnier with ale."],
		"thanks": ["[laughing]You're welcome! I'll put it on your tab.", "[happy]Anytime, friend!"],
		"compliment": ["[laughing]Oh, stop. No, go on.", "[happy]Flatterer! I like you already. Well, more."],
		"insult": ["[angry]Wow. Okay. I've been thrown out of nicer conversations.", "[angry]Charming. Really."],
		"farewell": ["[laughing]Off you go! Don't buy anything I wouldn't!", "[happy]See you{you}! Come back with gossip."],
		"unknown": ["[surprised]You've lost me! Ask me about trade, the road, the news. I know all the news.", "[laughing]I didn't understand a word of that. Try again?"],
		"cool": ["Oh. You.", "[angry]Not now."],
	},
	# General styles for everyone else.
	"warm": {
		"greeting": ["[happy]Hello{you}! Nice to see you.", "[happy]Oh, hello{you}! How lovely."],
		"how_good": ["[happy]I'm well, thank you! Life's good here."],
		"how_ok": ["Alright, thank you. Keeping busy."],
		"how_bad": ["[sad]Not my best day, but thank you for asking."],
		"job": ["[happy]I'm the village {job}. I enjoy it, most days."],
		"likes": ["[happy]Good company, good food, and a job well done."],
		"worries": ["[worried]Mostly that everyone's alright. I worry about people."],
		"village": ["[happy]I like it here. People are kind."],
		"family": ["Family's important to me. I'm glad to be here."],
		"joke": ["[laughing]I'm terrible at jokes. Ask Sera!"],
		"thanks": ["[happy]You're welcome!"],
		"compliment": ["[happy]That's so kind of you!"],
		"insult": ["[sad]That wasn't nice."],
		"farewell": ["[happy]Take care{you}!"],
		"unknown": ["Sorry, I'm not sure what you mean. Ask me about my work, the village or the news?"],
		"cool": ["I'd rather not talk right now."],
	},
	"blunt": {
		"greeting": ["Hello{you}.", "Mm. Hello."],
		"how_good": ["Fine. Good, even."],
		"how_ok": ["Fine. Why?"],
		"how_bad": ["[worried]Bad day. Leave it at that."],
		"job": ["I'm the {job}. Somebody has to be."],
		"likes": ["Quiet. Work done right. Not being asked questions."],
		"worries": ["Plenty. Not your concern."],
		"village": ["It's alright. Could be worse."],
		"family": ["That's my business."],
		"joke": ["No."],
		"thanks": ["Mm."],
		"compliment": ["Hm. Thanks."],
		"insult": ["[angry]Get lost."],
		"farewell": ["Bye."],
		"unknown": ["Don't know what you mean. Say it plainly."],
		"cool": ["What."],
	},
	"shy": {
		"greeting": ["[happy]Oh! H-hello{you}.", "[happy]Hi..."],
		"how_good": ["[happy]Good, I think. Thank you for asking."],
		"how_ok": ["Okay. Just... okay."],
		"how_bad": ["[sad]Not so good. But it's fine."],
		"job": ["I'm... the {job}. I'm still learning."],
		"likes": ["[happy]Quiet places. Reading. Small things."],
		"worries": ["[worried]Lots of things. Mostly people being cross with me."],
		"village": ["[happy]It's nice. Quiet enough."],
		"family": ["I don't talk about them much."],
		"joke": ["[surprised]Oh, I don't know any. Sorry."],
		"thanks": ["[happy]Oh! You're welcome."],
		"compliment": ["[surprised]R-really? Thank you..."],
		"insult": ["[sad]...Oh."],
		"farewell": ["[happy]Bye..."],
		"unknown": ["[worried]Sorry, I don't understand. Maybe ask about my work, or the village?"],
		"cool": ["...", "[worried]Please leave me be."],
	},
	"lively": {
		"greeting": ["[laughing]Hey{you}! Great to see you!", "[happy]Hello hello{you}!"],
		"how_good": ["[laughing]Great! Never better!"],
		"how_ok": ["Oh, not bad! Busy busy."],
		"how_bad": ["[sad]Bit of a rough one, honestly."],
		"job": ["[laughing]I'm the {job}! Best job in the village, if you ask me."],
		"likes": ["[laughing]Festivals! Dancing! Talking! You might have noticed."],
		"worries": ["[worried]That things get boring. Never let things get boring."],
		"village": ["[happy]Love it! Always something going on."],
		"family": ["[laughing]Big family, loud family. I miss the noise."],
		"joke": ["[laughing]Why did the scarecrow win an award? He was outstanding in his field!"],
		"thanks": ["[laughing]Anytime!"],
		"compliment": ["[laughing]Aw, you're the best!"],
		"insult": ["[angry]Hey! Rude!"],
		"farewell": ["[laughing]See you soon{you}!"],
		"unknown": ["[laughing]Ha, I didn't get that! Ask me something else? Work, news, the village?"],
		"cool": ["Hmph."],
	},
	"child": {
		"greeting": ["[laughing]Hiii{you}!", "[happy]Hello! Do you want to play?"],
		"how_good": ["[laughing]Good! I found a beetle!"],
		"how_ok": ["Okay. I'm bored."],
		"how_bad": ["[sad]Not good. Nobody wants to play."],
		"job": ["[laughing]I don't have a job, I'm a kid! I help sometimes."],
		"likes": ["[laughing]Running! Frogs! Honey cakes!"],
		"worries": ["[worried]The big wolves. Are they real?"],
		"village": ["[happy]It's the best! There's a pond with frogs!"],
		"family": ["[happy]My family's here. They're nice. Mostly."],
		"joke": ["[laughing]Knock knock! ...I forgot the rest."],
		"thanks": ["[happy]You're welcome!"],
		"compliment": ["[laughing]Hehe, thanks!"],
		"insult": ["[sad]That's mean! I'm telling!"],
		"farewell": ["[laughing]Byeee!"],
		"unknown": ["[surprised]Huh? I don't get it."],
		"cool": ["[sad]Go away."],
	},
}

## What founders like, for "I like ..." (shared interests warm them).
const LIKES := {
	"mara": ["build", "wood", "tool", "house", "work", "hammer"],
	"elias": ["farm", "bread", "food", "rain", "grow", "garden", "cook"],
	"nia": ["plant", "flower", "herb", "book", "read", "garden", "science", "nature"],
	"tomas": ["wood", "tea", "craft", "quiet", "story", "stories", "music", "old"],
	"sera": ["travel", "story", "stories", "music", "market", "trade", "dance", "adventure"],
}


# --- Cleaning and understanding -----------------------------------------------------

## The message as shown: trimmed, one line, no control characters, at most
## MAX_LENGTH characters.
static func clean(text: String) -> String:
	var out := ""
	for c in text:
		var code := c.unicode_at(0)
		out += " " if code < 32 or code == 127 else c
	out = " ".join(out.split(" ", false)).strip_edges()
	return out.substr(0, MAX_LENGTH)


## Lower case, punctuation removed (apostrophes become spaces: "what's" -> "what s").
static func normalize(text: String) -> String:
	var out := ""
	for c in text.to_lower():
		out += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else " "
	return " ".join(out.split(" ", false))


## What the message seems to be: { intent, text, value (a name, a liked thing,
## a place), about (a villager mentioned) }. intent "unknown" when nothing fits.
static func understand(text: String, speaker = null) -> Dictionary:
	var n := normalize(text)
	var result := {"intent": "unknown", "text": n, "value": "", "about": ""}
	if n == "":
		result["intent"] = "empty"
		return result
	# Someone in the village mentioned by name ("what do you think of Tomas?").
	for v in GameManager.villagers:
		if is_instance_valid(v) and v != speaker and v.person and v.person.is_resident():
			if RegEx.create_from_string("\\b" + normalize(v.data.display_name) + "\\b").search(n):
				result["about"] = String(v.data.id)
				break
	for rule in INTENTS:
		if RegEx.create_from_string(rule[1]).search(n):
			result["intent"] = rule[0]
			break
	match String(result["intent"]):
		"player_name":
			result["value"] = _after(n, ["my name is", "my name s", "call me", "i m called", "they call me", "i go by"], 1)
		"player_like":
			result["value"] = _after(n, ["i really like", "i also like", "i do like", "i like", "i really love", "i love", "i really enjoy", "i enjoy", "i adore"], 4)
		"player_from":
			result["value"] = _after(n, ["i m from", "i am from", "i come from", "i grew up in"], 3)
		"player_feeling":
			var m := RegEx.create_from_string("(sad|tired|happy|lonely|bored|scared|worried|great|good|fine|ok|okay|sick|ill|hungry|angry|upset|excited|lost|exhausted)").search(n)
			result["value"] = m.get_string(1) if m else ""
	if result["about"] != "" and String(result["intent"]) in ["unknown", "ask_likes", "ask_village", "compliment", "insult"]:
		# "Do you like Tomas?" / "Tomas is nice" / questions about someone.
		if String(result["intent"]) in ["unknown", "ask_likes", "ask_village"]:
			result["intent"] = "ask_person"
	if String(result["intent"]) == "unknown" and (text.strip_edges().ends_with("?") or RegEx.create_from_string("^(what|why|how|who|where|when|which|do|does|did|can|could|would|will|is|are)\\b").search(n)):
		result["intent"] = "unknown_question"
	return result


## Up to `words` words after the first of `phrases` found in `n`.
static func _after(n: String, phrases: Array, words: int) -> String:
	for p in phrases:
		var at := n.find(p)
		if at >= 0:
			var rest := n.substr(at + p.length()).strip_edges().split(" ", false)
			return " ".join(rest.slice(0, words))
	return ""


# --- Who's talking --------------------------------------------------------------------

static func style_of(villager) -> String:
	var id := String(villager.data.id)
	if VOICES.has(id):
		return id
	var person: Person = villager.person
	if person and person.age() < 13:
		return "child"
	var p: Dictionary = person.personality if person and not person.personality.is_empty() else villager.data.personality
	if float(p.get("agreeableness", 0.5)) < 0.4:
		return "blunt"
	if float(p.get("extraversion", 0.5)) > 0.65:
		return "lively"
	if float(p.get("extraversion", 0.5)) < 0.35:
		return "shy"
	return "warm"


## A line of `kind` in this villager's voice, not the one they said last.
static func voice_line(villager, kind: String) -> String:
	var voice: Dictionary = VOICES[style_of(villager)]
	var lines: Array = voice.get(kind, VOICES["warm"].get(kind, ["..."]))
	# Someone who knows your name uses it when they greet you.
	if kind in ["greeting", "farewell"] and known_name(villager) != "":
		var named := lines.filter(func(l): return String(l).contains("{you}"))
		if not named.is_empty():
			lines = named
	var line := LineBank._fresh(villager, lines)
	return fill(villager, line)


static func fill(villager, line: String) -> String:
	var name_ := known_name(villager)
	var job := Professions.label(villager.person.profession).to_lower() if villager.person else String(villager.data.role).to_lower()
	return line.replace("{you}", (", " + name_) if name_ != "" else "").replace("{name}", villager.data.display_name).replace("{job}", job)


# --- Memory: only what was really said ---------------------------------------------------

## A fact the player told this villager ("" if never told).
static func fact(villager, key: String) -> String:
	var mind: VillagerMind = villager.mind
	for i in range(mind.memory.entries.size() - 1, -1, -1):
		var e: Dictionary = mind.memory.entries[i]
		if e["type"] == "fact" and e["subject"] == GameManager.PLAYER_ID and String(e["detail"]).begins_with(key + "="):
			return String(e["detail"]).substr(key.length() + 1)
	return ""


static func facts(villager, key: String) -> Array:
	var out: Array = []
	for e in villager.mind.memory.find("fact", GameManager.PLAYER_ID):
		if String(e["detail"]).begins_with(key + "="):
			var v := String(e["detail"]).substr(key.length() + 1)
			out.erase(v)
			out.append(v)
	return out


static func remember_fact(villager, key: String, value: String) -> void:
	villager.mind.memory.add("fact", GameManager.PLAYER_ID, WorldClock.day, WorldClock.time_of_day, "%s=%s" % [key, value])


static func known_name(villager) -> String:
	return fact(villager, "name")


## How many times today the player did `what` (typed compliments, thanks...).
static func times_today(villager, what: String) -> int:
	var n := 0
	for e in villager.mind.memory.find("typed", GameManager.PLAYER_ID):
		if String(e["detail"]) == what and int(e["day"]) == WorldClock.day:
			n += 1
	return n


# --- Answering -------------------------------------------------------------------------------

## Sentences answered from one message ("Hi! I'm Sam. I love flowers.").
const MAX_SENTENCES := 3


## The villager's answer to `text`: { lines, intent, choices (or null to keep
## the menu), end (say goodbye) }. Applies what the words change (feelings,
## memories). Up to MAX_SENTENCES sentences are answered, in order; parts it
## can't interpret are left out if others were understood (and answered
## honestly if nothing was). `conversation` keeps a yes/no question waiting.
static func respond(villager, text: String, conversation = null) -> Dictionary:
	var sentences: Array = []
	for part in RegEx.create_from_string("[^.!?]+[.!?]*").search_all(text):
		var s := String(part.get_string()).strip_edges()
		if normalize(s) != "":
			sentences.append(s)
	if sentences.size() <= 1:
		return _respond_one(villager, text, conversation)
	var known: Array = sentences.filter(func(s): return not String(understand(s, villager)["intent"]) in ["unknown", "unknown_question", "empty"])
	if known.is_empty():
		return _respond_one(villager, text, conversation)
	var out := {"lines": [], "intent": "", "choices": null, "end": false}
	var greeted := false
	for s in known.slice(0, MAX_SENTENCES):
		var intent := String(understand(s, villager)["intent"])
		# One hello is enough when there's more to say.
		if intent == "greeting" and known.size() > 1:
			if greeted:
				continue
			greeted = true
		var one := _respond_one(villager, s, conversation)
		out["lines"].append_array(one["lines"])
		out["intent"] = one["intent"] if out["intent"] == "" or out["intent"] == "greeting" else out["intent"]
		if one["choices"] != null:
			out["choices"] = one["choices"]
		if bool(one["end"]):
			out["end"] = true
			break
	return out


static func _respond_one(villager, text: String, conversation = null) -> Dictionary:
	var u := understand(text, villager)
	var intent := String(u["intent"])
	var mind: VillagerMind = villager.mind
	var me := GameManager.PLAYER_ID
	var affection := mind.get_affection(me)
	var hostile := mind.is_hostile(me)
	var out := {"lines": [], "intent": intent, "choices": null, "end": false}
	var lines: Array = out["lines"]
	mind.memory.add("typed", me, WorldClock.day, WorldClock.time_of_day, intent)
	mind.record_interaction(me, "talk", WorldClock.day, WorldClock.time_of_day)

	# Someone who dislikes you only listens to an apology.
	if hostile and intent not in ["apology", "farewell"]:
		lines.append(voice_line(villager, "cool"))
		return out

	match intent:
		"greeting":
			lines.append(voice_line(villager, "greeting"))
			if WorldClock.time_of_day >= 22.0 or WorldClock.time_of_day < 5.0:
				lines.append("It's late, though. Shouldn't you be asleep?")
		"farewell":
			lines.append(voice_line(villager, "farewell" if not hostile else "cool"))
			out["end"] = true
		"how_are_you":
			lines.append(_how_are_you(villager))
		"ask_name":
			lines.append(_name_line(villager))
		"ask_job":
			lines.append(voice_line(villager, "job"))
		"ask_activity":
			var doing := String(villager.get_activity_description()).to_lower()
			lines.append(("Right now? %s." % doing.rstrip(".")) if doing != "" else "Nothing much. Just thinking.")
		"ask_family":
			lines.append(_family_line(villager))
		"ask_news":
			var news := Chatter.lines_for(villager, 1) if Chatter.has_news(villager) else []
			if news.is_empty():
				lines.append("Nothing new that I've heard. Quiet few days.")
			else:
				lines.append_array(news)
		"ask_worries":
			lines.append(_worry_line(villager))
		"ask_likes":
			lines.append(voice_line(villager, "likes"))
		"ask_village":
			lines.append(voice_line(villager, "village"))
		"ask_person":
			lines.append(_person_line(villager, String(u["about"])))
		"weather":
			lines.append(_weather_line())
		"ask_time":
			lines.append("It's about %s. %s" % [_clock(), "Getting late." if WorldClock.time_of_day >= 20.0 else ""])
		"joke":
			lines.append(voice_line(villager, "joke"))
		"thanks":
			lines.append(voice_line(villager, "thanks"))
			if times_today(villager, "thanks") <= 1:
				mind.adjust_opinion(me, 1.0, 1.0)
		"compliment":
			var n := times_today(villager, "compliment")
			if n <= 1:
				lines.append(voice_line(villager, "compliment"))
				mind.adjust_opinion(me, 3.0, 1.0)
			elif n <= 3:
				lines.append("[laughing]Alright, alright, I get it. You're very sweet." if affection >= 0 else "Hm. You've said that already.")
				mind.adjust_opinion(me, 1.0, 0.0)
			else:
				lines.append("[worried]You keep saying that. Is everything alright?")
				mind.adjust_opinion(me, -1.0, -1.0)
		"insult":
			lines.append(voice_line(villager, "insult"))
			mind.adjust_opinion(me, -8.0, -5.0)
			mind.memory.add("deed", me, WorldClock.day, WorldClock.time_of_day, DialogueService.pack_deed("said something hurtful to them", -8.0))
			if mind.is_hostile(me):
				lines.append("[angry]We're done talking.")
				out["end"] = true
		"apology":
			if affection < 0.0 and times_today(villager, "apology") <= 1:
				mind.adjust_opinion(me, 6.0, 3.0)
				mind.memory.add("mentioned", me, WorldClock.day, WorldClock.time_of_day, "apology")
				lines.append("[sad]...Alright. Thank you for saying it. Let's start over." if not mind.is_hostile(me) else "[sad]I hear you. It'll take more than words, but... I hear you.")
			elif affection < 0.0:
				lines.append("You've said sorry already. Show me instead.")
			else:
				lines.append("[surprised]Sorry? For what? You haven't done anything wrong.")
		"player_name":
			lines.append(_learn_name(villager, String(u["value"])))
		"ask_player_name":
			var known := known_name(villager)
			lines.append(("[happy]You're %s. I remember." % known) if known != "" else "You haven't told me your name, actually. What should I call you?")
		"player_like":
			lines.append(_learn_like(villager, String(u["value"])))
		"player_from":
			var place := String(u["value"]).capitalize()
			if place.length() >= 2:
				remember_fact(villager, "from", place)
				lines.append("[happy]%s? I've heard of it. Or I'll pretend I have. I'll remember that." % place if style_of(villager) == "sera" else "[happy]%s, is it? I'll remember that." % place)
			else:
				lines.append("From where? You didn't say.")
		"ask_recall":
			lines.append_array(_recall_lines(villager))
		"player_feeling":
			lines.append(_feeling_reply(villager, String(u["value"])))
		"offer_help":
			lines.append_array(_offer_help_lines(villager))
		"ask_help":
			lines.append("What do you need?" if affection > -15.0 else "...Depends what it is.")
			out["choices"] = DialogueService.task_menu(villager)
		"yes", "no":
			var pending := String(conversation.pending_question) if conversation and conversation.get("pending_question") != null else ""
			if pending == "":
				lines.append("Yes or no to what? I didn't ask anything." if intent == "yes" else "No? I didn't ask anything.")
			else:
				lines.append("[happy]Good." if intent == "yes" else "Fair enough.")
				conversation.pending_question = ""
		"unknown_question", "unknown":
			lines.append(voice_line(villager, "unknown"))
	if lines.is_empty():
		lines.append(voice_line(villager, "unknown"))
	return out


## When you say how you feel.
static func _feeling_reply(villager, feeling: String) -> String:
	var gentle := style_of(villager) in ["elias", "nia", "warm", "shy"]
	match feeling:
		"sad", "upset", "lonely", "lost":
			return "[sad]I'm sorry to hear that. You're not alone here, you know." if gentle else "[worried]Hey. Come sit by the fire tonight. Company helps."
		"tired", "exhausted", "sick", "ill":
			return "[worried]Then rest! Your bed won't sleep in itself." if style_of(villager) != "tomas" else "[worried]Rest, then. Work keeps; health doesn't."
		"hungry":
			return "[happy]Elias always has bread. Or try the stew at the meeting circle in the evening."
		"scared", "worried":
			return "[worried]What's scaring you? The woods? Stay near the village after dark."
		"angry":
			return "[worried]Breathe. Whatever it is, shouting won't fix it. Want to talk about it?"
		"bored":
			return "[laughing]Bored? There's always wood to chop. Or come and help me." if style_of(villager) == "mara" else "[happy]Go and explore! There's a windmill, a lake, ruins... plenty to see."
	return "[happy]Glad to hear it! That makes my day better too."


static func _clock() -> String:
	var h := int(WorldClock.time_of_day)
	var m := int((WorldClock.time_of_day - h) * 60.0)
	return "%d:%02d" % [h, m]


static func _how_are_you(villager) -> String:
	var person: Person = villager.person
	var lost := Population.recently_lost(person) if person else null
	if lost:
		return "[sad]Not well. I keep thinking about %s." % lost.first_name
	if person and (person.home == Population.CAMP_ID or person.home == ""):
		return "[worried]Honestly? Sleeping in a tent is wearing me down. I need a proper roof."
	var happiness := person.happiness if person else 60.0
	var kind := "how_good" if happiness >= 65.0 else ("how_ok" if happiness >= 40.0 else "how_bad")
	var line := voice_line(villager, kind)
	# A house the player gave them: they say so.
	if person and Population.is_given_house(Population.house_record(person.home)) and String(Population.home_owners.get(person.home, "")) == person.id:
		line += " And I still can't believe you gave me a house."
	return line


static func _name_line(villager) -> String:
	var data: VillagerData = villager.data
	var role := String(data.role) if data.role != "" else (Professions.label(villager.person.profession) if villager.person else "")
	match style_of(villager):
		"mara":
			return "Mara. I build things. You've probably walked through one of my doors."
		"elias":
			return "[happy]I'm Elias. I keep the fields, and the fields keep us."
		"nia":
			return "[happy]Nia! Herbalist, gardener, asker of too many questions."
		"tomas":
			return "Tomas. The old craftsman, they call me. The 'old' is accurate."
		"sera":
			return "[laughing]Sera, trader extraordinaire! Well. Trader ordinaire. I'm working on it."
	return "I'm %s%s." % [data.display_name, (", the " + role.to_lower()) if role != "" else ""]


static func _family_line(villager) -> String:
	var person: Person = villager.person
	if person == null:
		return voice_line(villager, "family")
	var bits: Array = []
	var partner := Population.get_person(person.partner)
	if partner:
		bits.append("%s%s" % ["my wife " if partner.sex == "female" else "my husband ", partner.first_name] if person.married else "%s, my partner" % partner.first_name)
	var kids: Array = []
	for id in person.children:
		var child := Population.get_person(String(id))
		if child and child.status != Person.STATUS_LEFT:
			kids.append(child.first_name)
	if not kids.is_empty():
		bits.append("%s %s" % ["my little one" if kids.size() == 1 else "my children", " and ".join(kids)])
	if bits.is_empty():
		return voice_line(villager, "family")
	return "[happy]There's %s. They're my whole world." % " and ".join(bits)


static func _worry_line(villager) -> String:
	var person: Person = villager.person
	if person:
		if person.leaving:
			return "[sad]I've been thinking about leaving. I'm not happy here."
		if person.home == Population.CAMP_ID:
			return "[worried]Where I'll sleep when the cold comes. A tent won't do for winter."
		var lost := Population.recently_lost(person)
		if lost:
			return "[sad]%s. I miss them." % lost.first_name
	if VillageDefence.instance and VillageDefence.instance.is_raid():
		return "[worried]Monsters at the gates! What do you think?!"
	if RequestBoard.instance:
		var ask := RequestBoard.instance.reminder_for(villager)
		if ask != "":
			return ask
	return voice_line(villager, "worries")


static func _person_line(villager, other_id: String) -> String:
	var other = GameManager.get_villager(StringName(other_id))
	if other == null:
		return "Who? I don't know who you mean."
	var name_: String = other.data.display_name
	var person: Person = villager.person
	if person and person.partner == other_id:
		return "[happy]%s? I love them. Don't tell them I said it so plainly." % name_
	if person and (person.children.has(other_id) or person.parents.has(other_id)):
		return "[happy]%s is family. Of course I care about them." % name_
	var feeling: float = villager.mind.get_affection(other_id)
	if feeling >= 40.0:
		return "[happy]%s? One of my closest friends." % name_
	if feeling >= 12.0:
		return "[happy]I like %s. We get along well." % name_
	if feeling <= -15.0:
		return "[angry]%s and I don't see eye to eye. Leave it there." % name_
	return "%s? I don't know them that well yet, honestly." % name_


static func _weather_line() -> String:
	if Weather.instance and Weather.instance.is_raining():
		return "[worried]Raining again. Good for the crops, bad for my boots."
	var h := WorldClock.time_of_day
	if h >= 20.0 or h < 5.0:
		return "Clear night. You can see every star out here."
	return "[happy]Nice enough today. Make the most of it."


static func _learn_name(villager, raw: String) -> String:
	var name_ := raw.strip_edges().capitalize()
	if name_.length() < 2 or name_.length() > 20:
		return "Sorry, I didn't catch your name. Say 'my name is...' and then your name?"
	var old := known_name(villager)
	remember_fact(villager, "name", name_)
	if old == name_:
		return "[happy]I know, %s. I remember." % name_
	if old != "":
		return "[surprised]%s? I thought it was %s. Alright, %s it is." % [name_, old, name_]
	return "[happy]Nice to meet you properly, %s. I'll remember that." % name_


static func _learn_like(villager, raw: String) -> String:
	var thing := raw.strip_edges()
	if thing.length() < 2 or thing in ["it", "that", "this", "them"]:
		return "You like what? You'll have to tell me."
	var likes := facts(villager, "likes")
	if not likes.has(thing):
		remember_fact(villager, "likes", thing)
	var shared := false
	for word in LIKES.get(style_of(villager), []):
		if thing.contains(word):
			shared = true
	if shared:
		if times_today(villager, "player_like") <= 1:
			villager.mind.adjust_opinion(GameManager.PLAYER_ID, 2.0, 0.0)
		return "[happy]You like %s? Me too! We'll get on just fine." % thing
	return "[happy]%s, hm? I'll remember that." % thing.capitalize()


## Only what they really remember: facts you told them, things you did,
## what they heard about you, and how often you've talked.
static func _recall_lines(villager) -> Array:
	var mind: VillagerMind = villager.mind
	var me := GameManager.PLAYER_ID
	var bits: Array = []
	var name_ := known_name(villager)
	if name_ != "":
		bits.append("your name's %s" % name_)
	var from := fact(villager, "from")
	if from != "":
		bits.append("you're from %s" % from)
	var likes := facts(villager, "likes")
	if not likes.is_empty():
		bits.append("you like %s" % " and ".join(likes.slice(maxi(likes.size() - 2, 0))))
	var deeds := mind.memory.find("deed", me)
	if not deeds.is_empty():
		bits.append("you %s" % DialogueService.unpack_deed(String(deeds[-1]["detail"]))["text"])
	var talks := mind.memory.count("conversation", me)
	var lines: Array = []
	if bits.is_empty():
		if talks <= 1:
			lines.append("We've only just met. I don't know much about you yet. Tell me something?")
		else:
			lines.append("We've talked %d times, but you haven't told me much about yourself." % talks)
	else:
		lines.append("[happy]I remember %s." % _join(bits))
	return lines


static func _join(items: Array) -> String:
	if items.size() <= 1:
		return "".join(items)
	return ", ".join(items.slice(0, items.size() - 1)) + " and " + String(items[-1])


static func _offer_help_lines(villager) -> Array:
	var lines: Array = []
	if RequestBoard.instance:
		var ask := RequestBoard.instance.reminder_for(villager)
		if ask != "":
			lines.append("[happy]Actually, yes. " + ask.trim_prefix("[happy]").trim_prefix("[worried]"))
			return lines
	if times_today(villager, "offer_help") <= 1:
		villager.mind.adjust_opinion(GameManager.PLAYER_ID, 2.0, 2.0)
	lines.append("[happy]That's kind of you. Nothing right now, but I'll remember you offered.")
	return lines
