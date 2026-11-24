class_name AttractInputSource
extends InputSource
## A simple scripted brawler for demos and captures (not the CPU opponent): walks at the
## nearest enemy and throws light strings, heavies, abilities and guards on a fixed rhythm.
## Deterministic: it reads only the sim state.

const RANGE := Fx.ONE * 2


func next_frame(sim: Sim, slot: int) -> int:
	var f := sim.fighter(slot)
	var target := sim.attack_target(f)
	if target == null:
		return 0
	var offset := target.pos - f.pos
	var direction := Vector2(offset.x, offset.z)
	var beat := (sim.state.tick + slot * 37) % 120
	var buttons := 0
	if direction.length() > RANGE:
		return SimInput.from_vector(0, direction.normalized())
	if beat < 30:
		buttons = SimInput.LIGHT if beat % 8 < 4 else 0
	elif beat < 50:
		buttons = SimInput.GUARD
	elif beat < 70:
		buttons = SimInput.HEAVY if beat < 52 else 0
	elif beat < 74:
		buttons = SimInput.ABILITIES[(sim.state.tick / 120 + slot) % 3]
	elif beat > 100 and f.soul_points() >= 100:
		buttons = SimInput.SUPER if beat < 104 else 0
	return SimInput.from_vector(buttons, direction.normalized() * 0.2)
