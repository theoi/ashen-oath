extends Node
## Dev view of the in-fight HUD over the Ashen Chapel with a mid-fight 1v2 state (cooldowns
## running, damage taken, Soul at Burst and Super). For screenshots of HUD states the
## simulation cannot reach yet:
##   SCENE=res://tests/ui/hud_preview.tscn tools/capture_screenshot.sh /tmp/hud.png 60

const ARENA := "res://presentation/arenas/ashen_chapel/ashen_chapel.tscn"


func _ready() -> void:
	var arena: Node3D = load(ARENA).instantiate()
	add_child(arena)
	var camera := Camera3D.new()
	camera.fov = 60.0
	add_child(camera)
	camera.position = Vector3(-6.0, 3.0, 2.5)
	camera.look_at(Vector3(2.0, 1.0, 0.0))
	camera.make_current()
	var layer := CanvasLayer.new()
	add_child(layer)
	var hud := Hud.new()
	layer.add_child(hud)

	var state := HudState.new()
	state.round_number = 2
	state.round_wins = [1, 0]
	state.seconds_left = 47.0
	var rows: Array[Array] = [
		["Aldric Vane", 0, 640.0, 1000.0, 58.0, 72.0, [0.0, 2.4, 5.1], PackedStringArray(["Oathfire Lunge", "Brand Rise", "Bulwark Charge"])],
		["Morrigan", 1, 310.0, 900.0, 100.0, 40.0, [0.0, 0.0, 0.0], PackedStringArray()],
		["Gorrath", 1, 900.0, 1150.0, 24.0, 18.0, [0.0, 0.0, 0.0], PackedStringArray()],
	]
	for slot in rows.size():
		var row := rows[slot]
		var fighter := HudState.Fighter.new()
		fighter.slot = slot
		fighter.name = row[0]
		fighter.team = row[1]
		fighter.health = row[2]
		fighter.max_health = row[3]
		fighter.soul = row[4]
		fighter.guard = row[5]
		fighter.guard_broken = slot == 2
		fighter.is_player = slot == 0
		fighter.cooldown_left.assign(row[6])
		fighter.cooldown_total = [5.0, 4.0, 6.0]
		fighter.ability_names = row[7]
		state.fighters.append(fighter)
	hud.apply(state)
	hud.on_event({"type": MatchEvents.PARRY, "slot": 0})
	hud.on_event({"type": MatchEvents.GUARD_BREAK, "slot": 2})
	hud.announce("Counter", "Aldric breaks Gorrath's guard", 30.0)
