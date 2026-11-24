extends FighterTrait
## Test trait: records hits taken in vars (0 total damage, 1 armored hits, 2 attacker slot + 1).


func on_hit_taken(_sim: Sim, victim: FighterState, attacker: FighterState, _move: MoveData,
		_hit: HitData, damage: int, armored: bool) -> void:
	victim.vars[0] += damage
	if armored:
		victim.vars[1] += 1
	victim.vars[2] = attacker.slot + 1 if attacker != null else 0
