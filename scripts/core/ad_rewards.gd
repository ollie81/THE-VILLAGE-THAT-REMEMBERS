extends Node
## Optional rewarded video ads: the player chooses to watch an ad and gets a
## gift for the village. Nothing is ever forced, there are no banner or
## pop-up ads, and the game is fully playable without watching any.
##
## On Android this uses Google AdMob through the Poing Studios AdMob plugin
## (addons/admob), loaded only if it's installed. Until you replace the IDs
## below with your own from https://admob.google.com, Google's TEST ads are
## shown, which pay nothing but let you check everything works.
## On desktop and in tests a short simulated ad stands in (debug builds only).

signal reward_granted(reward_id: StringName)
signal ad_failed(reason: String)
signal availability_changed

## Replace with your own rewarded ad unit ID (AdMob → Apps → Ad units).
## Also put your AdMob App ID in addons/admob/android/config.gd.
const REWARDED_UNIT_ID_ANDROID := "ca-app-pub-3940256099942544/5224354917"  # Google's test unit
const MAX_PER_DAY := 6
## Seconds between two ads.
const COOLDOWN := 120.0
const SAVE_PATH := "user://ad_rewards.cfg"
const SIMULATED_AD_SECONDS := 3.0

## Gifts the player can earn. Each is something the village story explains:
## a caravan, a blessing, a feast, a traveller.
const REWARDS := {
	&"caravan": {"title": "Merchant's caravan", "text": "A passing caravan leaves 8 wood, 5 stone and 6 food."},
	&"harvest": {"title": "Blessed harvest", "text": "Every planted crop ripens at once."},
	&"feast": {"title": "Village feast", "text": "Everyone eats well tonight. All villagers are happier."},
	&"traveller": {"title": "Word of the village", "text": "A traveller hears of the village and comes today."},
}

enum Provider { NONE, ADMOB, SIMULATED }

## The AdMob plugin's scripts, loaded only when the plugin is installed.
const ADMOB_API := "res://addons/admob/gdscript/src/api/"

var provider: int = Provider.NONE
## Shown today (resets at midnight, real time).
var watched_today: int = 0
var _day_key: String = ""
var _last_shown_msec: int = -10000000
var _loaded_ad = null  # RewardedAd (AdMob)
var _loading: bool = false
var _pending_reward: StringName = &""
var _earned: bool = false
var _overlay: CanvasLayer
## Tests set this so the daily count isn't written to the player's files.
var persist: bool = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_counts()
	if Engine.has_singleton("PoingGodotAdMob") and Engine.has_singleton("PoingGodotAdMobRewardedAd") \
			and ResourceLoader.exists(ADMOB_API + "MobileAds.gd"):
		provider = Provider.ADMOB
		_api("MobileAds").initialize()
		_request_ad()
	elif OS.is_debug_build():
		provider = Provider.SIMULATED


## Can an ad be offered right now? (Returns why not, or "".)
func unavailable_reason() -> String:
	_roll_day()
	if provider == Provider.NONE:
		return "Ads aren't available on this device."
	if watched_today >= MAX_PER_DAY:
		return "That's all the gifts for today. Come back tomorrow!"
	var wait := cooldown_left()
	if wait > 0.0:
		return "The next gift is on its way (%d:%02d)." % [int(wait) / 60, int(wait) % 60]
	if provider == Provider.ADMOB and _loaded_ad == null:
		if not _loading:
			_request_ad()
		return "Finding an ad... (check your internet connection)"
	return ""


func is_available() -> bool:
	return unavailable_reason() == ""


func cooldown_left() -> float:
	return maxf(COOLDOWN - (Time.get_ticks_msec() - _last_shown_msec) / 1000.0, 0.0)


func remaining_today() -> int:
	_roll_day()
	return maxi(MAX_PER_DAY - watched_today, 0)


## Shows an ad; `reward_granted` fires only if it's watched to the end.
func show_for(reward_id: StringName) -> void:
	var reason := unavailable_reason()
	if reason != "":
		ad_failed.emit(reason)
		return
	_pending_reward = reward_id
	_earned = false
	_last_shown_msec = Time.get_ticks_msec()
	Voices.stop()
	match provider:
		Provider.ADMOB:
			_show_admob()
		Provider.SIMULATED:
			_show_simulated()


func _finish(watched: bool) -> void:
	get_tree().paused = false
	if watched and _pending_reward != &"":
		watched_today += 1
		_save_counts()
		var reward := _pending_reward
		_pending_reward = &""
		reward_granted.emit(reward)
	else:
		_pending_reward = &""
		ad_failed.emit("The ad was closed early, so no gift this time.")
	availability_changed.emit()


# --- AdMob ------------------------------------------------------------------------

func _request_ad() -> void:
	if _loading or provider != Provider.ADMOB:
		return
	_loading = true
	var callback = _api("listeners/RewardedAdLoadCallback").new()
	callback.on_ad_loaded = func(ad):
		_loading = false
		_loaded_ad = ad
		availability_changed.emit()
	callback.on_ad_failed_to_load = func(error):
		_loading = false
		_loaded_ad = null
		push_warning("Rewarded ad failed to load: %s" % (error.message if error else "unknown"))
		# Try again in a minute.
		get_tree().create_timer(60.0, true).timeout.connect(_request_ad)
	_api("RewardedAdLoader").new().load(REWARDED_UNIT_ID_ANDROID, _api("core/AdRequest").new(), callback)


func _show_admob() -> void:
	var ad = _loaded_ad
	_loaded_ad = null
	var content = _api("listeners/FullScreenContentCallback").new()
	content.on_ad_dismissed_full_screen_content = func():
		ad.destroy()
		_finish(_earned)
		_request_ad()
	content.on_ad_failed_to_show_full_screen_content = func(_error):
		ad.destroy()
		_last_shown_msec = -10000000
		get_tree().paused = false
		_pending_reward = &""
		ad_failed.emit("The ad couldn't be shown. Try again in a moment.")
		_request_ad()
	ad.full_screen_content_callback = content
	var listener = _api("listeners/OnUserEarnedRewardListener").new()
	listener.on_user_earned_reward = func(_item):
		_earned = true
	get_tree().paused = true
	ad.show(listener)


static func _api(script_name: String) -> Script:
	return load(ADMOB_API + script_name + ".gd")


# --- Simulated ad (desktop and debug builds) -------------------------------------

func _show_simulated() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 100
	_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_overlay)
	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.05, 0.08, 0.96)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(shade)
	var label := UiTheme.label("Advertisement\n(test ad: on a phone, a real video plays here)", 30)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_overlay.add_child(label)
	get_tree().paused = true
	get_tree().create_timer(SIMULATED_AD_SECONDS, true, false, true).timeout.connect(func():
		_overlay.queue_free()
		_overlay = null
		_finish(true))


# --- Daily count -----------------------------------------------------------------

func _roll_day() -> void:
	var today := Time.get_date_string_from_system()
	if today != _day_key:
		_day_key = today
		watched_today = 0


func _load_counts() -> void:
	var config := ConfigFile.new()
	_day_key = Time.get_date_string_from_system()
	if config.load(SAVE_PATH) == OK and String(config.get_value("ads", "day", "")) == _day_key:
		watched_today = int(config.get_value("ads", "watched", 0))


func _save_counts() -> void:
	if not persist:
		return
	var config := ConfigFile.new()
	config.set_value("ads", "day", _day_key)
	config.set_value("ads", "watched", watched_today)
	config.save(SAVE_PATH)


## Tests only: start fresh.
func reset_for_tests() -> void:
	persist = false
	watched_today = 0
	_last_shown_msec = -10000000
