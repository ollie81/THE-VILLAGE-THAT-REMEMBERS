class_name AdConfig
extends RefCounted
## Every AdMob setting in one place.
##
## Test ads: debug builds ALWAYS use Google's official test ad units (they pay
## nothing and are safe to tap while developing). Release builds use your own
## ad units if they're supplied, and test units otherwise.
##
## Your real IDs are never written into the code. The build fills
## res://config/admob.cfg from GitHub secrets (ADMOB_APP_ID,
## ADMOB_REWARDED_ID, ADMOB_INTERSTITIAL_ID, ADMOB_BANNER_ID); that file is not
## committed. The App ID also goes into the Android manifest at export (see
## addons/admob/android/config.gd).

## Google's official test ad units (https://developers.google.com/admob/android/test-ads).
const TEST_APP_ID := "ca-app-pub-3940256099942544~3347511713"
const TEST_REWARDED := "ca-app-pub-3940256099942544/5224354917"
const TEST_INTERSTITIAL := "ca-app-pub-3940256099942544/1033173712"
const TEST_BANNER := "ca-app-pub-3940256099942544/6300978111"

const CONFIG_PATH := "res://config/admob.cfg"

## Who the game is for. The Village That Remembers is a general-audience game
## (not made for children), so ads aren't tagged as child-directed. If you
## ever list it in Google Play's Families programme, set CHILD_DIRECTED to
## true in res://config/admob.cfg ([audience] child_directed=true): ads are
## then limited to Families-certified, non-personalised ones rated G.
const DEFAULT_MAX_RATING := "PG"

static var _cache: ConfigFile = null


static func _config() -> ConfigFile:
	if _cache == null:
		_cache = ConfigFile.new()
		if FileAccess.file_exists(CONFIG_PATH):
			_cache.load(CONFIG_PATH)
	return _cache


## The unit for `kind` ("rewarded", "interstitial", "banner"): test units in
## debug builds or when no real one is configured.
static func unit_id(kind: String, debug_build: bool = OS.is_debug_build()) -> String:
	var test: String = {"rewarded": TEST_REWARDED, "interstitial": TEST_INTERSTITIAL, "banner": TEST_BANNER}.get(kind, "")
	if debug_build:
		return test
	var real := String(_config().get_value("units", kind, "")).strip_edges()
	return real if is_real_id(real) else test


## Whether real (production) ad units are configured for release builds.
static func has_production_ids() -> bool:
	for kind in ["rewarded", "interstitial", "banner"]:
		if not is_real_id(String(_config().get_value("units", kind, ""))):
			return false
	return true


## A plausible AdMob ad unit ID that isn't one of Google's test units.
static func is_real_id(id: String) -> bool:
	return id.begins_with("ca-app-pub-") and "/" in id and not id.begins_with("ca-app-pub-3940256099942544")


static func child_directed() -> bool:
	return bool(_config().get_value("audience", "child_directed", false))


static func max_rating() -> String:
	return "G" if child_directed() else String(_config().get_value("audience", "max_rating", DEFAULT_MAX_RATING))
