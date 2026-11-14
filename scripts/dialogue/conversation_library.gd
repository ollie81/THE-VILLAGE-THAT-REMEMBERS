class_name ConversationLibrary
extends RefCounted
## Conversation topics, one list per villager, offered in order across visits.
##
## A topic is { id, lines, choices }. Each choice:
##   text       what the player says
##   reply      the villager's answer (lines may start with an [expression])
##   affection  change to how warmly they feel about the player
##   trust      change to how much they rely on the player
##   remember   what they remember the player did, phrased to follow "you"
##              ("offered to help build the new house"). Empty = not memorable.
## Remembered deeds come back in later conversations and spread as gossip.

const TOPICS := {
	&"mara": [
		{
			"id": "mara_new_house",
			"lines": ["[happy]The new house on the west edge is nearly framed. Nobody's claimed it yet."],
			"choices": [
				{"text": "I could help you haul timber.", "affection": 12, "trust": 8, "remember": "offered to help build the new house",
					"reply": ["[surprised]You'd do that?", "[happy]Then I'll hold you to it. Thank you."]},
				{"text": "Who's it for?", "affection": 5, "trust": 3, "remember": "",
					"reply": ["[happy]Whoever the village needs next. A family, a traveller...", "[laughing]Maybe even you, if you stick around."]},
				{"text": "Looks a bit crooked to me.", "affection": -12, "trust": -4, "remember": "called her new house crooked",
					"reply": ["[angry]Crooked? I've been raising walls since before you could walk.", "[worried]...Is it really crooked?"]},
			],
		},
		{
			"id": "mara_wolves",
			"lines": ["[worried]Wolves were howling past the river last night. I don't like it."],
			"choices": [
				{"text": "I'll keep watch with you tonight.", "affection": 10, "trust": 12, "remember": "volunteered to keep watch for wolves",
					"reply": ["[happy]Good. Two pairs of eyes are better than one."]},
				{"text": "What would you do if they came?", "affection": 4, "trust": 3, "remember": "",
					"reply": ["Bang a pot, build the fire high, and stand between them and the little ones.", "[happy]Same as always."]},
				{"text": "You worry too much.", "affection": -6, "trust": -8, "remember": "told her she worries too much about the wolves",
					"reply": ["[angry]Someone has to."]},
			],
		},
		{
			"id": "mara_tomas",
			"lines": ["[laughing]Tomas says my hammering sounds like an argument. He's not wrong."],
			"choices": [
				{"text": "You two are like family.", "affection": 8, "trust": 4, "remember": "said she and Tomas are like family",
					"reply": ["[happy]He taught me to hold a chisel.", "[laughing]Don't tell him I said that."]},
				{"text": "Maybe hammer a bit quieter?", "affection": -2, "trust": 0, "remember": "",
					"reply": ["[laughing]Never."]},
				{"text": "Tomas is just a grumpy old man.", "affection": -8, "trust": -8, "remember": "called Tomas a grumpy old man behind his back",
					"reply": ["[angry]Careful. He's earned every one of his grumbles."]},
			],
		},
	],
	&"elias": [
		{
			"id": "elias_crows",
			"lines": ["[worried]Crows got into the wheat again. Half a row, gone."],
			"choices": [
				{"text": "Let me help you fix the scarecrow.", "affection": 12, "trust": 8, "remember": "helped mend the scarecrow",
					"reply": ["[happy]That'd be a real kindness. Grab the straw by the fence."]},
				{"text": "Well, crows have to eat too.", "affection": 3, "trust": 0, "remember": "",
					"reply": ["[laughing]Ha! Tell that to my bread."]},
				{"text": "Sounds like poor farming to me.", "affection": -12, "trust": -6, "remember": "called his farming poor",
					"reply": ["[sad]...Maybe. I do my best with what the land gives."]},
			],
		},
		{
			"id": "elias_bread",
			"lines": ["[happy]I baked too much bread again. Would you take a loaf?"],
			"choices": [
				{"text": "Thank you, I'd love some.", "affection": 8, "trust": 4, "remember": "gratefully took a loaf of his bread",
					"reply": ["[happy]Good. Eat it while it's warm."]},
				{"text": "Give it to someone who needs it more.", "affection": 10, "trust": 8, "remember": "asked him to give his bread to someone in need",
					"reply": ["[surprised]You're a good soul.", "[happy]I'll take it to Tomas, then."]},
				{"text": "I don't need your charity.", "affection": -10, "trust": -4, "remember": "refused his bread rudely",
					"reply": ["[sad]It wasn't charity. It was just bread."]},
			],
		},
		{
			"id": "elias_father",
			"lines": ["[sad]My father worked this land. Some mornings I still hear him calling the cows."],
			"choices": [
				{"text": "Tell me about him.", "affection": 10, "trust": 8, "remember": "asked about his late father",
					"reply": ["[happy]He sang off-key and never once lost his temper.", "[sad]I miss him every harvest."]},
				{"text": "He'd be proud of you.", "affection": 12, "trust": 6, "remember": "said his father would be proud of him",
					"reply": ["[happy]...I'd like to think so."]},
				{"text": "Everybody loses someone.", "affection": -6, "trust": -2, "remember": "brushed off his grief",
					"reply": ["[sad]Aye. Doesn't make it any lighter."]},
			],
		},
	],
	&"nia": [
		{
			"id": "nia_mushroom",
			"lines": ["[surprised]I found a mushroom that glows faintly at night! I have to know why."],
			"choices": [
				{"text": "Show me where you found it!", "affection": 10, "trust": 6, "remember": "wanted to see her glowing mushroom",
					"reply": ["[laughing]Meet me past the bridge after sunset. And don't step on anything."]},
				{"text": "Is it safe to eat?", "affection": 3, "trust": 0, "remember": "",
					"reply": ["[laughing]Absolutely not. Probably. Let's not find out."]},
				{"text": "Sounds like a waste of time.", "affection": -12, "trust": -4, "remember": "called her plant studies a waste of time",
					"reply": ["[sad]Oh. Right. Sorry I bothered you."]},
			],
		},
		{
			"id": "nia_remedy",
			"lines": ["[worried]Tomas's knees ache in the cold. I'm trying a willow bark tea for him."],
			"choices": [
				{"text": "I can gather willow bark for you.", "affection": 12, "trust": 10, "remember": "offered to gather willow bark for Tomas's medicine",
					"reply": ["[happy]Really? The willows across the river have the best bark. Thank you!"]},
				{"text": "You're good to look after him.", "affection": 8, "trust": 4, "remember": "praised how she cares for Tomas",
					"reply": ["[happy]He looked after all of us first."]},
				{"text": "Old people complain a lot.", "affection": -10, "trust": -8, "remember": "mocked Tomas's aching knees",
					"reply": ["[angry]That's unkind. Pain is pain, at any age."]},
			],
		},
		{
			"id": "nia_sketches",
			"lines": ["[happy]Do you want to see my sketches? I draw every plant I find."],
			"choices": [
				{"text": "I'd love to.", "affection": 10, "trust": 4, "remember": "admired her plant sketches",
					"reply": ["[happy]This one's lavender, and this...", "[laughing]...is my best guess at a nettle."]},
				{"text": "Could you draw me sometime?", "affection": 6, "trust": 2, "remember": "",
					"reply": ["[laughing]I only draw things that hold still!"]},
				{"text": "Maybe later.", "affection": -2, "trust": 0, "remember": "",
					"reply": ["[sad]Oh. Sure. Later."]},
			],
		},
	],
	&"tomas": [
		{
			"id": "tomas_stone",
			"lines": ["[sad]Every mark on the story stone is something we chose to remember. Some of them are sad."],
			"choices": [
				{"text": "What's the oldest mark?", "affection": 10, "trust": 6, "remember": "asked about the oldest mark on the story stone",
					"reply": ["[sad]The flood year. We lost the old bridge, and my brother with it.", "[happy]Then we built a better bridge."]},
				{"text": "Maybe one day I'll earn a mark.", "affection": 8, "trust": 4, "remember": "hoped to earn a mark on the story stone",
					"reply": ["[happy]Maybe you will. It usually takes a lifetime."]},
				{"text": "It's just a rock.", "affection": -12, "trust": -8, "remember": "called the story stone just a rock",
					"reply": ["[angry]It's the memory of everyone who came before you. Mind your tongue."]},
			],
		},
		{
			"id": "tomas_apprentice",
			"lines": ["[worried]My hands shake more each winter. Someone should learn the craft before I'm gone."],
			"choices": [
				{"text": "Would you teach me?", "affection": 14, "trust": 10, "remember": "asked to learn his craft",
					"reply": ["[surprised]You'd want to learn?", "[happy]Come to the workshop at dawn. Bring patience."]},
				{"text": "Mara would make a fine apprentice.", "affection": 8, "trust": 6, "remember": "suggested Mara should learn his craft",
					"reply": ["[happy]She would. Stubborn as iron, that one."]},
				{"text": "You've got years left. Don't be gloomy.", "affection": 2, "trust": 0, "remember": "",
					"reply": ["[laughing]Ha. Maybe. But wood doesn't wait."]},
			],
		},
		{
			"id": "tomas_old_ways",
			"lines": ["Young folk want everything faster. A good chair takes a week. A good name takes a lifetime."],
			"choices": [
				{"text": "Some things are worth the wait.", "affection": 10, "trust": 6, "remember": "agreed that good things take time",
					"reply": ["[happy]Now you're talking sense."]},
				{"text": "Faster isn't always worse.", "affection": 2, "trust": 6, "remember": "politely disagreed with him about the old ways",
					"reply": ["[surprised]Hm. Perhaps.", "[laughing]You argue like Sera."]},
				{"text": "Nobody needs handmade chairs anymore.", "affection": -10, "trust": -6, "remember": "said nobody needs handmade chairs",
					"reply": ["[angry]Then sit on the floor."]},
			],
		},
	],
	&"sera": [
		{
			"id": "sera_badger",
			"lines": ["[laughing]Did I ever tell you about the badger I outran? It was the size of a cart!"],
			"choices": [
				{"text": "Tell me the whole story!", "affection": 10, "trust": 4, "remember": "begged to hear her badger story",
					"reply": ["[happy]Sit down, this'll take a while..."]},
				{"text": "The size of a cart? Really?", "affection": 6, "trust": 2, "remember": "",
					"reply": ["[laughing]Well. A small cart.", "[laughing]A wheelbarrow, maybe."]},
				{"text": "You're making that up.", "affection": -6, "trust": -4, "remember": "called her badger story a lie",
					"reply": ["[angry]Every story's true if you tell it right!"]},
			],
		},
		{
			"id": "sera_trade",
			"lines": ["[happy]If we could trade with the towns past the hills, we'd never go hungry in winter."],
			"choices": [
				{"text": "I'll come with you when you go.", "affection": 12, "trust": 8, "remember": "promised to join her trading journey",
					"reply": ["[surprised]You mean it?", "[happy]Then pack light and bring a good hat."]},
				{"text": "What would we trade?", "affection": 6, "trust": 4, "remember": "",
					"reply": ["[happy]Elias's grain, Tomas's tools, Nia's remedies. We're richer than we think."]},
				{"text": "Too risky. Stay here.", "affection": -4, "trust": 0, "remember": "told her the trade route was too risky",
					"reply": ["[sad]Everyone says that."]},
			],
		},
		{
			"id": "sera_seriously",
			"lines": ["[worried]Can I tell you something? I'm afraid nobody here takes me seriously."],
			"choices": [
				{"text": "I take you seriously.", "affection": 12, "trust": 12, "remember": "told her she is taken seriously",
					"reply": ["[happy]...Thank you. That means more than you know."]},
				{"text": "Your stories make everyone happy.", "affection": 8, "trust": 4, "remember": "said her stories make everyone happy",
					"reply": ["[happy]Then maybe that's enough."]},
				{"text": "Maybe tell fewer tall tales.", "affection": -6, "trust": 2, "remember": "told her to tell fewer tall tales",
					"reply": ["[sad]...Maybe you're right."]},
			],
		},
	],
}

## Offered instead of a topic when a villager has come to dislike the player.
const APOLOGY := {
	"id": "apology",
	"lines": ["[angry]I've got nothing to say to you."],
	"choices": [
		{"text": "I'm sorry for how I treated you.", "affection": 18, "trust": 6, "remember": "apologised",
			"reply": ["[worried]...", "[sad]Fine. Let's start over. Don't make me regret it."]},
		{"text": "Suit yourself.", "affection": -4, "trust": -2, "remember": "",
			"reply": ["[angry]I will."]},
	],
}


static func topics_for(villager_id: StringName) -> Array:
	return TOPICS.get(villager_id, [])
