extends TestCase
## Drowned Crypt grave vents: the sim fires them on the fixed design schedule (glow 60 f,
## fire 45 f, every 12 s per vent, diagonal pairs alternating), and the arena shows glow and
## fire on exactly the ticks the sim is in those phases.

const CRYPTS: PackedStringArray = [
	"res://content/arenas/drowned_crypt.tres",
	"res://content/arenas/drowned_crypt_depths.tres",
]
const CYCLES := 2


func test_vents_follow_the_design_schedule() -> void:
	for path in CRYPTS:
		var data: ArenaData = load(path)
		assert_eq(data.hazards.size(), 4, "%s has 4 vents" % path)
		var offsets := {}
		for hazard in data.hazards:
			assert_eq(hazard.period, 720, "%s %s: 12 s cycle" % [path, hazard.id])
			assert_eq(hazard.warn, 60, "%s %s: glows 60 f" % [path, hazard.id])
			assert_eq(hazard.active, 45, "%s %s: vents 45 f" % [path, hazard.id])
			assert_eq(hazard.hit.damage, 60, "%s %s: 60 damage" % [path, hazard.id])
			assert_eq(hazard.hit.reaction, HitData.Reaction.LAUNCH, "%s %s: small launch" % [path, hazard.id])
			offsets[hazard.offset] = offsets.get(hazard.offset, 0) + 1
		# Two diagonal pairs, half a cycle apart, so one pair is always quiet.
		assert_eq(offsets.size(), 2, "%s: two vent pairs" % path)
		var keys: Array = offsets.keys()
		assert_eq(absi(int(keys[0]) - int(keys[1])), 360, "%s: pairs alternate every 6 s" % path)


func test_sim_events_match_the_schedule() -> void:
	var sim := _crypt_sim(CRYPTS[0])
	var data := sim.arena.data
	var warns: Array[PackedInt32Array] = []
	var actives: Array[PackedInt32Array] = []
	for _i in data.hazards.size():
		warns.append(PackedInt32Array())
		actives.append(PackedInt32Array())
	var neutral := PackedInt32Array([0, 0])
	var last := data.hazards[0].offset + 720 * CYCLES
	for h in data.hazards:
		last = maxi(last, h.offset + 720 * CYCLES)
	while sim.state.round_tick < last:
		for e in sim.step(neutral):
			if e.type == SimEvent.Type.HAZARD_WARN:
				warns[e.amount].append(sim.state.round_tick)
			elif e.type == SimEvent.Type.HAZARD_ACTIVE:
				actives[e.amount].append(sim.state.round_tick)
	for i in data.hazards.size():
		var h := data.hazards[i]
		var expected_warn := PackedInt32Array()
		var expected_active := PackedInt32Array()
		for k in CYCLES:
			expected_warn.append(h.offset + k * h.period)
			expected_active.append(h.offset + k * h.period + h.warn)
		assert_eq(warns[i].slice(0, CYCLES), expected_warn, "%s warns" % h.id)
		assert_eq(actives[i].slice(0, CYCLES), expected_active, "%s erupts" % h.id)


func test_vent_visuals_follow_sim_phase() -> void:
	for path in CRYPTS:
		var sim := _crypt_sim(path)
		var data := sim.arena.data
		var scene: PackedScene = load(data.scene)
		var crypt: ArenaView = scene.instantiate()
		add_child_autofree(crypt)
		var neutral := PackedInt32Array([0, 0])
		var end := data.hazards[0].offset + 720
		for h in data.hazards:
			end = maxi(end, h.offset + h.warn + h.active + 2)
		var fire_ticks := 0
		while sim.state.round_tick <= end:
			sim.step(neutral)
			crypt.show_sim(sim)
			for i in data.hazards.size():
				var phase := sim.hazard_phase(i)
				var vent: int = crypt._hazard_vents[i]
				var fire: MeshInstance3D = crypt._vent_fire_meshes[vent]
				var glow: ShaderMaterial = crypt._vent_glows[vent]
				var charge: float = glow.get_shader_parameter("charge")
				assert_eq(fire.visible, phase == 2, "%s vent %d fire at round tick %d" % [path, i, sim.state.round_tick])
				assert_eq(charge > 0.0, phase == 1, "%s vent %d glow at round tick %d" % [path, i, sim.state.round_tick])
				if phase == 2:
					fire_ticks += 1
		assert_eq(fire_ticks, data.hazards.size() * data.hazards[0].active, "%s: every vent burned for its active frames" % path)
		var vents := PackedInt32Array(crypt._hazard_vents)
		vents.sort()
		assert_eq(vents, PackedInt32Array([0, 1, 2, 3]), "%s: each hazard drives its own grate" % path)


func _crypt_sim(path: String) -> Sim:
	var config := SimConfig.new()
	config.arena = load(path)
	config.rules = load("res://content/rules/default_rules.tres")
	config.round_seconds = -1
	for i in 2:
		var slot := SlotConfig.new()
		slot.fighter = FighterData.new()
		slot.team = i
		config.slots.append(slot)
	var sim := Sim.new(config)
	var neutral := PackedInt32Array([0, 0])
	while sim.state.phase != SimState.Phase.FIGHT:
		sim.step(neutral)
	return sim
