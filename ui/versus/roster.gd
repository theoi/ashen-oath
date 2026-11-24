class_name Roster
extends RefCounted
## Display data for the versus select screens: fighters and arenas by content id.
##
## Gameplay data (stats, moves) lives in content/; this table holds what the menus show and
## where each fighter's FighterData and each arena's ArenaData live ("data"; the arena's
## presentation scene comes from ArenaData.scene).
## MatchSetup falls back to stand-ins while those files do not exist yet.

const FIGHTERS: Array[Dictionary] = [
	{
		"id": &"aldric",
		"data": "res://content/fighters/aldric/aldric.tres",
		"name": "Aldric Vane",
		"epithet": "The Oathbreaker",
		"style": "All-rounder · best at punishing",
		"abilities": ["Oathfire Lunge", "Brand Rise", "Bulwark Charge"],
		"super": "Pyre of the Forsworn",
		"trait": "Oathkeeper: wider parry; a parry ignites his blade.",
		"color": Color(0.93, 0.5, 0.2),
	},
	{
		"id": &"morrigan",
		"data": "res://content/fighters/morrigan/morrigan.tres",
		"name": "Morrigan",
		"epithet": "The Grave-Witch",
		"style": "Zoner · controls space, weak up close",
		"abilities": ["Soul Lance", "Grave Grasp", "Wraithstep"],
		"super": "Requiem of the Drowned",
		"trait": "Lantern of Souls: ability hits store souls for her next Soul Lance.",
		"color": Color(0.52, 0.9, 0.78),
	},
	{
		"id": &"gorrath",
		"data": "res://content/fighters/gorrath/gorrath.tres",
		"name": "Gorrath",
		"epithet": "The Chainbound",
		"style": "Grappler · slow, armored, hits like a cart",
		"abilities": ["Chain Hook", "Earthsplitter", "Bull Rush"],
		"super": "Execution Chain",
		"trait": "Unbroken: his heavies shrug off one hit.",
		"color": Color(0.78, 0.72, 0.66),
	},
	{
		"id": &"hollowed",
		"data": "res://content/fighters/hollowed/hollowed.tres",
		"name": "Hollowed",
		"epithet": "The Lost",
		"style": "Story opponent · a soldier of Vael, hollowed by the Oath",
		"abilities": [],
		"super": "",
		"trait": "No abilities or super: blade strings, a grab and nothing left to lose.",
		"color": Color(0.55, 0.75, 0.9),
	},
	{
		"id": &"oath_shade",
		"data": "res://content/fighters/oath_shade/oath_shade.tres",
		"name": "Oath-Shade",
		"epithet": "The Broken Vow",
		"style": "Story opponent · Aldric's own curse, wearing his face",
		"abilities": ["Oathfire Lunge", "Brand Rise", "Bulwark Charge"],
		"super": "Pyre of the Forsworn",
		"trait": "Oathkeeper: wider parry; a parry ignites its blade.",
		"color": Color(0.85, 0.3, 0.12),
	},
]

const ARENAS: Array[Dictionary] = [
	{"id": &"ashen_chapel", "data": "res://content/arenas/ashen_chapel.tres", "name": "Ashen Chapel", "blurb": "A burned cathedral nave under falling ash. No hazards."},
	{"id": &"ashen_chapel_night", "data": "res://content/arenas/ashen_chapel_night.tres", "name": "Ashen Chapel · Night", "blurb": "The chapel after dark, thick with embers. No hazards."},
	{"id": &"drowned_crypt", "data": "res://content/arenas/drowned_crypt.tres", "name": "Drowned Crypt", "blurb": "Black water and iron grates. Grave vents erupt in spectral fire every 12 s."},
	{"id": &"drowned_crypt_depths", "data": "res://content/arenas/drowned_crypt_depths.tres", "name": "Drowned Crypt · Depths", "blurb": "The crypt's deepest hall, lit by drowned souls. Grave vents."},
]


static func fighter(id: StringName) -> Dictionary:
	for entry in FIGHTERS:
		if entry["id"] == id:
			return entry
	return {"id": id, "name": String(id).capitalize(), "epithet": "", "style": "", "abilities": [],
			"super": "", "trait": "", "color": Palette.BONE}


static func ability_names(id: StringName) -> PackedStringArray:
	return PackedStringArray(fighter(id)["abilities"])


static func fighter_name(id: StringName) -> String:
	return fighter(id)["name"]


static func arena(id: StringName) -> Dictionary:
	for entry in ARENAS:
		if entry["id"] == id:
			return entry
	return {"id": id, "name": String(id).capitalize(), "blurb": ""}


static func fighter_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for entry in FIGHTERS:
		ids.append(entry["id"])
	return ids
