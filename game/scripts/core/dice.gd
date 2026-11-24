class_name Dice
extends RefCounted
## Every random number the rules use comes from here, so a game can be replayed
## from its seed and tests stay deterministic. The AI GM never rolls dice: it asks
## the engine for a roll and gets the result back.

const VALID_SIDES := [2, 4, 6, 8, 10, 12, 20, 100]

var rng := RandomNumberGenerator.new()


func _init(seed_value: int = 0) -> void:
	if seed_value == 0:
		rng.randomize()
	else:
		rng.seed = seed_value


## Parses "NdM", "NdM+K" or "NdM-K" (e.g. "2d6+3", "d20").
## Returns {count, sides, modifier}, or {} when the expression is not valid.
static func parse(expr: String) -> Dictionary:
	var re := RegEx.new()
	re.compile("^(\\d*)d(\\d+)(?:([+-])(\\d+))?$")
	var m := re.search(expr.to_lower().replace(" ", ""))
	if m == null:
		return {}
	var count: int = 1 if m.get_string(1).is_empty() else m.get_string(1).to_int()
	var sides: int = m.get_string(2).to_int()
	var modifier: int = 0
	if not m.get_string(4).is_empty():
		modifier = m.get_string(4).to_int()
		if m.get_string(3) == "-":
			modifier = -modifier
	if count < 1 or count > 100 or not (sides in VALID_SIDES):
		return {}
	return {"count": count, "sides": sides, "modifier": modifier}


func roll_die(sides: int) -> int:
	return rng.randi_range(1, sides)


## Rolls a dice expression. Returns {ok, total, rolls, modifier, expr}.
func roll(expr: String) -> Dictionary:
	var spec := Dice.parse(expr)
	if spec.is_empty():
		return {"ok": false, "total": 0, "rolls": [], "modifier": 0, "expr": expr}
	var rolls: Array = []
	var total: int = int(spec["modifier"])
	for i in int(spec["count"]):
		var r := roll_die(int(spec["sides"]))
		rolls.append(r)
		total += r
	return {"ok": true, "total": total, "rolls": rolls, "modifier": spec["modifier"], "expr": expr}


## Rolls a d20. mode: 1 = advantage, -1 = disadvantage, 0 = straight.
## Returns {natural, rolls}.
func d20(mode: int = 0) -> Dictionary:
	var a := roll_die(20)
	if mode == 0:
		return {"natural": a, "rolls": [a]}
	var b := roll_die(20)
	var pick: int = maxi(a, b) if mode > 0 else mini(a, b)
	return {"natural": pick, "rolls": [a, b]}
