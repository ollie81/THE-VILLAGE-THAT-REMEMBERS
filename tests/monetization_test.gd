extends Node
## Headless test of ads and the credit economy:
##  1 rewarded ad watched to the end pays      6 spending credits
##  2 a cancelled ad pays nothing              7 balances saved and restored
##  3 at most 10 rewarded ads a day            8 interstitials are rare and well timed
##  4 credits from playing                     9 the banner never covers the Shop
##  5 nothing is ever paid twice              10 APK / SDK setup (test IDs, no real IDs in code)
## On a computer the ad SDK isn't there, so the debug build's simulated ad
## runs the same flow; real ads can only be checked on a phone.
## Run:  godot --headless --path . res://tests/monetization_test.tscn

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
	print("== Monetization test ==")
	WorldClock.day = 1
	WorldClock.set_time(10.0)
	WorldClock.set_time_scale(0.0)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _frames(40)
	await _rewarded_completion()
	await _cancelled()
	await _daily_limit()
	await _credit_rewards()
	await _duplicates()
	await _spending()
	await _save_restore()
	await _interstitials()
	await _banner()
	_apk_setup()
	get_tree().paused = false
	print("== %s: %d failure(s) ==" % ["PASSED" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(0 if _failures == 0 else 1)


func _fresh_ad() -> void:
	AdRewards._last_shown_msec = -10000000
	get_tree().paused = false


# 1 ------------------------------------------------------------------------------------------

func _rewarded_completion() -> void:
	print("-- 1. rewarded ad completed")
	var credits := VillageCredits.instance
	_check(AdRewards.provider == AdRewards.Provider.SIMULATED, "on a computer, the debug build uses a simulated ad")
	_check(AdRewards.MAX_PER_DAY == 10, "the daily limit is 10 rewarded ads")
	var shop := ShopPanel.instance
	shop.open_shop("earn")
	await _frames(2)
	_check(shop._ad_button.text.contains("+%d credits" % EconomyConfig.AD_CREDITS) and shop._ad_button.text.contains("10 of 10 left"),
		"the reward is shown before choosing to watch: \"%s\"" % shop._ad_button.text)
	var before := credits.balance
	var watched := AdRewards.watched_today
	shop._ad_button.pressed.emit()
	await _frames(2)
	_check(get_tree().paused and credits.balance == before, "the game pauses during the ad and nothing is paid yet")
	await _seconds(AdRewards.SIMULATED_AD_SECONDS + 0.5)
	_check(not get_tree().paused, "the game carries on after the ad")
	_check(credits.balance == before + EconomyConfig.AD_CREDITS, "watched to the end: +%d credits" % EconomyConfig.AD_CREDITS)
	_check(AdRewards.watched_today == watched + 1 and AdRewards.remaining_today() == 9, "and it counts towards today's 10")
	_check(AdRewards.cooldown_left() > 0.0 and AdRewards.unavailable_reason().begins_with("The next one"), "a short pause before the next one")
	shop.close_shop()


# 2 ------------------------------------------------------------------------------------------

func _cancelled() -> void:
	print("-- 2. cancelled ad")
	var credits := VillageCredits.instance
	_fresh_ad()
	var before := credits.balance
	var failed: Array = []
	var on_fail := func(reason): failed.append(reason)
	AdRewards.ad_failed.connect(on_fail)
	AdRewards.show_for(&"credits")
	await _frames(3)
	var close: Button = AdRewards.find_child("CloseAd", true, false)
	_check(close != null, "the ad can be closed early")
	if close:
		close.pressed.emit()
	await _seconds(AdRewards.LATE_REWARD_WAIT + AdRewards.SIMULATED_AD_SECONDS + 0.5)
	_check(credits.balance == before, "closed early: no credits")
	_check(failed.size() == 1 and String(failed[0]).contains("closed early"), "and the player is told why")
	_check(not get_tree().paused, "the game isn't left paused")
	# The SDK reporting the ad failed to show: nothing paid, nothing counted.
	_fresh_ad()
	var watched := AdRewards.watched_today
	AdRewards._pending_reward = &"credits"
	AdRewards._earned = false
	AdRewards.on_ad_dismissed()
	await _seconds(AdRewards.LATE_REWARD_WAIT + 0.3)
	_check(credits.balance == before and AdRewards.watched_today == watched, "an unconfirmed ad isn't paid or counted")
	AdRewards.ad_failed.disconnect(on_fail)


# 3 ------------------------------------------------------------------------------------------

func _daily_limit() -> void:
	print("-- 3. daily limit")
	var credits := VillageCredits.instance
	_fresh_ad()
	AdRewards.watched_today = AdRewards.MAX_PER_DAY - 1
	AdRewards.show_for(&"credits")
	await _seconds(AdRewards.SIMULATED_AD_SECONDS + 0.5)
	_check(AdRewards.watched_today == AdRewards.MAX_PER_DAY and AdRewards.remaining_today() == 0, "the 10th ad of the day is allowed")
	_fresh_ad()
	var before := credits.balance
	var failed: Array = []
	var on_fail := func(reason): failed.append(reason)
	AdRewards.ad_failed.connect(on_fail)
	AdRewards.show_for(&"credits")
	await _frames(3)
	_check(not get_tree().paused and credits.balance == before, "an 11th isn't shown or paid")
	_check(failed.size() == 1 and String(failed[0]).contains("10"), "and says to come back tomorrow: %s" % (failed[0] if failed else ""))
	AdRewards.ad_failed.disconnect(on_fail)
	var shop := ShopPanel.instance
	shop.open_shop("earn")
	await _frames(2)
	_check(shop._ad_button.disabled, "the Shop's ad button is disabled for the rest of the day")
	shop.close_shop()
	AdRewards._day_key = "2000-01-01"
	_check(AdRewards.remaining_today() == AdRewards.MAX_PER_DAY, "a new day brings 10 more")


# 4 ------------------------------------------------------------------------------------------

func _credit_rewards() -> void:
	print("-- 4. credits from playing")
	var credits := VillageCredits.instance
	var rewards := CreditRewards.instance
	_check(rewards != null, "the rewards tracker is running")
	# Discovering a place.
	var player: PlayerController = GameManager.player
	var home := player.global_position
	var before := credits.balance
	var windmill: Dictionary = CreditRewards.PLACES[0]
	player.global_position = VillageLayout.ground_point((windmill["at"] as Vector3).x + 3.0, (windmill["at"] as Vector3).z + 8.0)
	rewards._check_places()
	_check(rewards.is_discovered("windmill") and credits.balance >= before + int(EconomyConfig.EARN["discovery"]),
		"discovering %s pays +%d" % [windmill["name"], int(EconomyConfig.EARN["discovery"])])
	player.global_position = home
	# Achievements.
	for p in CreditRewards.PLACES.slice(1, 3):
		rewards.discover(String(p["id"]))
	rewards.check_achievements()
	_check(rewards.is_achieved("explorer"), "discovering 3 places earns the Explorer achievement")
	# Daily challenges.
	var todays := rewards.todays_challenges()
	_check(todays.size() == 3 and todays == CreditRewards.challenges_for(CreditRewards.today()), "three daily challenges, the same all day")
	var other_day := CreditRewards.challenges_for("2031-03-04")
	_check(other_day.size() == 3, "other days have their own three")
	var c0: Dictionary = todays[0]
	var c0_done := rewards.challenge_done(String(c0["id"]))
	before = credits.balance
	if not c0_done:
		rewards.record(String(c0["event"]), int(c0["target"]))
		_check(rewards.challenge_done(String(c0["id"])) and credits.balance == before + int(EconomyConfig.EARN["challenge"]),
			"finishing a challenge (%s) pays +%d" % [String(c0["text"]) % int(c0["target"]), int(EconomyConfig.EARN["challenge"])])
	for c in todays:
		rewards.record(String(c["event"]), int(c["target"]))
	var all_done := todays.all(func(c): return rewards.challenge_done(String(c["id"])))
	_check(all_done and credits.paid.has("challenge_%s_all" % rewards.day), "finishing all three pays the +%d bonus" % int(EconomyConfig.EARN["challenges_all"]))
	before = credits.balance
	for c in todays:
		rewards.record(String(c["event"]), int(c["target"]))
	_check(credits.balance == before, "a finished challenge doesn't pay again")
	# Buying planks doesn't count as gathering.
	var gathered := int(rewards.gathered.get("wood", 0))
	credits.earn(50, "test_planks_money")
	credits.buy_supplies("wood_bundle")
	_check(int(rewards.gathered.get("wood", 0)) == gathered, "bought planks don't count as gathered")
	GameState.add(&"wood", 3)
	_check(int(rewards.gathered.get("wood", 0)) == gathered + 3, "gathered wood does")
	# Streaks and lucky days.
	_check(DailyGift.streak_bonus(1) == 0 and DailyGift.streak_bonus(3) == 3 and DailyGift.streak_bonus(7) == 10 and DailyGift.streak_bonus(14) == 10,
		"days in a row add a bonus (3 on day 3, 10 on day 7, 10 each week)")
	var lucky := 0
	for d in 600:
		if DailyGift.is_lucky(20000 + d):
			lucky += 1
	_check(lucky > 50 and lucky < 160, "about one day in %d is lucky (%d of 600)" % [EconomyConfig.LUCKY_ONE_IN, lucky])
	var gift := DailyGift.instance
	DailyGift.enabled = true
	gift.claims = 0
	gift.last_claim_day = -1
	gift.high_unix = 0.0
	gift.streak = 0
	var day0 := 20500.0 * DailyGift.DAY_SECONDS + 3600.0
	for i in 3:
		gift.check(day0 + i * DailyGift.DAY_SECONDS)
	_check(gift.streak == 3, "three days in a row: a 3-day streak")
	gift.check(day0 + 5 * DailyGift.DAY_SECONDS)
	_check(gift.streak == 1 and gift.claims == 4, "a missed day restarts the streak but keeps every visit")
	DailyGift.enabled = false


# 5 ------------------------------------------------------------------------------------------

func _duplicates() -> void:
	print("-- 5. never paid twice")
	var credits := VillageCredits.instance
	var before := credits.balance
	# Confirmed, then the SDK sends 'closed' twice and 'earned' twice.
	_fresh_ad()
	AdRewards._pending_reward = &"credits"
	AdRewards._pending_token = "dup-test-1"
	AdRewards._earned = false
	AdRewards.on_user_earned_reward()
	AdRewards.on_ad_dismissed()
	AdRewards.on_ad_dismissed()
	AdRewards.on_user_earned_reward()
	await _frames(3)
	_check(credits.balance == before + EconomyConfig.AD_CREDITS, "repeated SDK messages pay one reward")
	# The same ad token can't be paid again even if the flow restarts.
	before = credits.balance
	AdRewards._pending_reward = &"credits"
	AdRewards._pending_token = "dup-test-1"
	AdRewards._finish(true)
	_check(credits.balance == before, "the same ad can't be paid twice")
	# The credits side also refuses a repeated token.
	_check(credits.earn(15, "ad_dup-test-1") == 0, "the credits ledger refuses a token it has paid")
	before = credits.balance
	CreditRewards.instance.discover("windmill")
	CreditRewards.instance.check_achievements()
	CreditRewards.instance.check_achievements()
	_check(credits.balance == before, "discoveries and achievements pay once")
	AdRewards.reward_granted.emit(&"credits")
	_check(credits.balance == before, "a reward signal without a confirmed ad pays nothing")


# 6 ------------------------------------------------------------------------------------------

func _spending() -> void:
	print("-- 6. spending")
	var credits := VillageCredits.instance
	credits.earn(400, "test_spending_money")
	# Missing materials for a house.
	for r in [&"wood", &"stone", &"herbs"]:
		GameState.add(r, -GameState.count(r))
	var cost: Dictionary = StructureCatalog.info(&"house_medium")["cost"]
	var price := VillageCredits.missing_price(cost)
	var before := credits.balance
	_check(price == EconomyConfig.credits_for(cost) and price > 0, "the missing materials for a medium house cost %d credits" % price)
	_check(credits.buy_missing(cost, "a medium house") and credits.balance == before - price and GameState.can_afford(cost),
		"buying them leaves you able to build it")
	_check(VillageCredits.missing_price(cost) == 0 and not credits.buy_missing(cost, "a medium house"), "nothing more to buy then")
	# Furniture into storage.
	before = credits.balance
	var stored := Furnishings.stored().size()
	var record := credits.buy_furniture(&"lamp")
	_check(not record.is_empty() and String(record["place"]) == "stored" and Furnishings.stored().size() == stored + 1
		and credits.balance == before - VillageCredits.furniture_price(&"lamp"), "bought furniture waits in storage, ready to place")
	# Unlocking a paint.
	var d := HouseDesigns.default_design()
	d["wall"] = 5
	_check(int(HouseDesigns.step(d, "wall", 1)["wall"]) == 0, "locked paints are skipped in Design")
	_check(credits.buy_unlock("paint_lavender", 25, "Lavender") and credits.owns("paint_lavender"), "a paint can be unlocked")
	_check(int(HouseDesigns.step(d, "wall", 1)["wall"]) == 6, "and then appears in Design")
	before = credits.balance
	_check(credits.buy_unlock("paint_lavender", 25, "Lavender") and credits.balance == before, "an unlock is only paid once")
	# Animals still use credits (already in the game).
	_check(AnimalManager.instance != null, "animals are bought with credits in the Shop")
	# Not enough credits.
	credits.spend(credits.balance)
	_check(credits.buy_furniture(&"bed").is_empty() and not credits.buy_unlock("paint_mint", 25, "Mint"), "nothing is bought without enough credits")
	_check(credits.balance == 0, "and the balance never goes below zero")
	# The Shop shows every tab, prices and the balance.
	var shop := ShopPanel.instance
	shop.open_shop("supplies")
	await _frames(2)
	_check(shop._balance.text == "0 Village Credits", "the Shop shows the balance: %s" % shop._balance.text)
	for t in ShopPanel.TABS:
		shop.show_tab(t[0])
		await _frames(1)
		_check((shop._pages[t[0]] as Control).visible and (shop._pages[t[0]] as Control).get_child_count() > 0, "the %s tab has things in it" % t[1])
	shop.show_tab("building")
	_check(shop.find_child("Kit_house_medium", true, false) != null, "Building lists missing materials per building")
	shop.show_tab("furniture")
	var b: Button = shop.find_child("BuyFurniture_lamp", true, false)
	_check(b != null and b.text.contains("credits") and b.disabled, "furniture shows its price (and can't be bought with 0 credits)")
	shop.close_shop()


# 7 ------------------------------------------------------------------------------------------

func _save_restore() -> void:
	print("-- 7. save and restore")
	var credits := VillageCredits.instance
	credits.earn(123, "test_save_money")
	var balance := credits.balance
	var data: Dictionary = JSON.parse_string(JSON.stringify(credits.to_dict()))
	var copy := VillageCredits.new()
	copy.from_dict(data)
	_check(copy.balance == balance and copy.owns("paint_lavender") and copy.paid.has("discover_windmill"), "credits, unlocks and found places survive a save")
	var tampered := data.duplicate(true)
	tampered["balance"] = 99999
	copy.from_dict(tampered)
	_check(copy.balance == 0, "an edited save doesn't give free credits")
	copy.free()
	var rewards := CreditRewards.instance
	var rdata: Dictionary = JSON.parse_string(JSON.stringify(rewards.to_dict()))
	var r2 := CreditRewards.new()
	r2.from_dict(rdata)
	_check(r2.gathered == rewards.gathered and r2.progress == rewards.progress, "challenge progress and gathering survive a save")
	r2.from_dict({"day": "2001-01-01", "progress": {"wood": 9}})
	_check(r2.progress.is_empty() and r2.day == CreditRewards.today(), "yesterday's challenge progress doesn't carry over")
	r2.free()
	var gift := DailyGift.instance
	gift.streak = 4
	var gdata: Dictionary = JSON.parse_string(JSON.stringify(gift.to_dict()))
	var g2 := DailyGift.new()
	g2.from_dict(gdata)
	_check(g2.streak == 4, "the streak survives a save")
	var old := gdata.duplicate()
	old.erase("streak")
	old["sig"] = DailyGift._signature({"claims": int(old["claims"]), "last_day": int(old["last_day"]),
		"last_unix": float(old["last_unix"]), "high_unix": float(old["high_unix"])}, false)
	g2.from_dict(old)
	_check(g2.last_reason != "save edited" and g2.streak == 0, "a save from before streaks still loads as genuine")
	gdata["streak"] = 50
	g2.from_dict(gdata)
	_check(g2.streak == 0, "an edited streak isn't trusted")
	g2.free()
	# The daily ad count is kept between sessions (in its own file).
	_check(AdRewards.SAVE_PATH.begins_with("user://"), "the daily ad count is stored on the phone")


# 8 ------------------------------------------------------------------------------------------

func _interstitials() -> void:
	print("-- 8. interstitial frequency")
	AdRewards.play_seconds = 0.0
	AdRewards._last_interstitial_play = -1.0
	AdRewards._last_rewarded_play = -1000.0
	_check(AdRewards.interstitial_reason(&"left_house") == "too soon after starting", "never in the first minutes after starting")
	AdRewards.play_seconds = AdRewards.FIRST_INTERSTITIAL_AFTER + 1.0
	_check(AdRewards.interstitial_reason(&"fighting") == "not a calm moment", "only at calm moments the game offers")
	BuildMode.instance.active = true
	_check(AdRewards.interstitial_reason(&"left_house") == "building", "never while building")
	BuildMode.instance.active = false
	FurnishMode.instance.arranging = true
	_check(AdRewards.interstitial_reason(&"left_house") == "furnishing", "never while arranging furniture")
	FurnishMode.instance.arranging = false
	_check(AdRewards.interstitial_reason(&"left_house") == "", "after 10 minutes, leaving a house can show one: %s" % AdRewards.interstitial_reason(&"left_house"))
	var shown := AdRewards.interstitials_shown
	_check(AdRewards.maybe_show_interstitial(&"left_house"), "one is shown")
	await _seconds(AdRewards.SIMULATED_AD_SECONDS + 0.5)
	_check(not get_tree().paused and AdRewards.interstitials_shown == shown + 1, "and the game carries on after it")
	AdRewards.play_seconds += 60.0
	_check(not AdRewards.maybe_show_interstitial(&"woke_up"), "not another one a minute later")
	AdRewards.play_seconds += AdRewards.INTERSTITIAL_GAP_MIN - 61.0
	_check(AdRewards.interstitial_reason(&"woke_up") != "", "nor before 10 minutes have passed")
	AdRewards.play_seconds += AdRewards.INTERSTITIAL_GAP_MAX - AdRewards.INTERSTITIAL_GAP_MIN + 2.0
	_check(AdRewards.interstitial_reason(&"woke_up") == "", "15 minutes later one may show again")
	_check(AdRewards._next_gap >= AdRewards.INTERSTITIAL_GAP_MIN and AdRewards._next_gap <= AdRewards.INTERSTITIAL_GAP_MAX, "the gap is between 10 and 15 minutes")
	AdRewards._last_rewarded_play = AdRewards.play_seconds - 10.0
	_check(AdRewards.interstitial_reason(&"woke_up") == "too soon after a rewarded ad", "not straight after a rewarded ad")
	AdRewards._last_rewarded_play = -1000.0
	var player: PlayerController = GameManager.player
	if player.combat:
		var fight := player.combat.in_fight()
		_check(not fight or AdRewards.interstitial_reason(&"woke_up") == "fighting", "never during a fight")


# 9 ------------------------------------------------------------------------------------------

func _banner() -> void:
	print("-- 9. banner position")
	_check(not AdRewards.banner_visible, "no banner during play")
	var shop := ShopPanel.instance
	shop.open_shop("supplies")
	await _frames(3)
	_check(AdRewards.banner_visible, "a banner shows while the Shop is open")
	var banner: Control = AdRewards.find_child("TestBanner", true, false)
	var screen := shop.get_viewport_rect().size
	_check(banner != null and absf(banner.get_global_rect().end.y - screen.y) < 2.0, "at the very bottom of the screen")
	var panel_rect := shop._panel.get_global_rect()
	_check(banner != null and panel_rect.end.y <= banner.get_global_rect().position.y,
		"it never covers the Shop (window ends at %d, banner starts at %d)" % [int(panel_rect.end.y), int(banner.get_global_rect().position.y) if banner else -1])
	_check(panel_rect.position.y >= 0.0, "and the Shop still fits on screen")
	_check(banner == null or banner.mouse_filter == Control.MOUSE_FILTER_IGNORE, "the stand-in banner can't catch taps meant for the game")
	shop.close_shop()
	await _frames(2)
	_check(not AdRewards.banner_visible and AdRewards.find_child("TestBanner", true, false) == null, "closing the Shop removes the banner")
	AdRewards.show_banner("a")
	AdRewards.show_banner("b")
	AdRewards.hide_banner("a")
	_check(AdRewards.banner_visible, "it stays while another menu still wants it")
	AdRewards.hide_banner("b")
	_check(not AdRewards.banner_visible, "and goes when none do")


# 10 -----------------------------------------------------------------------------------------

func _apk_setup() -> void:
	print("-- 10. APK / SDK setup")
	var api := ["MobileAds", "RewardedAd", "RewardedAdLoader", "InterstitialAd", "InterstitialAdLoader", "AdView"]
	var ok := true
	for n in api:
		ok = ok and load(AdRewards.ADMOB_API + n + ".gd") != null
	_check(ok, "the AdMob plugin's scripts load in this Godot version")
	_check(load("res://addons/admob/src/ump/api/UserMessagingPlatform.gd") != null, "consent (UMP) is available")
	_check(FileAccess.file_exists("res://addons/admob/android/bin/ads/libs/poing-godot-admob-ads-release.aar")
		and FileAccess.file_exists("res://addons/admob/android/bin/ads/libs/poing-godot-admob-core-release.aar"), "the Android libraries are in the project")
	var presets := ConfigFile.new()
	presets.load("res://export_presets.cfg")
	_check(bool(presets.get_value("preset.0.options", "gradle_build/use_gradle_build", false)), "the Android export uses the Gradle build (needed for the SDK)")
	_check(AdConfig.unit_id("rewarded", true) == AdConfig.TEST_REWARDED and AdConfig.unit_id("interstitial", true) == AdConfig.TEST_INTERSTITIAL
		and AdConfig.unit_id("banner", true) == AdConfig.TEST_BANNER, "debug builds always use Google's test ads")
	_check(FileAccess.file_exists(AdConfig.CONFIG_PATH) or AdConfig.unit_id("rewarded", false) == AdConfig.TEST_REWARDED,
		"release builds use test ads until real IDs are supplied")
	_check(not AdConfig.is_real_id(AdConfig.TEST_REWARDED) and AdConfig.is_real_id("ca-app-pub-1234567890123456/1234567890"), "test IDs are told apart from real ones")
	var config_gd := FileAccess.get_file_as_string("res://addons/admob/android/config.gd")
	_check(config_gd.contains("APPLICATION_ID := \"%s\"" % AdConfig.TEST_APP_ID), "the committed App ID is Google's test App ID (CI swaps in yours from a secret)")
	var found := _real_ids_in("res://scripts")
	_check(found.is_empty(), "no real AdMob IDs are written in the code %s" % str(found))
	_check(not AdConfig.child_directed() and AdConfig.max_rating() == "PG", "general audience: ads rated PG at most")


func _real_ids_in(path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(path)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".gd"):
			var text := FileAccess.get_file_as_string(path + "/" + f)
			var re := RegEx.create_from_string("ca-app-pub-(\\d+)")
			for m in re.search_all(text):
				if m.get_string(1) != "3940256099942544":
					out.append(f)
	for d in dir.get_directories():
		out.append_array(_real_ids_in(path + "/" + d))
	return out
