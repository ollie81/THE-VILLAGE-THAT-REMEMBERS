extends Node
## Advertising, the game's only income. The game is free and fully playable
## without ever watching an ad.
##
## - Rewarded ads: the player chooses to watch one (the reward is shown first)
##   and gets it only when Google's SDK confirms the ad was watched to the end.
##   At most MAX_PER_DAY a day, a short pause between them, never paid twice.
## - Interstitial ads: only at calm moments the game offers (coming out of a
##   house, waking up in the morning), never in the first minutes after
##   starting, at most one every 10–15 minutes of play, and never while you're
##   building, fighting, riding, placing furniture or talking to someone.
## - Banner ads: a small banner at the bottom while certain menus are open
##   (the Shop), laid out so it never covers buttons or information.
## - No app-open ads.
##
## On Android this uses Google AdMob through the Poing Studios AdMob plugin
## (addons/admob, which bundles Google's Mobile Ads SDK). Before any ad, the
## player is asked for consent where the law requires it (Google's User
## Messaging Platform). Test ads in debug builds; see AdConfig for real IDs.
## On a computer (editor, tests) a short simulated ad stands in, in debug
## builds only; on a phone without the SDK, ads are simply unavailable.

signal reward_granted(reward_id: StringName)
signal ad_failed(reason: String)
signal availability_changed
signal interstitial_shown
signal banner_changed(visible: bool)

const TEST_REWARDED_UNIT_ID := AdConfig.TEST_REWARDED
## Real units come from res://config/admob.cfg (see AdConfig), never the code.
const PRODUCTION_REWARDED_UNIT_ID := ""
const REWARDED_UNIT_ID_ANDROID := TEST_REWARDED_UNIT_ID
const MAX_PER_DAY := 10
## Seconds between two rewarded ads.
const COOLDOWN := 60.0
const SAVE_PATH := "user://ad_rewards.cfg"
const SIMULATED_AD_SECONDS := 3.0
## How long to wait after an ad closes for the SDK's late "earned" message.
const LATE_REWARD_WAIT := 1.5
## Interstitials: not before this much play since starting, then one every
## GAP_MIN..GAP_MAX seconds of play, and not soon after a rewarded ad.
const FIRST_INTERSTITIAL_AFTER := 600.0
const INTERSTITIAL_GAP_MIN := 600.0
const INTERSTITIAL_GAP_MAX := 900.0
const NOT_AFTER_REWARDED := 240.0
## Moments the game offers for an interstitial.
const INTERSTITIAL_MOMENTS := [&"left_house", &"woke_up"]
## Retry loading after a failure: 30 s, doubling, at most 5 minutes.
const RETRY_FIRST := 30.0
const RETRY_MAX := 300.0

## Gifts the player can earn. Each is something the village story explains.
const REWARDS := {
	&"caravan": {"title": "Merchant's caravan", "text": "A passing caravan leaves 8 wood, 5 stone and 6 food."},
	&"harvest": {"title": "Blessed harvest", "text": "Every planted crop ripens at once."},
	&"feast": {"title": "Village feast", "text": "Everyone eats well tonight. All villagers are happier."},
	&"traveller": {"title": "Word of the village", "text": "A traveller hears of the village and comes today."},
	&"credits": {"title": "Village Credits", "text": "Village Credits to spend in the Shop."},
}

enum Provider { NONE, ADMOB, SIMULATED }

## The plugin's GDScript API (Google Mobile Ads SDK underneath).
const ADMOB_API := "res://addons/admob/src/api/"

var provider: int = Provider.NONE
## The SDK is started (after consent).
var ready_for_ads: bool = false
var watched_today: int = 0
var _day_key: String = ""
var _last_shown_msec: int = -10000000
var _loaded_ad = null  # RewardedAd
var _loading: bool = false
var _rewarded_retry: float = RETRY_FIRST
var _pending_reward: StringName = &""
var _pending_token: String = ""
var _earned: bool = false
var _dismissed_unearned: bool = false
var _overlay: CanvasLayer
## A unique token for the reward being paid right now (set just before
## reward_granted fires), so a reward can be recorded and never paid twice.
var last_reward_token: String = ""
var _paid_tokens: Dictionary = {}
var _shown_count: int = 0
var persist: bool = true
## Interstitials.
var play_seconds: float = 0.0
var _last_interstitial_play: float = -1.0
var _last_rewarded_play: float = -1000.0
var _next_gap: float = INTERSTITIAL_GAP_MIN
var _interstitial = null  # InterstitialAd
var _interstitial_loading: bool = false
var _interstitial_retry: float = RETRY_FIRST
var interstitials_shown: int = 0
var _showing_fullscreen: bool = false
## Banner.
var _banner = null  # AdView
var _banner_owners: Dictionary = {}
var banner_visible: bool = false
var _sim_banner: CanvasLayer
var _rng := RandomNumberGenerator.new()
var _install_id: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_next_gap = _rng.randf_range(INTERSTITIAL_GAP_MIN, INTERSTITIAL_GAP_MAX)
	_load_counts()
	var mobile := OS.get_name() == "Android" or OS.get_name() == "iOS"
	if mobile and Engine.has_singleton("PoingGodotAdMob") and ResourceLoader.exists(ADMOB_API + "MobileAds.gd"):
		provider = Provider.ADMOB
		_gather_consent()
	elif OS.is_debug_build() and not mobile:
		provider = Provider.SIMULATED
		ready_for_ads = true


func _process(delta: float) -> void:
	if not get_tree().paused:
		play_seconds += delta


# --- Consent, then the SDK --------------------------------------------------------------

## Asks Google's User Messaging Platform whether consent is needed (EEA, UK,
## and similar laws) and shows its form if so; ads start only afterwards.
func _gather_consent() -> void:
	var params := ConsentRequestParameters.new()
	params.tag_for_under_age_of_consent = AdConfig.child_directed()
	var info = UserMessagingPlatform.consent_information
	info.update(params, func():
		if info.get_is_consent_form_available() and info.get_consent_status() == ConsentInformation.ConsentStatus.REQUIRED:
			UserMessagingPlatform.load_consent_form(func(form):
				form.show(func(_error): _start_sdk()), func(_error): _start_sdk())
		else:
			_start_sdk(),
		func(_error):
			_start_sdk())


func _start_sdk() -> void:
	if ready_for_ads:
		return
	var config := RequestConfiguration.new()
	config.max_ad_content_rating = AdConfig.max_rating()
	if AdConfig.child_directed():
		config.tag_for_child_directed_treatment = RequestConfiguration.TagForChildDirectedTreatment.TRUE
		config.tag_for_under_age_of_consent = RequestConfiguration.TagForUnderAgeOfConsent.TRUE
	MobileAds.set_request_configuration(config)
	var listener := OnInitializationCompleteListener.new()
	listener.on_initialization_complete = func(_status):
		ready_for_ads = true
		_request_ad()
		_request_interstitial()
		availability_changed.emit()
	MobileAds.initialize(listener)


# --- Rewarded ------------------------------------------------------------------------------

## Can a rewarded ad be offered right now? (Why not, or "".)
func unavailable_reason() -> String:
	_roll_day()
	if provider == Provider.NONE:
		return "Ads aren't available on this device."
	if not ready_for_ads:
		return "Ads are starting up..."
	if watched_today >= MAX_PER_DAY:
		return "That's all %d for today. Come back tomorrow!" % MAX_PER_DAY
	var wait := cooldown_left()
	if wait > 0.0:
		return "The next one is ready in %d:%02d." % [int(wait) / 60, int(wait) % 60]
	if provider == Provider.ADMOB and _loaded_ad == null:
		if not _loading:
			_request_ad()
		return "Finding an ad... (check your internet connection)"
	return ""


static func rewarded_unit_id(debug_build: bool = OS.is_debug_build()) -> String:
	return AdConfig.unit_id("rewarded", debug_build)


func is_available() -> bool:
	return unavailable_reason() == ""


func cooldown_left() -> float:
	return maxf(COOLDOWN - (Time.get_ticks_msec() - _last_shown_msec) / 1000.0, 0.0)


func remaining_today() -> int:
	_roll_day()
	return maxi(MAX_PER_DAY - watched_today, 0)


## Shows a rewarded ad; `reward_granted` fires only if it's watched to the end.
func show_for(reward_id: StringName) -> void:
	var reason := unavailable_reason()
	if reason != "":
		ad_failed.emit(reason)
		return
	_pending_reward = reward_id
	_earned = false
	_dismissed_unearned = false
	_shown_count += 1
	_pending_token = "%d-%d-%d" % [int(Time.get_unix_time_from_system()), _shown_count, _rng.randi() % 1000000]
	_last_shown_msec = Time.get_ticks_msec()
	_last_rewarded_play = play_seconds
	Voices.stop()
	match provider:
		Provider.ADMOB:
			_show_admob()
		Provider.SIMULATED:
			_show_simulated_rewarded()


func _finish(watched: bool) -> void:
	get_tree().paused = false
	_showing_fullscreen = false
	if _pending_token == "":
		_shown_count += 1
		_pending_token = "%d-%d-%d" % [int(Time.get_unix_time_from_system()), _shown_count, _rng.randi() % 1000000]
	if watched and _pending_reward != &"" and not _paid_tokens.has(_pending_token):
		watched_today += 1
		_save_counts()
		var reward := _pending_reward
		_pending_reward = &""
		_paid_tokens[_pending_token] = true
		last_reward_token = _pending_token
		_pending_token = ""
		reward_granted.emit(reward)
		last_reward_token = ""
	else:
		var had := _pending_reward != &""
		_pending_reward = &""
		if had and not watched:
			ad_failed.emit("The ad was closed early, so no reward this time.")
	availability_changed.emit()


func _request_ad() -> void:
	if _loading or provider != Provider.ADMOB or not ready_for_ads or _loaded_ad != null:
		return
	_loading = true
	var callback := RewardedAdLoadCallback.new()
	callback.on_ad_loaded = func(ad):
		_loading = false
		_loaded_ad = ad
		_rewarded_retry = RETRY_FIRST
		availability_changed.emit()
	callback.on_ad_failed_to_load = func(error):
		_loading = false
		_loaded_ad = null
		push_warning("Rewarded ad failed to load: %s" % (error.message if error else "unknown"))
		get_tree().create_timer(_rewarded_retry, true).timeout.connect(_request_ad)
		_rewarded_retry = minf(_rewarded_retry * 2.0, RETRY_MAX)
	RewardedAdLoader.new().load(rewarded_unit_id(), AdRequest.new(), callback)


func _show_admob() -> void:
	var ad = _loaded_ad
	_loaded_ad = null
	# The reward token travels with the ad, so a server can verify it (AdMob
	# server-side verification, if a callback URL is set up in AdMob).
	var ssv := ServerSideVerificationOptions.new()
	ssv.user_id = install_id()
	ssv.custom_data = _pending_token
	ad.set_server_side_verification_options(ssv)
	var content := FullScreenContentCallback.new()
	content.on_ad_dismissed_full_screen_content = func():
		ad.destroy()
		on_ad_dismissed()
		_request_ad()
	content.on_ad_failed_to_show_full_screen_content = func(_error):
		ad.destroy()
		_last_shown_msec = -10000000
		get_tree().paused = false
		_showing_fullscreen = false
		_pending_reward = &""
		ad_failed.emit("The ad couldn't be shown. Try again in a moment.")
		_request_ad()
	ad.full_screen_content_callback = content
	var listener := OnUserEarnedRewardListener.new()
	listener.on_user_earned_reward = func(_item):
		on_user_earned_reward()
	_showing_fullscreen = true
	get_tree().paused = true
	ad.show(listener)


## The SDK confirmed the ad was watched (OnUserEarnedReward).
func on_user_earned_reward() -> void:
	_earned = true
	if _dismissed_unearned:
		_dismissed_unearned = false
		_finish(true)


## The ad was closed. Rewards only if the SDK confirmed it was watched; some
## devices confirm a moment after closing, so wait briefly for that.
func on_ad_dismissed() -> void:
	if _pending_reward == &"":
		return  # already finished (a repeated close message)
	if _earned:
		_finish(true)
		return
	_dismissed_unearned = true
	get_tree().create_timer(LATE_REWARD_WAIT, true, false, true).timeout.connect(func():
		if _dismissed_unearned:
			_dismissed_unearned = false
			_finish(false))


## A random id for this install (for ad server-side verification; not
## personal, and not linked to anything else).
func install_id() -> String:
	if _install_id == "":
		var config := ConfigFile.new()
		config.load(SAVE_PATH)
		_install_id = String(config.get_value("ads", "install_id", ""))
		if _install_id == "":
			_install_id = "%08x%08x" % [_rng.randi(), _rng.randi()]
			config.set_value("ads", "install_id", _install_id)
			if persist:
				config.save(SAVE_PATH)
	return _install_id


# --- Interstitials -------------------------------------------------------------------------

## Why an interstitial can't be shown at `moment` now, or "".
func interstitial_reason(moment: StringName) -> String:
	if provider == Provider.NONE or not ready_for_ads:
		return "no ads"
	if not moment in INTERSTITIAL_MOMENTS:
		return "not a calm moment"
	if _showing_fullscreen or _pending_reward != &"":
		return "an ad is already showing"
	if play_seconds < FIRST_INTERSTITIAL_AFTER:
		return "too soon after starting"
	if _last_interstitial_play >= 0.0 and play_seconds - _last_interstitial_play < _next_gap:
		return "too soon after the last one"
	if play_seconds - _last_rewarded_play < NOT_AFTER_REWARDED:
		return "too soon after a rewarded ad"
	var player = GameManager.player
	if player:
		if player.get("combat") and player.combat and player.combat.in_fight():
			return "fighting"
		if player.has_method("is_riding") and player.is_riding():
			return "riding"
		if player.is_busy():
			return "busy"
	if BuildMode.instance and (BuildMode.instance.active or BuildMode.instance.edit_mode != ""):
		return "building"
	if FurnishMode.instance and (FurnishMode.instance.active or FurnishMode.instance.arranging):
		return "furnishing"
	if GameManager.is_in_conversation():
		return "talking"
	if VillageDefence.instance and VillageDefence.instance.is_raid():
		return "a raid"
	if provider == Provider.ADMOB and _interstitial == null:
		_request_interstitial()
		return "not loaded"
	return ""


## Called by the game at a calm moment; shows an interstitial if one is due.
## Returns whether it showed one.
func maybe_show_interstitial(moment: StringName) -> bool:
	if interstitial_reason(moment) != "":
		return false
	_last_interstitial_play = play_seconds
	_next_gap = _rng.randf_range(INTERSTITIAL_GAP_MIN, INTERSTITIAL_GAP_MAX)
	interstitials_shown += 1
	Voices.stop()
	match provider:
		Provider.ADMOB:
			var ad = _interstitial
			_interstitial = null
			var content := FullScreenContentCallback.new()
			content.on_ad_dismissed_full_screen_content = func():
				ad.destroy()
				get_tree().paused = false
				_showing_fullscreen = false
				_request_interstitial()
			content.on_ad_failed_to_show_full_screen_content = func(_error):
				ad.destroy()
				get_tree().paused = false
				_showing_fullscreen = false
				_request_interstitial()
			ad.full_screen_content_callback = content
			_showing_fullscreen = true
			get_tree().paused = true
			ad.show()
		Provider.SIMULATED:
			_show_simulated("Advertisement\n(test interstitial: on a phone a real ad shows here)", func():
				_showing_fullscreen = false)
	interstitial_shown.emit()
	return true


func _request_interstitial() -> void:
	if _interstitial_loading or provider != Provider.ADMOB or not ready_for_ads or _interstitial != null:
		return
	_interstitial_loading = true
	var callback := InterstitialAdLoadCallback.new()
	callback.on_ad_loaded = func(ad):
		_interstitial_loading = false
		_interstitial = ad
		_interstitial_retry = RETRY_FIRST
	callback.on_ad_failed_to_load = func(error):
		_interstitial_loading = false
		push_warning("Interstitial failed to load: %s" % (error.message if error else "unknown"))
		get_tree().create_timer(_interstitial_retry, true).timeout.connect(_request_interstitial)
		_interstitial_retry = minf(_interstitial_retry * 2.0, RETRY_MAX)
	InterstitialAdLoader.new().load(AdConfig.unit_id("interstitial"), AdRequest.new(), callback)


# --- Banner -----------------------------------------------------------------------------------

## Shows the bottom banner while `owner` (a menu) is open.
func show_banner(owner: String) -> void:
	_banner_owners[owner] = true
	_update_banner()


func hide_banner(owner: String) -> void:
	_banner_owners.erase(owner)
	_update_banner()


## Space (in the game's UI pixels) the banner takes at the bottom of the
## screen when shown, so menus can stay clear of it.
func banner_height() -> float:
	if not banner_visible:
		return 0.0
	var ui := get_viewport().get_visible_rect().size if get_viewport() else Vector2(1612, 720)
	var window := Vector2(DisplayServer.window_get_size())
	if window.y <= 0.0:
		window = ui
	var px := 0.0
	if provider == Provider.ADMOB and _banner:
		px = float(_banner.get_height_in_pixels())
	if px <= 0.0:
		# The standard banner is 50 dp tall (dp = physical pixels at 160 dpi).
		var dpi := float(DisplayServer.screen_get_dpi()) if OS.get_name() == "Android" else 160.0
		px = 50.0 * maxf(dpi, 120.0) / 160.0
	return clampf(px * ui.y / window.y, 30.0, ui.y * 0.2) + 8.0


func _update_banner() -> void:
	var want := not _banner_owners.is_empty() and ready_for_ads and provider != Provider.NONE
	if want == banner_visible:
		return
	banner_visible = want
	match provider:
		Provider.ADMOB:
			if want:
				if _banner == null:
					_banner = AdView.new(AdConfig.unit_id("banner"), AdSize.BANNER, AdPosition.Values.BOTTOM)
					_banner.load_ad(AdRequest.new())
				_banner.show()
			elif _banner:
				_banner.hide()
		Provider.SIMULATED:
			if want:
				_sim_banner = CanvasLayer.new()
				_sim_banner.layer = 90
				add_child(_sim_banner)
				var box := ColorRect.new()
				box.name = "TestBanner"
				box.color = Color(0.92, 0.92, 0.95, 0.95)
				box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
				box.grow_horizontal = Control.GROW_DIRECTION_BOTH
				box.grow_vertical = Control.GROW_DIRECTION_BEGIN
				var h := banner_height() - 8.0
				box.offset_left = -h * 3.2
				box.offset_right = h * 3.2
				box.offset_top = -h
				box.mouse_filter = Control.MOUSE_FILTER_IGNORE
				_sim_banner.add_child(box)
				var label := Label.new()
				label.text = "Test banner ad"
				label.add_theme_color_override("font_color", Color(0.2, 0.2, 0.25))
				label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				box.add_child(label)
			elif _sim_banner:
				_sim_banner.queue_free()
				_sim_banner = null
	banner_changed.emit(banner_visible)


# --- Simulated ads (computer, debug builds only) -------------------------------------------

func _show_simulated_rewarded() -> void:
	_show_simulated("Advertisement\n(test ad: on a phone, a real video plays here)", func(): _finish(true), func(): on_ad_dismissed())


## A stand-in for an ad on a computer: a dark screen for a few seconds.
## `skip` (optional) adds a Close button that closes it early (no reward).
func _show_simulated(text: String, done: Callable, skip: Callable = Callable()) -> void:
	_showing_fullscreen = true
	_overlay = CanvasLayer.new()
	_overlay.layer = 100
	_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_overlay)
	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.05, 0.08, 0.96)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(shade)
	var label := UiTheme.label(text, 30)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_overlay.add_child(label)
	var closed := [false]
	if skip.is_valid():
		var close := UiTheme.button("Close", 140)
		close.name = "CloseAd"
		close.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		close.offset_left = -170
		close.offset_top = 20
		close.offset_right = -20
		close.pressed.connect(func():
			if closed[0]:
				return
			closed[0] = true
			_overlay.queue_free()
			_overlay = null
			get_tree().paused = false
			skip.call())
		_overlay.add_child(close)
	get_tree().paused = true
	get_tree().create_timer(SIMULATED_AD_SECONDS, true, false, true).timeout.connect(func():
		if closed[0]:
			return
		closed[0] = true
		if _overlay:
			_overlay.queue_free()
			_overlay = null
		get_tree().paused = false
		done.call())


# --- Daily count --------------------------------------------------------------------------------

func _roll_day() -> void:
	var today := Time.get_date_string_from_system(true)
	if today != _day_key:
		_day_key = today
		watched_today = 0


func _load_counts() -> void:
	var config := ConfigFile.new()
	_day_key = Time.get_date_string_from_system(true)
	if config.load(SAVE_PATH) == OK and String(config.get_value("ads", "day", "")) == _day_key:
		watched_today = int(config.get_value("ads", "watched", 0))


func _save_counts() -> void:
	if not persist:
		return
	var config := ConfigFile.new()
	config.load(SAVE_PATH)
	config.set_value("ads", "day", _day_key)
	config.set_value("ads", "watched", watched_today)
	config.save(SAVE_PATH)


## Tests only: start fresh.
func reset_for_tests() -> void:
	persist = false
	watched_today = 0
	_last_shown_msec = -10000000
	_paid_tokens.clear()
	play_seconds = 0.0
	_last_interstitial_play = -1.0
	_last_rewarded_play = -1000.0
	interstitials_shown = 0
	_banner_owners.clear()
	_update_banner()
