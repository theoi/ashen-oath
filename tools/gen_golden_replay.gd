extends SceneTree
## Records the golden replay used by tests/sim/test_golden_replay.gd: a DebugBot brawl with
## the test fighter on the training arena, with a checksum per tick. Regenerate only when a
## sim or test fighter change is meant to change outcomes, and say so in the PR.
##
##   godot --headless --path . -s "$PWD/tools/gen_golden_replay.gd"

const OUT := "res://tests/sim/golden/bot_brawl.res"
const TICKS := 1800


func _init() -> void:
	var config := SimConfig.new()
	config.rules = load("res://content/rules/default_rules.tres")
	config.arena = load("res://content/arenas/training_arena.tres")
	config.seed = 1234
	config.round_seconds = 20
	for i in 3:
		var slot := SlotConfig.new()
		slot.fighter = load("res://content/test_fighter/test_fighter.tres")
		slot.team = mini(i, 1)
		slot.start_soul = 50
		config.slots.append(slot)
	var sim := Sim.new(config)
	var replay := Replay.create(config)
	var bots: Array[DebugBot] = [DebugBot.new(5), DebugBot.new(6), DebugBot.new(7)]
	var hits := 0
	for _t in TICKS:
		var inputs := PackedInt64Array()
		for slot in 3:
			inputs.append(bots[slot].next_frame(sim, slot))
		for e in sim.step(inputs):
			if e.type == SimEvent.Type.HIT:
				hits += 1
		replay.record(inputs, sim.checksum(), true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	var err := ResourceSaver.save(replay, OUT)
	print("saved %s: %s, %d ticks, %d hits, final checksum %x" % [OUT, error_string(err), TICKS, hits, sim.checksum()])
	quit(0 if err == OK else 1)
