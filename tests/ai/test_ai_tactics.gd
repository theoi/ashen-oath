extends TestCase
## Tactics and reactions use the fighter's MoveData: the CPU punishes a whiffed heavy before
## it recovers, and is not hit by a slow heavy thrown at it (it blocks, parries, dodges or
## interrupts the startup).

const F := preload("res://tests/sim/sim_fixtures.gd")
const SEEDS := 10


func _duel(seed_value: int, distance: float) -> Sim:
	var cfg := F.config(2, F.test_fighter())
	cfg.seed = seed_value
	var sim := F.fighting_sim(cfg)
	F.place(sim, 0, 0.0, 0.0, 0)
	F.place(sim, 1, 0.0, distance, Fx.HALF_TURN)
	return sim


## Slot 0 whiffs heavy_1 from 2.6 m; true if the CPU (slot 1) hits it during the recovery.
func _punishes(level: int, seed_value: int) -> bool:
	var sim := _duel(seed_value, 2.6)
	var whiffer := sim.fighter(0)
	sim.start_move(whiffer, sim.fighter_data[0].find_move(&"heavy_1"))
	var move := sim.current_move(whiffer)
	while whiffer.action == FighterState.Action.ATTACK and whiffer.move_frame <= move.last_active_frame():
		F.step(sim)
	var ai := AiInputSource.new(AiDifficulty.preset(level))
	while whiffer.action == FighterState.Action.ATTACK:
		for e in F.step(sim, 0, ai.next_frame(sim, 1)):
			if e.type == SimEvent.Type.HIT and e.source == 1:
				return true
	return false


## Slot 0 throws heavy_2 (startup 22) from 1.3 m; true if it never hits the CPU.
func _survives_slow_heavy(level: int, seed_value: int) -> bool:
	var sim := _duel(seed_value, 1.3)
	var attacker := sim.fighter(0)
	var ai := AiInputSource.new(AiDifficulty.preset(level))
	sim.start_move(attacker, sim.fighter_data[0].find_move(&"heavy_2"))
	for _t in 60:
		for e in F.step(sim, 0, ai.next_frame(sim, 1)):
			if e.type == SimEvent.Type.HIT and e.source == 0:
				return false
	return true


func test_hard_and_nightmare_punish_a_whiffed_heavy() -> void:
	for level: int in [AiDifficulty.Level.HARD, AiDifficulty.Level.NIGHTMARE]:
		var count := 0
		for s in SEEDS:
			if _punishes(level, s + 1):
				count += 1
		assert_eq(count, SEEDS, "level %d punished %d of %d" % [level, count, SEEDS])


func test_hard_and_nightmare_are_not_hit_by_a_slow_heavy() -> void:
	for level: int in [AiDifficulty.Level.HARD, AiDifficulty.Level.NIGHTMARE]:
		var count := 0
		for s in SEEDS:
			if _survives_slow_heavy(level, s + 1):
				count += 1
		assert_eq(count, SEEDS, "level %d avoided it %d of %d times" % [level, count, SEEDS])


func test_move_book_reads_move_data() -> void:
	var book := AiMoveBook.new(F.test_fighter())
	assert_eq(book.light.hit_frame, 6)
	assert_eq(book.light.on_block, -2, "6/2/12 light with 11 blockstun is -2 on block")
	assert_true(book.abilities[0].has(AiMoveBook.TAG_GAP_CLOSER), "dash strike closes gaps")
	assert_true(book.abilities[0].has(AiMoveBook.TAG_ARMOR))
	assert_true(book.abilities[1].has(AiMoveBook.TAG_LAUNCH) and book.abilities[1].has(AiMoveBook.TAG_JUMP_CANCEL))
	assert_true(book.abilities[2].has(AiMoveBook.TAG_PROJECTILE))
	assert_true(book.abilities[2].reach > Fx.m(15.0), "the bolt reaches across the arena")
	assert_true(book.grab.has(AiMoveBook.TAG_THROW))


func test_profiles_resolve_by_fighter_id() -> void:
	var data := FighterData.new()
	data.id = &"morrigan"
	assert_eq(AiProfile.for_fighter(data).id, &"morrigan")
	data.id = &"nobody"
	assert_eq(AiProfile.for_fighter(data).id, &"default")
	assert_eq(AiProfile.by_id(&"oath_shade").id, &"oath_shade")
