extends TestCase
## The CPU on a skill-kit fighter (Aldric, design-lost-ark §4 and §5.6): it reads the six
## skill slots and their combo/chain parts, presses only the skill-kit buttons, aims every
## frame, fires ⚡Counter skills into counter windows and plays a clean mirror.

const F := preload("res://tests/sim/sim_fixtures.gd")
const T := SimEvent.Type
const ALDRIC := "res://content/fighters/aldric/aldric.tres"


func test_move_book_reads_the_six_slots_and_their_parts() -> void:
	var book := AiMoveBook.new(load(ALDRIC))
	assert_eq(book.abilities.size(), 6)
	for slot in 6:
		assert_eq(book.abilities[slot].button, SimInput.SKILLS[slot], "slot %d button" % slot)
	assert_true(book.abilities[0].has(AiMoveBook.TAG_COUNTER), "the lunge is a ⚡Counter")
	var rise := book.abilities[1]
	assert_eq(rise.follow.move.id, &"brand_rise_slam")
	assert_true(rise.follow.part and rise.follow.button == SimInput.SKILLS[1], "the slam is cast from E")
	var rend := book.abilities[2]
	assert_true(rend.follow.has(AiMoveBook.TAG_MARK_HIT), "Rend Ignition hits marked enemies")
	assert_true(book.abilities[3].stance, "Bulwark is a stance")
	assert_true(book.abilities[5].charged, "Verdict charges")


func test_counter_window_draws_a_counter_skill() -> void:
	var cfg := F.config(2, load(ALDRIC))
	var sim := F.fighting_sim(cfg)
	F.place(sim, 0, 0.0, 0.0, 0)
	F.place(sim, 1, 0.0, 5.0, Fx.HALF_TURN)
	var ai := AiInputSource.new(AiDifficulty.preset(AiDifficulty.Level.NIGHTMARE))
	var stunned := false
	# Slot 1 charges Verdict: its counter window lasts the whole charge.
	for _t in 70:
		for e in F.step(sim, ai.next_frame(sim, 0), SimInput.SKILL_6):
			if e.type == T.COUNTER_STUN and e.target == 1:
				stunned = true
		if stunned:
			break
	assert_true(stunned, "Nightmare fires a ⚡Counter skill into the charge")
	assert_eq(int(ai.counters.get("counter_fires", 0)), 1)


func test_mirror_presses_only_kit_buttons_aims_and_uses_the_kit() -> void:
	var forbidden := 0
	var fight_frames := 0
	var aimed := 0
	var dashes := 0
	var parts := 0
	var perfect := 0
	for seed_value: int in [1, 2]:
		var cfg := SimConfig.new()
		cfg.rules = load("res://content/rules/default_rules.tres")
		cfg.arena = load("res://content/arenas/ashen_chapel.tres")
		cfg.seed = seed_value
		cfg.rounds_to_win = 1
		for team in 2:
			var slot := SlotConfig.new()
			slot.fighter = load(ALDRIC)
			slot.team = team
			cfg.slots.append(slot)
		var sources: Array[AiInputSource] = [
			AiInputSource.new(AiDifficulty.preset(AiDifficulty.Level.NIGHTMARE)),
			AiInputSource.new(AiDifficulty.preset(AiDifficulty.Level.HARD)),
		]
		var sim := Sim.new(cfg)
		var inputs := PackedInt64Array([0, 0])
		while not sim.is_over() and sim.state.tick < 6000:
			for slot in 2:
				inputs[slot] = sources[slot].next_frame(sim, slot)
				if sim.state.phase == SimState.Phase.FIGHT and not sim.fighter(slot).ko:
					fight_frames += 1
					if SimInput.has_aim(inputs[slot]):
						aimed += 1
				if SimInput.buttons_of(inputs[slot]) & AiInputSource.KIT_UNUSED:
					forbidden += 1
			for e in sim.step(inputs):
				if e.type == T.DASH:
					dashes += 1
				elif e.type == T.MOVE_START and (e.id == &"brand_rise_slam" or e.id == &"rend_ignition"):
					parts += 1
		assert_true(sim.is_over(), "seed %d finishes" % seed_value)
		perfect += int(sources[0].counters.get("perfect_charges", 0))
	assert_eq(forbidden, 0, "no guard, heavy, grab or jump presses")
	assert_eq(aimed, fight_frames, "every fight frame carries an aim")
	assert_true(dashes > 0, "dashes: %d" % dashes)
	assert_true(parts > 0, "combo and chain parts: %d" % parts)
	assert_true(perfect > 0, "Nightmare lands perfect Verdict charges")
