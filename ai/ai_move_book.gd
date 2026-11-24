class_name AiMoveBook
extends RefCounted
## What the CPU knows about a fighter's moves, derived from the same MoveData the sim runs:
## when each move can first hit, how far it reaches, how safe it is on block and what it is
## good for. Each CPU builds one per fighter in its match, so any fighter's data (including
## data edited between matches) just works.
##
## Distances are sim units (Fx.ONE per meter), times are move frames.

const TAG_PROJECTILE := 1
## Delayed effect placed under the target (rune eruptions).
const TAG_ERUPTION := 1 << 1
const TAG_LAUNCH := 1 << 2
const TAG_KNOCKDOWN := 1 << 3
## Covers at least 2 m of ground before it hits.
const TAG_GAP_CLOSER := 1 << 4
const TAG_ARMOR := 1 << 5
const TAG_TELEPORT := 1 << 6
const TAG_THROW := 1 << 7
const TAG_BUFF := 1 << 8
const TAG_PULL := 1 << 9
const TAG_GUARD_BREAK := 1 << 10
## Can be jump-cancelled on hit (juggle follow-ups).
const TAG_JUMP_CANCEL := 1 << 11
const TAG_OTG := 1 << 12
const TAG_INVULN := 1 << 13
const TAG_WALL_SPLAT := 1 << 14
const TAG_UNBLOCKABLE := 1 << 15

## How a move is started from neutral.
enum Use { NONE, LIGHT, HEAVY, RUN_LIGHT, AIR_LIGHT, AIR_HEAVY, GRAB, ABILITY, SUPER, GETUP }


class Entry:
	extends RefCounted
	var index: int = -1
	var move: MoveData
	var use: Use = Use.NONE
	## SimInput bit that starts it (0 if it is only reached through a chain).
	var button: int = 0
	var ability_slot: int = -1
	## First frame on which it can hit (hitbox start, or effect spawn + delay).
	var hit_frame: int = 0
	## Last frame on which a hitbox of the move itself can still hit.
	var last_hit_frame: int = 0
	var total: int = 0
	## Forward reach from the fighter's center including travel before the hit (units).
	var reach: int = 0
	## Closest distance it hits at (eruptions and most moves: 0).
	var min_reach: int = 0
	## Vertical band of its hitboxes relative to the user's feet (units).
	var low: int = 0
	var high: int = 0
	var damage: int = 0
	## Frame advantage when blocked (negative = punishable), 0 when unknown (effects).
	var on_block: int = 0
	## Hitstun of its first hit (0 when unknown).
	var hitstun: int = 0
	var tags: int = 0
	## Has hitboxes of its own (not only spawned effects or movement).
	var melee: bool = false
	var cooldown: int = 0
	var soul_cost: int = 0
	var aerial: bool = false

	func has(tag: int) -> bool:
		return tags & tag != 0

	func hits_anything() -> bool:
		return reach > 0


var data: FighterData
var entries: Array[Entry] = []
## Entries by move index (null for moves with no entry).
var by_index: Array[Entry] = []
## Neutral entries by role.
var light: Entry
var heavy: Entry
var run_light: Entry
var air_light: Entry
var air_heavy: Entry
var grab: Entry
var getup: Entry
var super_entry: Entry
var abilities: Array[Entry] = []
## Longest reach among moves that start within 10 frames (the threat radius up close).
var quick_reach: int = 0


func _init(fighter: FighterData) -> void:
	data = fighter
	for i in fighter.moves.size():
		var entry := _analyze(i, fighter.moves[i])
		entries.append(entry)
		by_index.append(entry)
	light = _assign(fighter.light, Use.LIGHT, SimInput.LIGHT)
	heavy = _assign(fighter.heavy, Use.HEAVY, SimInput.HEAVY)
	run_light = _assign(fighter.run_light, Use.RUN_LIGHT, SimInput.LIGHT)
	air_light = _assign(fighter.air_light, Use.AIR_LIGHT, SimInput.LIGHT)
	air_heavy = _assign(fighter.air_heavy, Use.AIR_HEAVY, SimInput.HEAVY)
	grab = _assign(fighter.grab, Use.GRAB, SimInput.GRAB)
	getup = _assign(fighter.getup_attack, Use.GETUP, SimInput.LIGHT)
	super_entry = _assign(fighter.super_move, Use.SUPER, SimInput.SUPER)
	for slot in mini(3, fighter.abilities.size()):
		var entry := _assign(fighter.abilities[slot], Use.ABILITY, SimInput.ABILITIES[slot])
		if entry != null:
			entry.ability_slot = slot
		abilities.append(entry)
	for entry: Entry in [light, heavy, grab]:
		if entry != null and entry.hit_frame <= 10:
			quick_reach = maxi(quick_reach, entry.reach)
	if quick_reach == 0:
		quick_reach = Fx.m(1.4)


## Entry of move `index` (null if out of range).
func entry(index: int) -> Entry:
	return by_index[index] if index >= 0 and index < by_index.size() else null


## Chain follow-ups of `e` (next_light / next_heavy), null when absent.
func next_light(e: Entry) -> Entry:
	return entry(data.find_move(e.move.next_light)) if e != null else null


func next_heavy(e: Entry) -> Entry:
	return entry(data.find_move(e.move.next_heavy)) if e != null else null


func _assign(move_id: StringName, use: Use, button: int) -> Entry:
	var index := data.find_move(move_id)
	if index < 0:
		return null
	var e := by_index[index]
	if e.use == Use.NONE:
		e.use = use
		e.button = button
	return e


func _analyze(index: int, move: MoveData) -> Entry:
	var e := Entry.new()
	e.index = index
	e.move = move
	e.total = move.total_frames()
	e.cooldown = move.cooldown
	e.soul_cost = move.soul_cost
	e.aerial = move.aerial
	e.hit_frame = 9999
	e.low = 999999
	e.high = -999999
	var first_blockstun := 0
	var first_hitstun := 0
	var first_frame := 9999
	for hb in move.hitboxes:
		if hb.hit == null:
			continue
		var start := hb.start_frame if hb.start_frame >= 0 else move.startup
		var end := hb.end_frame if hb.end_frame >= 0 else move.last_active_frame()
		var forward := maxf(hb.offset.z, hb.offset_end.z if hb.capsule else hb.offset.z) + hb.radius
		# Charges keep their hitbox out while moving, so they reach as far as they travel.
		e.reach = maxi(e.reach, Fx.m(forward) + _travel(move, end + 1))
		var bottom := minf(hb.offset.y, hb.offset_end.y if hb.capsule else hb.offset.y) - hb.radius
		var top := maxf(hb.offset.y, hb.offset_end.y if hb.capsule else hb.offset.y) + hb.radius
		e.low = mini(e.low, Fx.m(bottom))
		e.high = maxi(e.high, Fx.m(top))
		e.damage += hb.hit.damage
		e.melee = true
		e.last_hit_frame = maxi(e.last_hit_frame, end)
		if start < first_frame:
			first_frame = start
			first_blockstun = hb.hit.blockstun
			first_hitstun = hb.hit.hitstun
		e.tags |= _hit_tags(hb.hit)
	if first_frame < 9999:
		e.hit_frame = first_frame
		e.on_block = first_blockstun - (e.total - first_frame)
		e.hitstun = first_hitstun
	for ed in move.effects:
		# Effects past the move's last frame are only spawned by traits (Morrigan's shards).
		if ed.hit == null or ed.spawn_frame > e.total:
			continue
		var start := ed.spawn_frame + ed.delay + 1
		var range_m := 0.0
		if ed.anchor == EffectData.Anchor.TARGET:
			range_m = ed.max_range + ed.radius
			e.tags |= TAG_ERUPTION
		else:
			var travel := ed.travel if ed.travel > 0.0 else ed.speed * ed.lifetime / 60.0
			range_m = ed.offset.z + travel + ed.radius + ed.grow_speed * ed.lifetime / 60.0
			if ed.speed > 0.0 and ed.projectile:
				e.tags |= TAG_PROJECTILE
		e.reach = maxi(e.reach, Fx.m(range_m))
		e.low = mini(e.low, Fx.m(ed.offset.y - ed.radius) if ed.height <= 0.0 else 0)
		e.high = maxi(e.high, Fx.m(ed.offset.y + maxf(ed.radius, ed.height)))
		e.damage += ed.hit.damage * maxi(1, ed.count)
		e.hit_frame = mini(e.hit_frame, start)
		e.last_hit_frame = maxi(e.last_hit_frame, start)
		e.tags |= _hit_tags(ed.hit)
	if e.hit_frame == 9999:
		e.hit_frame = 0
		e.low = 0
		e.high = 0
	if move.teleport != null:
		e.tags |= TAG_TELEPORT
		if move.teleport.mode == TeleportData.Mode.BEHIND_TARGET:
			e.reach = maxi(e.reach, Fx.m(move.teleport.max_range))
	if move.armor_hits > 0:
		e.tags |= TAG_ARMOR
	if move.invuln_end > 0:
		e.tags |= TAG_INVULN
	if move.buff != null:
		e.tags |= TAG_BUFF
	if e.hit_frame > 0 and _travel(move, e.last_hit_frame + 1) >= Fx.m(2.0):
		e.tags |= TAG_GAP_CLOSER
	for cancel in move.cancels:
		if cancel.into & CancelData.INTO_JUMP and cancel.condition == CancelData.Condition.ON_HIT:
			e.tags |= TAG_JUMP_CANCEL
	return e


## Forward distance covered by the move's motions from frame 1 to `frame` (units).
static func _travel(move: MoveData, frame: int) -> int:
	var total := 0
	for motion in move.motions:
		var first := motion.start_frame
		var last := mini(motion.end_frame, frame - 1)
		if last >= first:
			total += Fx.mps(motion.forward_speed) * (last - first + 1)
	if move.teleport != null and move.teleport.mode != TeleportData.Mode.BEHIND_TARGET \
			and move.teleport.frame < frame:
		total += Fx.m(move.teleport.distance)
	return total


static func _hit_tags(hit: HitData) -> int:
	var tags := 0
	match hit.reaction:
		HitData.Reaction.LAUNCH, HitData.Reaction.GROUND_BOUNCE:
			tags |= TAG_LAUNCH
		HitData.Reaction.KNOCKDOWN:
			tags |= TAG_KNOCKDOWN
		HitData.Reaction.PULL:
			tags |= TAG_PULL
	if hit.throw:
		tags |= TAG_THROW
	if hit.guard_break:
		tags |= TAG_GUARD_BREAK
	if hit.otg:
		tags |= TAG_OTG
	if hit.wall_splat:
		tags |= TAG_WALL_SPLAT
	if hit.unblockable or hit.throw:
		tags |= TAG_UNBLOCKABLE
	return tags
