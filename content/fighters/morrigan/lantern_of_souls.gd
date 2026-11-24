extends FighterTrait
## Morrigan's Lantern of Souls: each ability hit stores a soul (max 3, vars[0]). Her next
## Soul Lance fires the stored souls as shards fanned around the bolt and empties the
## lantern. Shard hits do not store souls.

const SOULS := 0
const MAX_SOULS := 3
const SPREAD_DEGREES := 14.0
const LANCE := &"soul_lance"
const SHARD_EFFECT := 1


func on_round_start(_sim: Sim, fighter: FighterState) -> void:
	fighter.vars[SOULS] = 0


func on_hit_dealt(_sim: Sim, attacker: FighterState, _victim: FighterState, move: MoveData,
		hit: HitData, blocked: bool) -> void:
	if blocked or move == null or move.kind != MoveData.Kind.ABILITY:
		return
	if move.id == LANCE and move.effects.size() > SHARD_EFFECT and hit == move.effects[SHARD_EFFECT].hit:
		return
	attacker.vars[SOULS] = mini(MAX_SOULS, attacker.vars[SOULS] + 1)


func on_effects_spawned(sim: Sim, fighter: FighterState, move: MoveData, effect_index: int,
		spawned: Array[EffectState]) -> void:
	if move.id != LANCE or effect_index != 0 or spawned.is_empty() or fighter.vars[SOULS] <= 0:
		return
	var souls := fighter.vars[SOULS]
	fighter.vars[SOULS] = 0
	var bolt := spawned[0]
	var step := Fx.deg(SPREAD_DEGREES)
	for k in souls:
		# Alternate sides: +1, -1, +2 steps.
		var side := (k / 2 + 1) * (1 if k % 2 == 0 else -1)
		sim.spawn_effect(fighter, fighter.move_index, SHARD_EFFECT, bolt.pos, bolt.facing + side * step)
