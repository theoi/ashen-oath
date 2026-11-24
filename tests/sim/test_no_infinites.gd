extends TestCase
## No universal infinite: whatever a fighter repeats against a dummy, the dummy gets a real
## gap (CombatRules.combo_reset_frames free ticks) within a bounded time.

const F := preload("res://tests/sim/sim_fixtures.gd")
const Action := FighterState.Action
const TICKS := 1500
## combo_max_frames (6 s) plus hitstop, knockdowns and the flip-out itself.
const MAX_PRESSURE := 600


static func _fighters() -> Array[FighterData]:
	var out: Array[FighterData] = [F.test_fighter()]
	for dir in DirAccess.get_directories_at("res://content/fighters"):
		var path := "res://content/fighters/%s/%s.tres" % [dir, dir]
		if ResourceLoader.exists(path):
			out.append(load(path) as FighterData)
	return out


static func _pressured(f: FighterState) -> bool:
	match f.action:
		Action.HITSTUN, Action.AIR_HITSTUN, Action.WALL_SPLAT, Action.COUNTER_STUN, Action.STAGGERED, \
				Action.KNOCKDOWN, Action.GRABBED:
			return true
	return false


## Longest stretch (ticks) in which the dummy never had combo_reset_frames free ticks in a row.
static func _longest_pressure(data: FighterData, pattern: Callable) -> int:
	var sim := F.duel(1.2, 2, data)
	var me := sim.fighter(0)
	var foe := sim.fighter(1)
	var reset := sim.rules.combo_reset_frames
	var free := reset
	var stretch := 0
	var longest := 0
	for t in TICKS:
		var to := Vector2(foe.pos.x - me.pos.x, foe.pos.z - me.pos.z)
		F.step(sim, SimInput.from_vector(pattern.call(t), to.normalized()))
		foe.hp = foe.max_hp
		me.soul = 0
		free = 0 if _pressured(foe) else free + 1
		if free >= reset:
			stretch = 0
		else:
			stretch += 1
			longest = maxi(longest, stretch)
	return longest


func test_held_basic_chain_is_not_an_infinite() -> void:
	for data in _fighters():
		var longest := _longest_pressure(data, func(_t: int) -> int: return SimInput.LIGHT)
		assert_true(longest <= MAX_PRESSURE, "%s: %d ticks without a gap" % [data.id, longest])


func test_basics_and_skills_mashed_are_not_an_infinite() -> void:
	var presses: Array[int] = [SimInput.LIGHT, SimInput.HEAVY]
	presses.append_array(SimInput.SKILLS)
	for data in _fighters():
		var longest := _longest_pressure(data,
				func(t: int) -> int: return SimInput.LIGHT | (presses[(t / 3) % presses.size()] if t % 3 == 0 else 0))
		assert_true(longest <= MAX_PRESSURE, "%s: %d ticks without a gap" % [data.id, longest])
