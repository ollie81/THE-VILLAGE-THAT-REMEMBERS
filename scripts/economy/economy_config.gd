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
}

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
