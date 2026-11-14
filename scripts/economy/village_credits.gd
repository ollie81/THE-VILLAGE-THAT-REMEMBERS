class_name VillageCredits
extends Node
## Village Credits: the one currency, earned by playing (goals, villager
## requests, clearing the woods, chests, festivals, coming back each day) and
## by watching an optional rewarded ad, and spent in the Shop and the Wardrobe.
##
## Every reward carries a token ("objective_2", "request_14", "ad_...") that is
## recorded when paid, so the same reward can never be paid twice. The balance
## is saved with the game alongside a checksum: a save file edited by hand is
## detected and the credits reset rather than trusted. (Everything lives on the
## phone, so this stops casual editing, not a determined cheat.)

signal changed(balance: int)

static var instance: VillageCredits

const SALT := "village-remembers-credits-v1"

var balance: int = 0
var earned: int = 0
var spent: int = 0
## Reward tokens already paid: token -> amount.
var paid: Dictionary = {}
## Things bought or unlocked (wardrobe items): id -> true.
var owned: Dictionary = {}


func _ready() -> void:
	name = "VillageCredits"
	instance = self
	GameState.objective_completed.connect(func(index: int, _title: String): award("objective", "objective_%d" % index, "a goal reached"))
	AdRewards.reward_granted.connect(_on_ad_reward)


func _exit_tree() -> void:
	if instance == self:
		instance = null


## Pays the reward `kind` (a key of EconomyConfig.EARN) once per `token`.
## Safe to call when the credits system isn't running (does nothing).
static func award(kind: String, token: String, reason: String = "") -> int:
	if instance == null:
		return 0
	return instance.earn(int(EconomyConfig.EARN.get(kind, 0)), token, reason)


## Adds `amount` for `token` unless that token was already paid. Returns what
## was added (0 if it was a duplicate).
func earn(amount: int, token: String, reason: String = "") -> int:
	if amount <= 0 or token == "" or paid.has(token):
		return 0
	paid[token] = amount
	balance += amount
	earned += amount
	changed.emit(balance)
	if reason != "":
		GameManager.notify("+%d Village Credits for %s." % [amount, reason])
	return amount


func can_afford(price: int) -> bool:
	return price <= balance


## Takes `price` credits if there are enough. Returns whether it did.
func spend(price: int) -> bool:
	if price < 0 or price > balance:
		return false
	balance -= price
	spent += price
	changed.emit(balance)
	return true


func owns(id: String) -> bool:
	return owned.has(id)


func unlock(id: String) -> void:
	owned[id] = true
	changed.emit(balance)


## Buys a Shop item: takes the credits and adds the supplies.
func buy_supplies(item_id: String) -> bool:
	for item: Dictionary in EconomyConfig.SHOP:
		if String(item["id"]) != item_id:
			continue
		if not spend(int(item["price"])):
			GameManager.notify("Not enough Village Credits (%d needed, you have %d)." % [int(item["price"]), balance])
			return false
		for resource in item["items"]:
			GameState.add(resource, int(item["items"][resource]))
		GameManager.notify("Bought %s (+%s)." % [String(item["name"]).to_lower(), GameState.cost_text(item["items"])])
		Sounds.play("built", null, -6.0)
		return true
	return false


## Credits for an ad only once the ad SDK has confirmed the reward (AdRewards
## emits reward_granted only then), and once per ad.
func _on_ad_reward(reward_id: StringName) -> void:
	if reward_id != &"credits":
		return
	var token := "ad_" + AdRewards.last_reward_token
	if AdRewards.last_reward_token == "":
		push_error("VillageCredits: an ad reward arrived without a token; not paid.")
		return
	if earn(EconomyConfig.AD_CREDITS, token) > 0:
		GameManager.notify("Thanks for watching! +%d Village Credits." % EconomyConfig.AD_CREDITS)


# --- Save -------------------------------------------------------------------------------

func _checksum() -> String:
	var tokens := paid.keys()
	tokens.sort()
	var items := owned.keys()
	items.sort()
	var text := "%d|%d|%d|%s|%s|%s" % [balance, earned, spent, ",".join(tokens), ",".join(items), SALT]
	return text.sha256_text()


func to_dict() -> Dictionary:
	return {"balance": balance, "earned": earned, "spent": spent, "paid": paid.duplicate(), "owned": owned.keys(), "check": _checksum()}


func from_dict(data: Dictionary) -> void:
	paid.clear()
	owned.clear()
	if data.is_empty():
		# A new village, or a save from before credits existed.
		balance = EconomyConfig.STARTING_CREDITS
		earned = balance
		spent = 0
		paid["starting"] = balance
		changed.emit(balance)
		return
	balance = int(data.get("balance", 0))
	earned = int(data.get("earned", 0))
	spent = int(data.get("spent", 0))
	var saved_paid: Dictionary = data.get("paid", {}) if data.get("paid", {}) is Dictionary else {}
	for token in saved_paid:
		paid[String(token)] = int(saved_paid[token])
	var saved_owned: Array = data.get("owned", []) if data.get("owned", []) is Array else []
	for id in saved_owned:
		owned[String(id)] = true
	if String(data.get("check", "")) != _checksum() or balance != earned - spent or balance < 0:
		push_warning("VillageCredits: the saved credits don't match their checksum (edited save?). Credits reset.")
		balance = 0
		earned = 0
		spent = 0
		owned.clear()
	changed.emit(balance)
