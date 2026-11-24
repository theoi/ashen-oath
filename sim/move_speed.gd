class_name MoveSpeed
extends RefCounted
## SimConfig.move_speed_percent: copies a fighter with every move frame number scaled by
## 100 / percent (rounded, at least 1 frame) and move speeds by percent, so moves play
## faster or slower but cover the same ground. Effect lifetimes, cooldowns and windows
## measured in time after the move (combo/chain windows) are unchanged.


static func scaled_fighter(data: FighterData, percent: int) -> FighterData:
	var copy := data.duplicate() as FighterData
	var moves: Array[MoveData] = []
	for move in data.moves:
		moves.append(scaled_move(move, percent))
	copy.moves = moves
	return copy


## Frame number `frame` (1 = first tick) on the scaled timeline. 0 and negatives are flags.
static func at(frame: int, percent: int) -> int:
	if frame <= 0:
		return frame
	return 1 + ((frame - 1) * 200 + percent) / (2 * percent)


## A length in frames on the scaled timeline (at least 1 when non-zero).
static func length(frames: int, percent: int) -> int:
	if frames <= 0:
		return frames
	return maxi(1, (frames * 200 + percent) / (2 * percent))


static func _window(start: int, end: int, percent: int) -> Vector2i:
	var a := at(start, percent)
	return Vector2i(a, maxi(a, at(end, percent)) if end > 0 else end)


static func scaled_move(move: MoveData, percent: int) -> MoveData:
	var m := move.duplicate() as MoveData
	var startup := at(move.startup, percent)
	var last := maxi(startup, at(move.last_active_frame(), percent))
	var total := maxi(last, at(move.total_frames(), percent))
	m.startup = startup
	m.active = last - startup + 1
	m.recovery = total - last
	m.landing_recovery = length(move.landing_recovery, percent)
	m.tracking = move.tracking * percent / 100.0 if move.tracking > 0.0 else move.tracking
	var w := _window(move.invuln_start, move.invuln_end, percent)
	m.invuln_start = w.x
	m.invuln_end = w.y
	w = _window(move.armor_start, move.armor_end, percent)
	m.armor_start = w.x
	m.armor_end = w.y
	w = _window(move.projectile_invuln_start, move.projectile_invuln_end, percent)
	m.projectile_invuln_start = w.x
	m.projectile_invuln_end = w.y
	w = _window(move.flinch_immune_start, move.flinch_immune_end, percent)
	m.flinch_immune_start = w.x
	m.flinch_immune_end = w.y
	w = _window(move.push_immune_start, move.push_immune_end, percent)
	m.push_immune_start = w.x
	m.push_immune_end = w.y
	w = _window(move.counter_window_start, move.counter_window_end, percent)
	m.counter_window_start = w.x
	m.counter_window_end = w.y
	w = _window(move.channel_start, move.channel_end, percent)
	m.channel_start = w.x
	m.channel_end = w.y
	w = _window(move.stance_start, move.stance_end, percent)
	m.stance_start = w.x
	m.stance_end = w.y
	w = _window(move.hold_start, move.hold_end, percent)
	m.hold_start = w.x
	m.hold_end = w.y
	m.charge_frame = at(move.charge_frame, percent)
	m.charge_max = length(move.charge_max, percent)
	var levels := PackedInt32Array()
	for threshold in move.charge_levels:
		levels.append(length(threshold, percent))
	m.charge_levels = levels
	m.perfect_start = length(move.perfect_start, percent)
	m.perfect_end = length(move.perfect_end, percent)
	m.buff_frame = at(move.buff_frame, percent)
	m.skill_cancel_from = at(move.skill_cancel_from, percent)
	m.dash_cancel_from = at(move.dash_cancel_from, percent)
	m.mark_frame = at(move.mark_frame, percent)
	var hitboxes: Array[HitboxData] = []
	for hb in move.hitboxes:
		var h := hb.duplicate() as HitboxData
		h.start_frame = at(hb.start_frame, percent)
		h.end_frame = maxi(h.start_frame, at(hb.end_frame, percent)) if hb.end_frame > 0 else hb.end_frame
		h.rehit_frames = length(hb.rehit_frames, percent)
		hitboxes.append(h)
	m.hitboxes = hitboxes
	var motions: Array[MotionData] = []
	for motion in move.motions:
		var mo := motion.duplicate() as MotionData
		mo.start_frame = at(motion.start_frame, percent)
		mo.end_frame = maxi(mo.start_frame, at(motion.end_frame, percent))
		mo.forward_speed = motion.forward_speed * percent / 100.0
		mo.side_speed = motion.side_speed * percent / 100.0
		motions.append(mo)
	m.motions = motions
	var effects: Array[EffectData] = []
	for ed in move.effects:
		var e := ed.duplicate() as EffectData
		e.spawn_frame = at(ed.spawn_frame, percent)
		effects.append(e)
	m.effects = effects
	var cancels: Array[CancelData] = []
	for cancel in move.cancels:
		var cd := cancel.duplicate() as CancelData
		cd.start_frame = at(cancel.start_frame, percent)
		cd.end_frame = maxi(cd.start_frame, at(cancel.end_frame, percent))
		cancels.append(cd)
	m.cancels = cancels
	if move.teleport != null:
		m.teleport = move.teleport.duplicate() as TeleportData
		m.teleport.frame = at(move.teleport.frame, percent)
	return m
