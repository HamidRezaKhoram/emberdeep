class_name OfflineProvider
extends GMProvider
## No AI at all: short canned narration so the game is playable (and testable)
## without a network or a model. Also the fallback when another provider fails.

const ROOM_LINES := {
	"entrance hall": "Cold air spills down worn stone steps into a vaulted entrance hall. Doors lead off in every direction.",
	"chamber": "A plain stone chamber, its floor scuffed by old boots.",
	"hall": "A long hall stretches ahead, pillars marching into the gloom.",
	"shrine": "Candle stubs ring a cracked altar. Something was worshipped here once.",
	"crypt": "Niches line the walls, each holding bones wrapped in rotted cloth.",
	"storeroom": "Broken crates and split barrels fill this musty storeroom.",
	"cavern": "The worked stone gives way to a damp natural cavern.",
	"library": "Shelves sag under swollen, mould-spotted books.",
	"barracks": "Rows of rotten bunks. Someone left in a hurry.",
	"well room": "A round well sits in the centre of the room; you hear water far below.",
	"kennel": "Iron rings in the wall and gnawed bones. Something was kept here.",
}


func display_name() -> String:
	return "Offline storyteller"


func request_turn(_system_prompt: String, _messages: Array, _schema: Dictionary, event: Dictionary) -> void:
	var text := ""
	match str(event.get("kind", "")):
		"room_revealed":
			var facts = JSON.parse_string(str(event.get("text", "")).trim_prefix("A new area is revealed: "))
			if typeof(facts) == TYPE_DICTIONARY:
				text = ROOM_LINES.get(str(facts.get("kind", "")), "You step into the unknown.")
				if not facts.get("creatures", []).is_empty():
					text += " You are not alone: " + ", ".join(facts["creatures"]) + "."
			else:
				text = "You step into the unknown."
		"check_result":
			text = "The dice have spoken."
		"combat_over":
			text = "Silence returns. You catch your breath."
		_:
			text = "(The offline storyteller only describes rooms. Pick a Local LLM or Claude in the menu for a real game master.)"
	_finish_json(JSON.stringify({"narration": text, "actions": []}))
