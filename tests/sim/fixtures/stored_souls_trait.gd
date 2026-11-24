extends FighterTrait
## Test trait in the style of Morrigan's Lantern of Souls: ability hits store a soul (max 3);
## the next bolt also fires the stored souls in a spread.

const SOULS := 0


func on_hit_dealt(_sim: Sim, attacker: FighterState, _victim: FighterState, move: MoveData,
		_hit: HitData, blocked: bool) -> void:
	if move.kind == MoveData.Kind.ABILITY and move.id != &"bolt" and not blocked:
		attacker.vars[SOULS] = mini(3, attacker.vars[SOULS] + 1)


func on_effects_spawned(sim: Sim, fighter: FighterState, move: MoveData, effect_index: int,
		spawned: Array[EffectState]) -> void:
	if move.id != &"bolt" or fighter.vars[SOULS] == 0:
		return
	var origin := spawned[0]
	for i in fighter.vars[SOULS]:
		var side := (i / 2 + 1) * Fx.deg(12.0) * (1 if i % 2 == 0 else -1)
		sim.spawn_effect(fighter, fighter.move_index, effect_index, origin.pos, origin.facing + side)
	fighter.vars[SOULS] = 0
