extends SceneTree
## Writes content/test_fighter/test_fighter.tres: a generic fighter whose moves exercise
## every universal mechanic (strings, launcher, sweep, charge, run/air attacks, grab, get-up
## attack, armor dash, projectile, eruption, blink, pull, command grab, buff, super).
## Sim tests and the debug scene use it; real fighters live in content/fighters/.
##
##   godot --headless --path . -s "$PWD/tools/gen_test_fighter.gd"

const OUT := "res://content/test_fighter/test_fighter.tres"
const R := HitData.Reaction
const K := MoveData.Kind


func _init() -> void:
	var data := FighterData.new()
	data.id = &"test_fighter"
	data.display_name = "Test Fighter"
	data.moves = _moves()
	data.light = &"light_1"
	data.heavy = &"heavy_1"
	data.run_light = &"run_light"
	data.air_light = &"air_light_1"
	data.air_heavy = &"air_heavy"
	data.grab = &"grab"
	data.getup_attack = &"getup_attack"
	data.abilities = [&"dash_strike", &"rising_slash", &"bolt"]
	data.super_move = &"super"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	var err := ResourceSaver.save(data, OUT)
	print("saved %s: %s" % [OUT, error_string(err)])
	quit(0 if err == OK else 1)


func _moves() -> Array[MoveData]:
	var moves: Array[MoveData] = []

	var l1 := _move(&"light_1", K.LIGHT, 6, 2, 12, [_box(_hit(35, 16, 11, R.STAGGER, 0.3))])
	l1.next_light = &"light_2"
	l1.next_heavy = &"sweep"
	moves.append(l1)
	var l2 := _move(&"light_2", K.LIGHT, 6, 2, 12, [_box(_hit(35, 16, 11, R.STAGGER, 0.3))])
	l2.next_light = &"light_3"
	l2.next_heavy = &"launcher"
	moves.append(l2)
	moves.append(_move(&"light_3", K.LIGHT, 13, 3, 18, [_box(_hit(50, 20, 14, R.STAGGER, 1.5), 0.55, 1.0)]))

	var sweep_hit := _hit(70, 0, 14, R.KNOCKDOWN, 1.0)
	moves.append(_move(&"sweep", K.HEAVY, 14, 3, 22, [_box(sweep_hit, 0.6, 1.1, 0.4)]))
	var launch_hit := _hit(60, 45, 13, R.LAUNCH, 0.3)
	launch_hit.launch_height = 2.7
	var launcher := _move(&"launcher", K.HEAVY, 14, 3, 24, [_box(launch_hit, 0.6)])
	launcher.cancels = [_cancel(14, 30, CancelData.Condition.ON_HIT, CancelData.INTO_JUMP)]
	moves.append(launcher)

	var h1 := _move(&"heavy_1", K.HEAVY, 18, 4, 24, [_box(_hit(100, 26, 15, R.STAGGER, 0.8), 0.6, 1.2)])
	h1.chargeable = true
	h1.charge_frame = 10
	h1.charge_max = 40
	h1.next_heavy = &"heavy_2"
	moves.append(h1)
	var h2_hit := _hit(110, 0, 14, R.KNOCKDOWN, 3.0)
	h2_hit.wall_splat = true
	moves.append(_move(&"heavy_2", K.HEAVY, 22, 4, 26, [_box(h2_hit, 0.65, 1.2)]))

	var run_light := _move(&"run_light", K.LIGHT, 8, 4, 18, [_box(_hit(50, 0, 13, R.KNOCKDOWN, 1.2), 0.55)])
	run_light.motions = [_motion(1, 10, 15.0)]
	moves.append(run_light)

	var a1 := _move(&"air_light_1", K.AIR_LIGHT, 5, 3, 12, [_box(_hit(30, 18, 10, R.STAGGER, 0.2))])
	a1.aerial = true
	a1.next_light = &"air_light_2"
	moves.append(a1)
	var a2 := _move(&"air_light_2", K.AIR_LIGHT, 5, 3, 12, [_box(_hit(30, 18, 10, R.STAGGER, 0.3))])
	a2.aerial = true
	moves.append(a2)
	var spike := _hit(80, 20, 12, R.GROUND_BOUNCE, 0.3)
	spike.juggle_cost = 2
	var air_heavy := _move(&"air_heavy", K.AIR_HEAVY, 12, 4, 20, [_box(spike, 0.6, 0.8, 0.5)])
	air_heavy.aerial = true
	air_heavy.landing_recovery = 16
	moves.append(air_heavy)

	var grab_hit := _hit(0, 0, 0, R.STAGGER, 0.0)
	grab_hit.throw = true
	var grab := _move(&"grab", K.GRAB, 6, 3, 30, [_box(grab_hit, 0.5, 1.0, 0.8)])
	grab.throw_move = &"throw"
	moves.append(grab)
	var throw_hit := _hit(90, 0, 0, R.KNOCKDOWN, 2.0)
	throw_hit.unblockable = true
	throw_hit.parryable = false
	moves.append(_move(&"throw", K.THROW, 14, 1, 20, [_box(throw_hit)]))

	var getup := _move(&"getup_attack", K.GETUP_ATTACK, 14, 3, 22, [_box(_hit(50, 18, 14, R.STAGGER, 1.0), 0.6)])
	getup.invuln_start = 1
	getup.invuln_end = 10
	moves.append(getup)

	var dash_hit := _hit(90, 24, 14, R.STAGGER, 2.5)
	dash_hit.wall_splat = true
	var dash := _move(&"dash_strike", K.ABILITY, 12, 4, 24, [_box(dash_hit, 0.6)])
	dash.motions = [_motion(1, 14, 25.0, 1.4)]
	dash.armor_start = 4
	dash.armor_end = 12
	dash.armor_hits = 1
	dash.cooldown = 300
	moves.append(dash)

	var rise_hit := _hit(70, 45, 13, R.LAUNCH, 0.3)
	rise_hit.launch_height = 2.7
	var rise := _move(&"rising_slash", K.ABILITY, 8, 4, 26, [_box(rise_hit, 0.6)])
	rise.cancels = [_cancel(8, 30, CancelData.Condition.ON_HIT, CancelData.INTO_JUMP)]
	rise.cooldown = 240
	moves.append(rise)

	var bolt := _move(&"bolt", K.ABILITY, 16, 1, 20, [])
	bolt.effects = [_effect(&"bolt", 16, 18.0, 20.0, _hit(60, 18, 12, R.STAGGER, 0.4))]
	bolt.cooldown = 150
	moves.append(bolt)

	var grasp_hit := _hit(90, 40, 12, R.LAUNCH, 0.0)
	grasp_hit.launch_height = 2.4
	var grasp_effect := _effect(&"eruption", 14, 0.0, 0.0, grasp_hit)
	grasp_effect.anchor = EffectData.Anchor.TARGET
	grasp_effect.max_range = 12.0
	grasp_effect.offset = Vector3.ZERO
	grasp_effect.radius = 1.2
	grasp_effect.height = 2.0
	grasp_effect.delay = 30
	grasp_effect.lifetime = 12
	grasp_effect.destroyable = false
	grasp_effect.blocked_by_walls = false
	grasp_effect.projectile = false
	var eruption := _move(&"eruption", K.ABILITY, 14, 1, 20, [])
	eruption.effects = [grasp_effect]
	eruption.cooldown = 420
	moves.append(eruption)

	var blink := _move(&"blink", K.ABILITY, 2, 1, 10, [])
	var tp := TeleportData.new()
	tp.frame = 2
	tp.mode = TeleportData.Mode.STICK
	tp.distance = 5.0
	blink.teleport = tp
	blink.invuln_start = 1
	blink.invuln_end = 14
	blink.air_ok = true
	blink.cooldown = 300
	moves.append(blink)

	var hook_hit := _hit(40, 30, 14, R.PULL, 0.0)
	hook_hit.pull_distance = 1.2
	hook_hit.guard_damage = 35
	var hook_box := _box(hook_hit, 0.35, 1.2, 0.8)
	hook_box.capsule = true
	hook_box.offset_end = Vector3(0.0, 1.2, 9.0)
	var chain_hook := _move(&"chain_hook", K.ABILITY, 14, 3, 26, [hook_box])
	chain_hook.cooldown = 360
	moves.append(chain_hook)

	var cg_hit := _hit(0, 0, 0, R.STAGGER, 0.0)
	cg_hit.throw = true
	cg_hit.throw_beats_attacks = true
	var command_grab := _move(&"command_grab", K.SUPER, 5, 3, 40, [_box(cg_hit, 0.6, 1.0, 1.0)])
	command_grab.throw_move = &"execution"
	command_grab.techable = false
	command_grab.soul_cost = 100
	command_grab.flash_frames = 20
	command_grab.invuln_start = 1
	command_grab.invuln_end = 4
	moves.append(command_grab)
	var slam := _hit(100, 30, 0, R.STAGGER, 0.0)
	slam.unblockable = true
	slam.parryable = false
	var final_slam := _hit(150, 0, 0, R.KNOCKDOWN, 2.5)
	final_slam.unblockable = true
	final_slam.parryable = false
	final_slam.hitstop = 16
	var execution := _move(&"execution", K.THROW, 10, 1, 30, [_box(slam), _box(slam), _box(final_slam)])
	execution.hitboxes[0].start_frame = 10
	execution.hitboxes[0].end_frame = 10
	execution.hitboxes[1].start_frame = 20
	execution.hitboxes[1].end_frame = 20
	execution.hitboxes[1].group = 1
	execution.hitboxes[2].start_frame = 30
	execution.hitboxes[2].end_frame = 30
	execution.hitboxes[2].group = 2
	execution.recovery = 20
	moves.append(execution)

	var war_cry := _move(&"war_cry", K.ABILITY, 10, 1, 14, [])
	var buff := BuffData.new()
	buff.id = &"war_cry"
	buff.duration = 180
	buff.damage_bonus_percent = 30
	buff.uses = 1
	war_cry.buff = buff
	war_cry.buff_frame = 10
	war_cry.cooldown = 600
	moves.append(war_cry)

	var super_launch := _hit(120, 40, 14, R.LAUNCH, 0.3)
	super_launch.launch_height = 3.0
	var super_final := _hit(180, 0, 16, R.KNOCKDOWN, 3.5)
	super_final.wall_splat = true
	super_final.hitstop = 16
	var super_move := _move(&"super", K.SUPER, 8, 6, 30, [_box(super_launch, 1.0, 1.0, 1.2), _box(super_final, 1.5, 1.2, 1.5)])
	super_move.hitboxes[0].start_frame = 8
	super_move.hitboxes[0].end_frame = 9
	super_move.hitboxes[1].start_frame = 12
	super_move.hitboxes[1].end_frame = 13
	super_move.hitboxes[1].group = 1
	super_move.soul_cost = 100
	super_move.flash_frames = 20
	super_move.invuln_start = 1
	super_move.invuln_end = 14
	moves.append(super_move)
	return moves


func _move(id: StringName, kind: MoveData.Kind, startup: int, active: int, recovery: int,
		boxes: Array) -> MoveData:
	var move := MoveData.new()
	move.id = id
	move.kind = kind
	move.startup = startup
	move.active = active
	move.recovery = recovery
	var typed: Array[HitboxData] = []
	typed.assign(boxes)
	move.hitboxes = typed
	move.animation = id
	return move


func _hit(damage: int, hitstun: int, blockstun: int, reaction: HitData.Reaction, knockback: float) -> HitData:
	var hit := HitData.new()
	hit.damage = damage
	hit.hitstun = hitstun
	hit.blockstun = blockstun
	hit.reaction = reaction
	hit.knockback = knockback
	return hit


func _box(hit: HitData, radius: float = 0.5, height: float = 1.1, forward: float = 0.9) -> HitboxData:
	var box := HitboxData.new()
	box.hit = hit
	box.radius = radius
	box.offset = Vector3(0.0, height, forward)
	return box


func _motion(first: int, last: int, speed: float, stop_at: float = 0.0) -> MotionData:
	var motion := MotionData.new()
	motion.start_frame = first
	motion.end_frame = last
	motion.forward_speed = speed
	motion.stop_at_distance = stop_at
	return motion


func _cancel(first: int, last: int, condition: CancelData.Condition, into: int) -> CancelData:
	var cancel := CancelData.new()
	cancel.start_frame = first
	cancel.end_frame = last
	cancel.condition = condition
	cancel.into = into
	return cancel


func _effect(id: StringName, frame: int, speed: float, travel: float, hit: HitData) -> EffectData:
	var effect := EffectData.new()
	effect.id = id
	effect.spawn_frame = frame
	effect.speed = speed
	effect.travel = travel
	effect.offset = Vector3(0.0, 1.1, 0.8)
	effect.radius = 0.3
	effect.lifetime = 90
	effect.hit = hit
	return effect
