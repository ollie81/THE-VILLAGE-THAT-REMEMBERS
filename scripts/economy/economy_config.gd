class_name EconomyConfig
extends RefCounted
## Every Village Credits price and reward in one place, so they can be tuned
## without touching the systems that use them.

## Credits a new village starts with.
const STARTING_CREDITS := 20

## What ordinary play earns.
const EARN := {
	"objective": 10,       # each first-week goal
	"request": 4,          # each villager request
	"woods": 15,           # clearing the west woods of thornlings
	"chest": 8,            # each hidden chest
	"festival_goal": 6,    # each festival goal
	"daily_gift": 3,       # coming back each day
	"discovery": 5,        # each place found for the first time
	"challenge": 5,        # each daily challenge
	"challenges_all": 5,   # bonus for all three of today's challenges
}

## Coming back on consecutive days (on top of the daily gift). Missing a day
## only restarts the count: nothing already earned is ever taken away.
const STREAK_BONUS := {3: 3, 7: 10}
## After a week, every 7th day in a row gives this.
const STREAK_WEEKLY := 10
## Some days are lucky: a small surprise on top (decided by the date, so
## reopening the game can't reroll it). One day in LUCKY_ONE_IN.
const LUCKY_ONE_IN := 6
const LUCKY_CREDITS := 5

## What a resource is worth in credits, for buying missing materials and
## furniture (matches the supply bundles: 10 planks cost 12).
const CREDIT_VALUE := {&"wood": 1.2, &"stone": 1.4, &"herbs": 1.6, &"food": 1.25}


## The credit price of `items` (resource -> amount), rounded up.
static func credits_for(items: Dictionary) -> int:
	var total := 0.0
	for resource in items:
		total += float(CREDIT_VALUE.get(resource, 1.5)) * int(items[resource])
	return int(ceil(total - 0.001))

## Credits for watching one optional rewarded ad (paid only after the ad SDK
## confirms the reward). The daily cap and cooldown are in AdRewards.
const AD_CREDITS := 15

## The Shop: supplies bought with credits.
const SHOP := [
	{"id": "wood_bundle", "name": "Bundle of planks", "items": {&"wood": 10}, "price": 12},
	{"id": "stone_bundle", "name": "Cart of stone", "items": {&"stone": 10}, "price": 14},
	{"id": "seed_pouch", "name": "Seeds and herbs", "items": {&"herbs": 5}, "price": 8},
	{"id": "food_basket", "name": "Basket of food", "items": {&"food": 8}, "price": 10},
	{"id": "builder_crate", "name": "Builder's crate", "items": {&"wood": 20, &"stone": 12}, "price": 36},
]
