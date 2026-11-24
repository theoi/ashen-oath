class_name Roster
extends RefCounted
## Display data for the versus select screens: fighters and arenas by content id.
##
## Gameplay data (stats, moves) lives in content/; this table holds what the menus show and
## where each fighter's FighterData and each arena's ArenaData / scene live ("data", "scene").
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
]

const ARENAS: Array[Dictionary] = [
	{"id": &"ashen_chapel", "data": "res://content/arenas/ashen_chapel.tres", "scene": "res://presentation/arenas/ashen_chapel/ashen_chapel.tscn", "name": "Ashen Chapel", "blurb": "A burned cathedral nave under falling ash. No hazards."},
	{"id": &"ashen_chapel_night", "data": "res://content/arenas/ashen_chapel.tres", "scene": "res://presentation/arenas/ashen_chapel/ashen_chapel_night.tscn", "name": "Ashen Chapel · Night", "blurb": "The chapel after dark, thick with embers. No hazards."},
	{"id": &"drowned_crypt", "data": "res://content/arenas/drowned_crypt.tres", "scene": "res://presentation/arenas/drowned_crypt/drowned_crypt.tscn", "name": "Drowned Crypt", "blurb": "Black water and iron grates. Grave vents erupt in spectral fire every 12 s."},
	{"id": &"drowned_crypt_depths", "data": "res://content/arenas/drowned_crypt_depths.tres", "scene": "res://presentation/arenas/drowned_crypt/drowned_crypt_depths.tscn", "name": "Drowned Crypt · Depths", "blurb": "The crypt's deepest hall, lit by drowned souls. Grave vents."},
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
