extends TestCase
## Every skill and awakening of every fighter (and the test fighter) becomes active on its
## data's startup frame in the sim, and aimed moves face the aim on frame 1.

const F := preload("res://tests/sim/sim_fixtures.gd")
const FIGHTERS := "res://content/fighters"


static func _fighters() -> Array[FighterData]:
	var out: Array[FighterData] = [F.test_fighter()]
	for dir in DirAccess.get_directories_at(FIGHTERS):
		for file in DirAccess.get_files_at(FIGHTERS.path_join(dir)):
			if file.ends_with(".tres"):
				var data := load(FIGHTERS.path_join(dir).path_join(file)) as FighterData
				if data != null:
					out.append(data)
	return out


## Slot buttons and move ids of a fighter's skills and awakening.
static func _skills(data: FighterData) -> Dictionary[int, StringName]:
	var out: Dictionary[int, StringName] = {}
	for i in mini(data.abilities.size(), SimInput.SKILLS.size()):
		out[SimInput.SKILLS[i]] = data.abilities[i]
	if data.super_move != &"":
		out[SimInput.AWAKEN] = data.super_move
	return out


## First move frame on which the move has a live hitbox or spawns an effect, or -1.
static func _first_active(data: FighterData, bit: int, move_id: StringName) -> Dictionary:
	var sim := F.fighting_sim(F.config(2, data))
	F.place(sim, 0, 0.0, -8.0, 0)
	F.place(sim, 1, 0.0, 7.0, Fx.HALF_TURN)
	var f := sim.fighter(0)
	f.soul = 10000
	var index := data.find_move(move_id)
	var move := data.moves[index]
	var frame := SimInput.with_aim_point(bit, Vector2(0.0, 5.0))
	var result := {"started": false, "first": -1, "facing": -1}
	for t in 240:
		var events := F.step(sim, frame if t == 0 else 0)
		if f.action != FighterState.Action.ATTACK or f.move_index != index:
			if result["started"]:
				break
			continue
		if not result["started"]:
			result["started"] = true
			result["facing"] = f.facing
		var live := false
		for hb in move.hitboxes:
			if hb.hit != null and Sim.hitbox_active(move, hb, f.move_frame):
				live = true
		for e in events:
			if e.type == SimEvent.Type.EFFECT_SPAWN and e.source == 0:
				live = true
		if live:
			result["first"] = f.move_frame
			break
	return result


func test_every_skill_starts_on_its_startup_frame() -> void:
	var checked := 0
	for data in _fighters():
		for bit: int in _skills(data):
			var move_id: StringName = _skills(data)[bit]
			var move := data.move_by_id(move_id)
			if move == null or (move.hitboxes.is_empty() and move.effects.is_empty()):
				continue
			var result := _first_active(data, bit, move_id)
			var label := "%s %s" % [data.id, move_id]
			assert_true(result["started"], "%s starts" % label)
			if not result["started"]:
				continue
			assert_eq(result["first"], move.startup, "%s: first active frame = startup" % label)
			if move.is_aimed():
				assert_eq(result["facing"], 0, "%s faces the aim on frame 1" % label)
			checked += 1
	assert_true(checked >= 10, "checked %d skills" % checked)
