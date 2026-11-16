extends Node
## Developer tool: every tab of the Village Shop (with the test banner at the
## bottom, as on a phone) and the simulated rewarded ad.
## Run: godot --path . --resolution 1612x720 res://tools/shop_screenshots.tscn -- --out=/some/dir
var _out := "user://screenshots"
var _main

func _ready() -> void:
	SaveService.enabled = false
	PopulationDirector.auto_arrivals = false
	DailyGift.persist = false
	AdRewards.reset_for_tests()
	GameState.reset()
	GameSettings.touch_mode = 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()

func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("saved ", name)

func _run() -> void:
	WorldClock.set_time(10.0)
	WorldClock.set_time_scale(0.0)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _wait(60)
	for tip in _main.find_children("TutorialTips", "", true, false):
		tip.visible = false
		tip.set_process(false)
	VillageCredits.instance.earn(80, "screenshot", "")
	CreditRewards.instance.discover("windmill")
	CreditRewards.instance.discover("pond")
	var shop := ShopPanel.instance
	var i := 1
	for t in ShopPanel.TABS:
		shop.open_shop(t[0])
		await _wait(12)
		await _shot("%d_shop_%s" % [i, t[0]])
		i += 1
	shop.show_tab("earn")
	await _wait(5)
	shop._ad_button.pressed.emit()
	await _wait(2)
	await _shot("%d_simulated_ad" % i)
	await get_tree().create_timer(AdRewards.SIMULATED_AD_SECONDS + 0.5, true, false, true).timeout
	await _wait(10)
	await _shot("%d_after_ad" % (i + 1))
	get_tree().quit()
