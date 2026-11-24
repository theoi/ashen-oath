class_name FighterTrait
extends RefCounted
## Script hook for fighter traits that move data cannot express (stored charges, custom
## reactions). Set FighterData.trait_script to a script extending this.
##
## A trait instance is stateless and shared across rollbacks: keep all state in
## FighterState.vars (8 ints) or buffs, so snapshots capture it. Hooks must be deterministic:
## no wall-clock time, no global RNG (use sim.rand_int), no engine physics.


## Called when a round starts (after fighters are reset).
func on_round_start(_sim: Sim, _fighter: FighterState) -> void:
	pass


## Called once per tick for the fighter, after its action update.
func on_tick(_sim: Sim, _fighter: FighterState) -> void:
	pass


## Return false to forbid starting `move` right now (e.g. needs a stored charge).
func can_start_move(_sim: Sim, _fighter: FighterState, _move: MoveData) -> bool:
	return true


func on_move_start(_sim: Sim, _fighter: FighterState, _move: MoveData) -> void:
	pass


## Called after the move's effect `effect_index` spawned; `spawned` are the new effects.
## Change them or call sim.spawn_effect for more.
func on_effects_spawned(_sim: Sim, _fighter: FighterState, _move: MoveData, _effect_index: int,
		_spawned: Array[EffectState]) -> void:
	pass


## Outgoing damage multiplier in percent for a hit about to land.
func damage_percent(_sim: Sim, _attacker: FighterState, _victim: FighterState, _move: MoveData,
		_hit: HitData) -> int:
	return 100


## Called after this fighter's move or effect connects (`blocked` true on block).
func on_hit_dealt(_sim: Sim, _attacker: FighterState, _victim: FighterState, _move: MoveData,
		_hit: HitData, _blocked: bool) -> void:
	pass


## Called after this fighter parries `attacker` (attacker is -1 for effects without owner).
func on_parry(_sim: Sim, _fighter: FighterState, _attacker: int) -> void:
	pass
