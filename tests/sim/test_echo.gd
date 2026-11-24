extends TestCase
## Move echoes (MoveData.echo_frames): a delayed re-cast from the cast position and aim.

const F := preload("res://tests/sim/sim_fixtures.gd")
const K := preload("res://tests/sim/test_skill_kit.gd")
const Action := FighterState.Action
const T := SimEvent.Type
const QUICK := SimInput.SKILL_3
const BOLT := SimInput.SKILL_5

var sim: Sim
var me: FighterState
var foe: FighterState


## The kit with quick echoing after 30 frames, plus an echoing bolt (projectile) in slot 5.
func _duel(distance: float) -> void:
	var data := K.kit()
	data.moves[5].echo_frames = 30
	var bolt := K._move(&"bolt", MoveData.Kind.ABILITY, 4, 1, 16, null)
	bolt.hitboxes = []
	bolt.echo_frames = 20
	var shot := EffectData.new()
	shot.id = &"shot"
	shot.spawn_frame = 4
	shot.offset = Vector3(0.0, 1.0, 0.5)
	shot.speed = 15.0
	shot.radius = 0.3
	shot.lifetime = 40
	shot.hit = K._hit(60, HitData.Weight.LIGHT)
	bolt.effects = [shot]
	data.moves.append(bolt)
	data.abilities.append(&"bolt")
	sim = F.duel(distance, 2, data)
	me = sim.fighter(0)
	foe = sim.fighter(1)


static func _hits(ticks: Array[Array]) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for events in ticks:
		for e: SimEvent in events:
			if e.type == T.HIT:
				out.append(e)
	return out


func test_echo_recasts_from_the_cast_position_at_half_damage() -> void:
	_duel(1.2)
	var back := SimInput.make(0, 0, -127)
	var ticks := F.play(sim, [QUICK] + F.held(back, 60), [], 60)
	var echo := F.first(ticks, T.ECHO)
	assert_not_null(echo)
	assert_eq(F.tick_of(ticks, T.ECHO), 1)
	assert_eq(echo.amount, 30)
	assert_eq(F.tick_of(ticks, T.ECHO_CAST), 31)
	var hits := _hits(ticks)
	assert_eq(hits.size(), 2)
	assert_eq(hits[0].amount, 50)
	assert_eq(hits[1].amount, 25, "the echo deals 50%")
	assert_eq(hits[1].source, 0)
	assert_eq(hits[1].id, &"quick")
	assert_true(Fx.dist_xz(me.pos, foe.pos) > Fx.m(3.0), "the caster walked away; the echo still hit")
	assert_eq(me.hitstop, 0, "echo hits do not freeze the caster")
	assert_true(sim.state.echoes.is_empty(), "removed once its move is over")


func test_echo_percent_override_and_echoed_effects() -> void:
	_duel(5.0)
	me.echo_percent = 100
	var ticks := F.play(sim, [BOLT], [], 60)
	var hits := _hits(ticks)
	assert_eq(hits.size(), 2, "the bolt and its echo")
	assert_eq(hits[1].amount, hits[0].amount, "100% in a boss phase 2")
	_duel(5.0)
	hits = _hits(F.play(sim, [BOLT], [], 60))
	assert_eq(hits[1].amount, 30, "an echoed projectile deals 50%")


func test_echo_telegraphs_count_down_through_the_delay() -> void:
	_duel(1.2)
	F.play(sim, [QUICK], [], 6)
	var found: SimTelegraph = null
	for t in sim.telegraphs():
		if t.echo:
			found = t
	assert_not_null(found)
	assert_eq(found.frames_to_active, 30 + 3 - 6, "echo frame 1 on tick 31, active on tick 33")
	assert_eq(found.owner, 0)


func test_echoes_survive_rollback() -> void:
	_duel(1.2)
	F.play(sim, [QUICK], [], 10)
	var snap := sim.snapshot()
	var ticks := F.play(sim, [], [], 40)
	var sum := sim.checksum()
	sim.restore(snap)
	var again := F.play(sim, [], [], 40)
	assert_eq(sim.checksum(), sum)
	assert_eq(_hits(again).size(), _hits(ticks).size())
