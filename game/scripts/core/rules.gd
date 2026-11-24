class_name Rules
extends RefCounted
## A small slice of the SRD 5.2.1 core mechanics (see docs/LEGAL.md and docs/DESIGN.md).
## Only what the skeleton needs: ability modifiers, d20 tests, attacks and damage.

const ABILITIES := ["str", "dex", "con", "int", "wis", "cha"]
const ABILITY_NAMES := {
	"str": "Strength", "dex": "Dexterity", "con": "Constitution",
	"int": "Intelligence", "wis": "Wisdom", "cha": "Charisma",
}


static func ability_modifier(score: int) -> int:
	return floori((score - 10) / 2.0)


static func proficiency_bonus(level: int) -> int:
	return 2 + floori((maxi(level, 1) - 1) / 4.0)


## Ability check or saving throw. A natural 20 or 1 has no special effect here
## (in the 2024 rules only attack rolls treat them specially).
static func ability_check(dice: Dice, modifier: int, dc: int, mode: int = 0) -> Dictionary:
	var r := dice.d20(mode)
	var natural: int = int(r["natural"])
	var total: int = natural + modifier
	return {"natural": natural, "modifier": modifier, "total": total, "dc": dc, "success": total >= dc}


## Attack roll against an Armor Class. A natural 20 always hits and is a
## critical hit; a natural 1 always misses.
static func attack_roll(dice: Dice, attack_bonus: int, armor_class: int, mode: int = 0) -> Dictionary:
	var r := dice.d20(mode)
	var natural: int = int(r["natural"])
	var total: int = natural + attack_bonus
	var crit := natural == 20
	var hit := crit or (natural != 1 and total >= armor_class)
	return {"natural": natural, "total": total, "hit": hit, "crit": crit}


## Damage from a dice expression. A critical hit doubles the dice, not the modifier.
static func damage(dice: Dice, expr: String, crit: bool = false) -> int:
	var spec := Dice.parse(expr)
	if spec.is_empty():
		return 0
	var count: int = int(spec["count"]) * (2 if crit else 1)
	var total: int = int(spec["modifier"])
	for i in count:
		total += dice.roll_die(int(spec["sides"]))
	return maxi(total, 0)
