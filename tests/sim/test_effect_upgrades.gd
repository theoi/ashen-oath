extends TestCase
## Effect upgrades: attached aim-turning beams, homing projectiles, teleport-origin spawns.

const F := preload("res://tests/sim/sim_fixtures.gd")
const K := preload("res://tests/sim/test_skill_kit.gd")
const Action := FighterState.Action
const T := SimEvent.Type
const SKILL := SimInput.SKILL_5

var sim: Sim
var me: FighterState
var foe: FighterState


## The kit plus one effect-only skill in slot 5.
func _duel(move: MoveData, foe_x: float, foe_z: float) -> void:
	var data := K.kit()
	move.hitboxes = []
	move.cooldown = 0
	data.moves.append(move)
	data.abilities.append(move.id)
	sim = F.duel(1.2, 2, data)
	me = sim.fighter(0)
	foe = sim.fighter(1)
	F.place(sim, 1, foe_x, foe_z, Fx.HALF_TURN)


static func _effect(id: StringName, damage: int) -> EffectData:
	var ed := EffectData.new()
	ed.id = id
	ed.hit = K._hit(damage, HitData.Weight.TICK)
	ed.hit.hitstun = 4
	ed.hit.knockback = 0.0
	return ed


func _hits(ticks: Array[Array]) -> int:
	return F.count_of(ticks, T.HIT)


func test_attached_beam_reaches_along_its_length_turns_to_the_aim_and_ends_with_the_cast() -> void:
	var torrent := K._move(&"torrent", MoveData.Kind.ABILITY, 5, 1, 60, null)
	var beam := _effect(&"beam", 14)
	beam.spawn_frame = 5
	beam.offset = Vector3(0.0, 1.0, 0.3)
	beam.attach_to_owner = true
	beam.aim_turn_rate = 3.0
	beam.length = 10.0
	beam.radius = 0.6
	beam.lifetime = 300
	beam.hits_per_target = 99
	beam.hit_interval = 8
	beam.destroy_on_contact = false
	beam.projectile = false
	beam.blocked_by_walls = false
	torrent.effects = [beam]
	_duel(torrent, 0.0, 7.0)
	var ticks := F.play(sim, [SKILL], [], 10)
	assert_true(_hits(ticks) >= 1, "7 m away, inside the 10 m beam")
	var e := sim.state.effects[0]
	assert_eq(e.facing, me.facing)
	var right := SimInput.with_aim_direction(0, Vector2(1.0, 0.0))
	F.play(sim, [right, right, right, right, right], [], 5)
	assert_eq(absi(Fx.angle_diff(me.facing, e.facing)), 5 * Fx.deg(3.0), "turned 3° a frame toward the aim")
	var pos := me.pos + Fx.rotate(Fx.v3(beam.offset), e.facing)
	assert_eq(e.pos, pos, "stays on the owner")
	ticks = F.play(sim, [], [], 70)
	assert_ne(F.tick_of(ticks, T.EFFECT_END), -1, "ends when the cast ends, not after its lifetime")
	assert_true(sim.state.effects.is_empty())


func test_homing_lances_curve_into_the_target() -> void:
	var lances := K._move(&"lances", MoveData.Kind.ABILITY, 3, 1, 20, null)
	var lance := _effect(&"lance", 20)
	lance.spawn_frame = 3
	lance.offset = Vector3(0.0, 1.0, 0.5)
	lance.speed = 12.0
	lance.count = 3
	lance.spread_degrees = 90.0
	lance.lifetime = 90
	lance.radius = 0.3
	lances.effects = [lance]
	_duel(lances, 0.0, 6.0)
	var straight := _hits(F.play(sim, [SKILL], [], 60))
	assert_eq(straight, 1, "without homing only the middle lance hits")
	lance.homing_turn_rate = 6.0
	_duel(lances, 0.0, 6.0)
	assert_eq(_hits(F.play(sim, [SKILL], [], 60)), 3, "all three curve in")


func test_teleport_origin_effect_spawns_where_the_blink_started() -> void:
	var step := K._move(&"wraithstep", MoveData.Kind.ABILITY, 3, 1, 12, null)
	step.teleport = TeleportData.new()
	step.teleport.frame = 3
	step.teleport.mode = TeleportData.Mode.FORWARD
	step.teleport.distance = 4.0
	var echo := _effect(&"grave_echo", 30)
	echo.spawn_frame = 3
	echo.anchor = EffectData.Anchor.TELEPORT_ORIGIN
	echo.offset = Vector3.ZERO
	echo.radius = 1.0
	echo.lifetime = 10
	echo.projectile = false
	step.effects = [echo]
	_duel(step, 0.0, -1.0)
	var start := me.pos
	var ticks := F.play(sim, [SKILL], [], 8)
	assert_eq(me.teleport_from, start)
	var spawn := F.first(ticks, T.EFFECT_SPAWN)
	assert_not_null(spawn)
	assert_eq(spawn.position, start)
	assert_ne(me.pos, start)
	var hit := F.first(ticks, T.HIT)
	assert_not_null(hit, "the foe behind the start point is hit")
	assert_eq(hit.id, &"wraithstep")
