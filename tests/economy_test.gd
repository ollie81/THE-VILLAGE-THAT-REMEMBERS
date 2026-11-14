extends Node
## Headless test of Village Credits, the Shop, rewarded-ad credits and the
## Wardrobe (outfits on the real player model, saved and loaded).
## Run:  godot --headless --path . res://tests/economy_test.tscn

var _failures: int = 0
var _main = null


func _ready() -> void:
	SaveService.enabled = false
	PopulationDirector.auto_arrivals = false
	Guide.rewards = false
	DailyGift.persist = false
	AdRewards.reset_for_tests()
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


func _seconds(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _run() -> void:
	print("== Economy test ==")
	WorldClock.day = 1
	WorldClock.set_time(10.0)
	WorldClock.set_time_scale(0.0)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _frames(40)
	await _credits()
	await _ads()
	await _shop()
	await _wardrobe()
	await _saving()
	print("== %s: %d failure(s) ==" % ["PASSED" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(0 if _failures == 0 else 1)


# --- Credits ---------------------------------------------------------------------------

func _credits() -> void:
	var credits := VillageCredits.instance
	_check(credits != null and credits.balance == EconomyConfig.STARTING_CREDITS, "a new village starts with %d credits" % EconomyConfig.STARTING_CREDITS)
	var before := credits.balance
	_check(credits.earn(5, "test_token") == 5 and credits.earn(5, "test_token") == 0 and credits.balance == before + 5,
		"the same reward token is only ever paid once")
	_check(not credits.spend(credits.balance + 1) and credits.balance == before + 5, "you can't spend more than you have")
	# Goals pay once.
	before = credits.balance
	GameState.objective_completed.emit(0, "Meet the villagers")
	GameState.objective_completed.emit(0, "Meet the villagers")
	_check(credits.balance == before + int(EconomyConfig.EARN["objective"]), "reaching a goal pays +%d once" % int(EconomyConfig.EARN["objective"]))
	# Chests pay once.
	before = credits.balance
	var treasure: Treasure = _main.find_child("Treasure", true, false)
	if treasure:
		treasure._open(0, null)
		treasure._open(0, null)
	_check(treasure != null and credits.balance == before + int(EconomyConfig.EARN["chest"]), "finding a chest pays +%d once" % int(EconomyConfig.EARN["chest"]))
	# Helping a villager pays.
	before = credits.balance
	var board := RequestBoard.instance
	var helped := false
	# Today's requests are random: make sure there's one to bring something.
	var asker0 = GameManager.villagers[0]
	var made: Dictionary = board._fetch(asker0)
	made["id"] = board._next_id
	board._next_id += 1
	made["kind"] = "fetch"
	made["from"] = String(asker0.get_villager_id())
	made["done"] = false
	made["day"] = WorldClock.day
	board.requests.insert(0, made)
	for request: Dictionary in board.open_requests():
		var asker = GameManager.get_villager(StringName(String(request["from"])))
		if asker == null:
			continue
		if String(request["kind"]) == "fetch":
			GameState.add(StringName(String(request["resource"])), int(request["amount"]))
			board.fulfil(int(request["id"]), asker)
			helped = true
			break
	_check(helped and credits.balance == before + int(EconomyConfig.EARN["request"]), "helping a villager pays +%d" % int(EconomyConfig.EARN["request"]))
	# Saved and loaded, through JSON like the save file.
	credits.unlock("hair_afro")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(credits.to_dict()))
	var balance := credits.balance
	credits.from_dict(saved)
	_check(credits.balance == balance and credits.owns("hair_afro") and credits.paid.has("test_token"), "credits, purchases and paid rewards survive saving")
	credits.earn(5, "test_token")
	_check(credits.balance == balance, "(and a reward paid before saving isn't paid again after loading)")
	var edited := saved.duplicate(true)
	edited["balance"] = 99999
	credits.from_dict(edited)
	_check(credits.balance == 0 and not credits.owns("hair_afro"), "an edited save file is caught by the checksum")
	credits.from_dict(saved)
	credits.from_dict({})
	_check(credits.balance == EconomyConfig.STARTING_CREDITS, "a save from before credits existed starts with %d" % EconomyConfig.STARTING_CREDITS)
	credits.from_dict(saved)


# --- Rewarded ads -----------------------------------------------------------------------------

func _ads() -> void:
	var credits := VillageCredits.instance
	var before := credits.balance
	_check(AdRewards.REWARDS.has(&"credits"), "Village Credits can be chosen as an ad reward")
	# A reward signal without a confirmed ad (no token) pays nothing.
	AdRewards.reward_granted.emit(&"credits")
	_check(credits.balance == before, "credits aren't paid without a confirmed, finished ad")
	# The simulated ad (debug builds) runs the real flow: paid when it finishes.
	_check(AdRewards.unavailable_reason() == "", "an ad is available: %s" % AdRewards.unavailable_reason())
	AdRewards.show_for(&"credits")
	_check(credits.balance == before, "nothing is paid while the ad is playing")
	await _seconds(AdRewards.SIMULATED_AD_SECONDS + 0.5)
	_check(credits.balance == before + EconomyConfig.AD_CREDITS, "a watched ad pays +%d credits" % EconomyConfig.AD_CREDITS)
	# An ad closed before the SDK confirms the reward pays nothing.
	before = credits.balance
	AdRewards._last_shown_msec = -10000000
	AdRewards._pending_reward = &"credits"
	AdRewards._earned = false
	AdRewards.on_ad_dismissed()
	await _seconds(AdRewards.LATE_REWARD_WAIT + 0.4)
	_check(credits.balance == before, "an ad closed early pays nothing")
	# A late duplicate 'earned' message after that pays nothing either.
	AdRewards.on_user_earned_reward()
	await _frames(2)
	_check(credits.balance == before, "a late or repeated 'earned' message doesn't pay")
	# Confirmed by the SDK, then closed: paid once, even if closed twice.
	AdRewards._pending_reward = &"credits"
	AdRewards._earned = false
	AdRewards.on_user_earned_reward()
	AdRewards.on_ad_dismissed()
	AdRewards.on_ad_dismissed()
	await _frames(2)
	_check(credits.balance == before + EconomyConfig.AD_CREDITS, "a confirmed ad pays exactly once")
	get_tree().paused = false


# --- Shop -----------------------------------------------------------------------------------

func _shop() -> void:
	var credits := VillageCredits.instance
	credits.earn(100, "shop_test")
	var wood := GameState.count(&"wood")
	var before := credits.balance
	var bundle: Dictionary = EconomyConfig.SHOP[0]
	_check(credits.buy_supplies(String(bundle["id"])) and credits.balance == before - int(bundle["price"])
		and GameState.count(&"wood") == wood + int(bundle["items"][&"wood"]), "buying %s" % bundle["name"])
	credits.spend(credits.balance)
	_check(not credits.buy_supplies(String(bundle["id"])) and GameState.count(&"wood") == wood + int(bundle["items"][&"wood"]), "and not without the credits")
	var shop := ShopPanel.instance
	_check(shop != null and shop._button.text == "Shop", "there's a Shop button")
	shop.toggle()
	_check(shop.is_open() and shop._list.get_child_count() == EconomyConfig.SHOP.size(), "the Shop lists the supplies")
	(shop.find_child("WardrobeButton", true, false) as Button).pressed.emit()
	_check(not shop.is_open() and WardrobePanel.instance.visible, "and opens the Wardrobe")
	WardrobePanel.instance.visible = false
	var actions: ActionsMenu = _main.find_child("ActionsMenu", true, false)
	actions.do(&"wardrobe")
	_check(WardrobePanel.instance.visible, "the Wardrobe is also in Actions")
	WardrobePanel.instance.visible = false


# --- Wardrobe ---------------------------------------------------------------------------------

func _wardrobe() -> void:
	var credits := VillageCredits.instance
	var player: PlayerController = GameManager.player
	var look := PlayerController.create_default_appearance()
	WardrobeCatalog.apply(look, "dress")
	_check(look.tunic_length >= 0.7, "a dress lengthens the outfit into a skirt")
	WardrobeCatalog.apply(look, "cap")
	WardrobeCatalog.apply(look, "straw_hat")
	_check(look.has_accessory("straw_hat") and not look.has_accessory("cap"), "one hat at a time")
	WardrobeCatalog.apply(look, "cloak")
	_check(not look.has_accessory("cloak"), "tapping an extra you wear takes it off")
	_check(WardrobeCatalog.is_owned("tunic") and not WardrobeCatalog.is_owned("hair_braids"), "basic clothes are free, others are bought")
	_check(not WardrobeCatalog.is_owned("flower_crown"), "the flower crown starts locked")
	GameState.set_flag(&"requests_done", 3)
	_check(WardrobeCatalog.is_owned("flower_crown"), "and is earned by helping 3 villagers")
	GameState.set_flag(&"requests_done", 0)
	# Try on and buy through the panel.
	var w := WardrobePanel.instance
	w.open()
	var old_look := AppearanceCodec.to_dict(player.model.appearance)
	w.try_on("hair_braids")
	w.try_on("glasses")
	w.colour_target = "shirt_color"
	w.dye("dye_crimson")
	var need := w.shopping()
	var price := int(WardrobeCatalog.item("hair_braids")["price"]) + int(WardrobeCatalog.item("glasses")["price"]) + int(WardrobeCatalog.item("dye_crimson")["price"])
	_check(int(need["cost"]) == price, "the outfit's price adds up: %d credits" % int(need["cost"]))
	credits.spend(credits.balance)
	_check(not w.wear() and AppearanceCodec.to_dict(player.model.appearance) == old_look, "without enough credits nothing is bought or changed")
	credits.earn(price + 5, "wardrobe_test")
	var before := credits.balance
	_check(w.wear(), "with enough credits: Buy and wear")
	await _frames(3)
	var worn := player.model.appearance
	_check(credits.balance == before - price, "exactly %d credits were spent" % price)
	_check(credits.owns("hair_braids") and credits.owns("glasses") and credits.owns("dye_crimson"), "and the items are now owned")
	_check(worn.hair_style == "braids" and worn.has_accessory("glasses") and worn.shirt_color.is_equal_approx(WardrobeCatalog.item("dye_crimson")["color"]),
		"the real 3D character wears them")
	_check(player.model.skeleton != null and player.model.body != null and player.model.get_parent() == player and player.get_children().filter(func(c): return c is CharacterModel).size() == 1,
		"on one rebuilt, animated model")
	player.tools.hold(&"axe", 1.0)
	_check(player.tools._attachment != null and player.tools._attachment.get_parent() == player.model.skeleton, "tools go in the new model's hand")
	player.tools.hold(&"", 0.0)
	GameState.set_flag(&"has_sword")
	player.combat.refresh_equipment()
	_check(player.combat._sword != null and player.combat._sword.get_parent().get_parent() == player.model.skeleton, "and so do the sword and shield")
	GameState.set_flag(&"has_sword", false)
	player.combat.refresh_equipment()
	w.open()
	w.try_on("hair_long")
	w.try_on("hair_braids")
	before = credits.balance
	_check(w.shopping()["cost"] == 0 and w.wear() and credits.balance == before, "things you own cost nothing to wear again")


# --- Saving the look -----------------------------------------------------------------------------

func _saving() -> void:
	var player: PlayerController = GameManager.player
	var data: Dictionary = JSON.parse_string(JSON.stringify(player.get_save_data()))
	_check(data.has("appearance"), "the player's look is in the save")
	var keep_data := SaveService._data
	SaveService.enabled = true
	SaveService._data = {"version": SaveService.SAVE_VERSION, "player": data}
	var loaded := PlayerController.saved_appearance()
	_check(loaded.hair_style == "braids" and loaded.has_accessory("glasses"), "and loads back the same")
	SaveService._data = {"version": SaveService.SAVE_VERSION, "player": {"position": [0, 0, 0], "yaw": 0.0}}
	var old := PlayerController.saved_appearance()
	_check(old.hair_style == PlayerController.create_default_appearance().hair_style, "an older save without a look keeps the starting traveller")
	SaveService._data = keep_data
	SaveService.enabled = false
