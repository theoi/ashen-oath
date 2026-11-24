extends ArenaView
## Ashen Chapel: a burned cathedral nave with half its roof fallen in. Moonlight and ash pour
## through the gap over the west end; coffins lie in window niches along the long walls,
## and an altar glows behind a balustrade at the east end. No hazards.
##
## `burning` dresses the night variant (fight 3): the fallen roof timbers smoulder, more
## embers rise and fire light replaces some of the moonlight.

## Half extents (x, z) of the fightable floor. Collision lives in content/arenas/ashen_chapel*.tres
## (corners chamfered; the north-west one is cut deeper around the fallen roof).
const HALF := Vector2(12.0, 10.0)
const WALL_THICKNESS := 1.0
const WALL_HEIGHT := 4.0
## wall_pillar pilasters stick out this far; those pieces sit further out so their faces
## line up with the collision wall.
const PILASTER_DEPTH := 0.25
## Nave pillars (x, z). The two western ones broke when the roof came down.
const PILLARS: Array[Vector2] = [Vector2(-5.0, -4.5), Vector2(-5.0, 4.5), Vector2(5.0, -4.5), Vector2(5.0, 4.5)]
const BROKEN_PILLARS: Array[int] = [0, 1]
## x of the coffin window niches in both long walls.
const NICHES: Array[float] = [-6.0, 6.0]
const CHAR_COLOR := Color(0.035, 0.03, 0.03)

@export var burning := false


func _build_layout() -> void:
	_build_floor()
	_build_long_walls()
	_build_end_walls()
	_build_corners()
	_build_upper_walls()
	_build_roof()
	_build_pillars()
	_build_chancel()
	_build_entrance()
	_build_atmosphere()


func _build_floor() -> void:
	for ix in 6:
		for iz in 5:
			var center := Vector3(-10.0 + ix * 4.0, -0.05, -8.0 + iz * 4.0)
			var pattern := (ix * 7 + iz * 13) % 5
			if pattern != 0:
				dungeon("floor_tile_large", center, 90.0 * float((ix + iz) % 4))
				continue
			for k in 4:
				var offset := Vector3(-1.0 + 2.0 * float(k % 2), 0.0, -1.0 + 2.0 * float(k >> 1))
				var broken := ["floor_tile_small", "floor_tile_small_broken_A", "floor_tile_small_broken_B"][(ix + iz + k) % 3] as String
				dungeon(broken, center + offset, 90.0 * float(k))


## North (z < 0) and south walls: solid runs with pilasters, plus a window niche holding a
## coffin at each NICHES position.
func _build_long_walls() -> void:
	for side: float in [-1.0, 1.0]:
		var z := side * (HALF.y + WALL_THICKNESS * 0.5)
		var yaw := 0.0 if side < 0.0 else 180.0
		var xs: Array[float] = [-10.0, -6.0, -2.0, 2.0, 6.0, 10.0]
		for i in xs.size():
			var x := xs[i]
			if x in NICHES:
				dungeon("wall_archedwindow_open", Vector3(x, 0.0, z), yaw)
				_build_niche(x, side)
			elif i % 2 == 0:
				dungeon("wall_pillar", Vector3(x, 0.0, z + side * PILASTER_DEPTH), yaw)
			else:
				dungeon("wall_cracked" if (i + int(side)) % 3 == 0 else "wall", Vector3(x, 0.0, z), yaw)
		for x: float in [-3.0, 3.0]:
			_banner(Vector3(x, 0.0, side * HALF.y), yaw, "banner_thin_red")
		_wall_torch(Vector3(-10.0, 2.1, side * HALF.y), yaw)
		_wall_torch(Vector3(10.0, 2.1, side * HALF.y), yaw)
		for x: float in [-8.0, -4.0, 0.0, 4.0, 8.0]:
			_candle_row(Vector3(x, 0.0, side * (HALF.y - 0.15)), int(x) + int(side * 3.0))


## A shallow room behind a window opening: a coffin on a stone shelf, candles on the sill.
func _build_niche(x: float, side: float) -> void:
	var back := side * (HALF.y + 3.5)
	var yaw := 0.0 if side < 0.0 else 180.0
	dungeon("wall", Vector3(x, 0.0, back), yaw)
	for dx: float in [-2.5, 2.5]:
		dungeon("wall", Vector3(x + dx, 0.0, side * (HALF.y + 2.0)), 90.0, Vector3(0.75, 1.0, 1.0))
	block(Vector3(4.0, 0.9, 2.0), Vector3(x, 0.45, side * (HALF.y + 2.1)), Vector3.ZERO, Color(0.09, 0.09, 0.1))
	halloween("coffin_decorated", Vector3(x, 0.9, side * (HALF.y + 2.0)), 90.0 + yaw)
	for dx: float in [-0.85, -0.45, 0.5, 0.9]:
		var candle := "candle_thin_lit" if int(absf(dx) * 10.0) % 2 == 0 else "candle_lit"
		var height := 0.55 + 0.2 * float(int(absf(dx) * 10.0) % 3)
		var pos := Vector3(x + dx, 1.02, side * (HALF.y + 0.45))
		dungeon(candle, pos, 0.0, Vector3(height, height, height))
		flame(pos + Vector3(0.0, 1.0 * height, 0.0), 0.14)
	fire_light(Vector3(x, 1.9, side * (HALF.y + 0.9)), 0.8, 5.5)


## West wall holds the gated entrance; east wall opens onto the chancel.
func _build_end_walls() -> void:
	for side: float in [-1.0, 1.0]:
		var x := side * (HALF.x + WALL_THICKNESS * 0.5)
		var yaw := 90.0 if side < 0.0 else -90.0
		for z: float in [-8.0, -4.0, 4.0, 8.0]:
			var model := "wall_pillar" if absf(z) > 6.0 else "wall"
			var inset := PILASTER_DEPTH if model == "wall_pillar" else 0.0
			dungeon(model, Vector3(x + side * inset, 0.0, z), yaw)
		_wall_torch(Vector3(side * HALF.x, 2.1, -4.0), yaw)
		_wall_torch(Vector3(side * HALF.x, 2.1, 4.0), yaw)


func _build_corners() -> void:
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			dungeon("pillar", Vector3(sx * (HALF.x + 0.5), 0.0, sz * (HALF.y + 0.5)))
			dungeon("pillar", Vector3(sx * (HALF.x + 0.5), WALL_HEIGHT, sz * (HALF.y + 0.5)))
	# Candle clusters tucked into three corners; the fallen roof fills the north-west one.
	var corners: Array[Vector2] = [Vector2(1.0, -1.0), Vector2(1.0, 1.0), Vector2(-1.0, 1.0)]
	for c in corners:
		var base := Vector3(c.x * (HALF.x - 0.45), 0.0, c.y * (HALF.y - 0.45))
		dungeon("candle_lit", base, 0.0, Vector3(0.9, 0.9, 0.9))
		flame(base + Vector3(0.0, 0.92, 0.0), 0.16)
		var b := base + Vector3(-c.x * 0.5, 0.0, 0.0)
		dungeon("candle_thin_lit", b, 0.0, Vector3(0.6, 0.6, 0.6))
		flame(b + Vector3(0.0, 0.62, 0.0), 0.12)
		var t := base + Vector3(0.0, 0.0, -c.y * 0.55)
		halloween("candle_melted", t, 30.0)
		flame(t + Vector3(-0.09, 0.62, -0.02), 0.11)
	# Fallen roof in the north-west corner, kept behind the corner wall of the floor polygon
	# (x + z < -18) so fighters never stand inside it.
	dungeon("rubble_large", Vector3(-10.6, 0.0, -8.8), 35.0, Vector3(0.42, 0.5, 0.42))
	beam(Vector3(-11.7, 4.5, -7.0), Vector3(-9.2, 0.15, -9.7), 0.45)
	dungeon("pillar", Vector3(-9.4, 0.15, -9.3), 20.0, Vector3(0.7, 0.32, 0.7)).rotation_degrees = Vector3(0.0, 20.0, 82.0)


## Clerestory: arched windows along the long walls, broken where the roof collapsed.
func _build_upper_walls() -> void:
	for side: float in [-1.0, 1.0]:
		var z := side * (HALF.y + WALL_THICKNESS * 0.5)
		var yaw := 0.0 if side < 0.0 else 180.0
		for x: float in [-10.0, -6.0, -2.0, 2.0, 6.0, 10.0]:
			var model := "wall_archedwindow_open"
			if x < -4.0:
				model = "wall_broken"
			elif absf(x) > 8.0:
				model = "wall"
			dungeon(model, Vector3(x, WALL_HEIGHT, z), yaw)
	for side: float in [-1.0, 1.0]:
		var x := side * (HALF.x + WALL_THICKNESS * 0.5)
		var yaw := 90.0 if side < 0.0 else -90.0
		for z: float in [-8.0, -4.0, 0.0, 4.0, 8.0]:
			var model := "wall"
			if side < 0.0 and absf(z) < 6.0:
				model = "wall_broken"
			dungeon(model, Vector3(x, WALL_HEIGHT, z), yaw)


## Charred roof beams survive over the east half only.
func _build_roof() -> void:
	for x: float in [1.0, 4.5, 8.0, 11.5]:
		overhead(block(Vector3(0.5, 0.6, 2.0 * HALF.y + 3.0), Vector3(x, 8.3, 0.0), Vector3.ZERO, CHAR_COLOR))
	overhead(block(Vector3(0.4, 0.5, 9.0), Vector3(-1.8, 8.6, -7.0), Vector3(-18.0, 0.0, 8.0), CHAR_COLOR))
	overhead(block(Vector3(2.0 * HALF.x + 2.0, 0.5, 0.5), Vector3(5.0, 8.0, 0.0), Vector3.ZERO, CHAR_COLOR))


func _build_pillars() -> void:
	for i in PILLARS.size():
		var p := PILLARS[i]
		var pos := Vector3(p.x, 0.0, p.y)
		if i in BROKEN_PILLARS:
			dungeon("pillar", pos, 15.0 * float(i), Vector3(1.0, 0.42 + 0.12 * float(i), 1.0))
			dungeon("rubble_half", pos + Vector3(0.4, 0.0, -0.3), 40.0 + 70.0 * float(i), Vector3(0.22, 0.2, 0.22))
		else:
			dungeon("pillar_decorated", pos, 90.0 if p.x < 0.0 else -90.0)
			overhead(dungeon("pillar", pos + Vector3(0.0, WALL_HEIGHT, 0.0)))
			overhead(block(Vector3(1.0, 0.5, 2.0 * HALF.y + 2.0), Vector3(p.x, 8.0, 0.0), Vector3.ZERO, CHAR_COLOR))


## The altar recess behind the east balustrade.
func _build_chancel() -> void:
	var x0 := HALF.x + WALL_THICKNESS * 0.5
	halloween("arch", Vector3(x0, 0.0, 0.0), 90.0)
	dungeon("barrier", Vector3(x0, 0.0, 0.0), 90.0)
	for z: float in [-2.0, 2.0]:
		dungeon("floor_tile_large", Vector3(x0 + 2.5, -0.05, z * 1.0))
	dungeon("wall", Vector3(x0 + 4.5, 0.0, -2.0), -90.0)
	dungeon("wall", Vector3(x0 + 4.5, 0.0, 2.0), -90.0)
	dungeon("wall", Vector3(x0 + 4.5, WALL_HEIGHT, 0.0), -90.0, Vector3(2.0, 1.0, 1.0))
	for side: float in [-1.0, 1.0]:
		dungeon("wall", Vector3(x0 + 2.5, 0.0, side * 4.5), 0.0 if side < 0.0 else 180.0)
		dungeon("wall", Vector3(x0 + 2.5, WALL_HEIGHT, side * 4.5), 0.0 if side < 0.0 else 180.0)
	overhead(block(Vector3(2.0 * 2.5, 0.2, 9.5), Vector3(x0 + 2.5, 8.1, 0.0), Vector3.ZERO, CHAR_COLOR))
	var altar := Vector3(x0 + 3.4, 0.0, 0.0)
	halloween("shrine_candles", altar, -90.0, Vector3(1.4, 1.4, 1.4))
	for tip: Vector3 in [Vector3(0.03, 1.73, -0.11), Vector3(0.03, 1.69, -0.01), Vector3(-0.1, 1.62, -0.01), Vector3(-0.08, 1.13, 0.3)]:
		flame(altar + Basis(Vector3.UP, deg_to_rad(-90.0)) * (tip * 1.4), 0.14)
	_banner(Vector3(x0 + 4.0, 0.6, -2.0), -90.0, "banner_patternA_red")
	_banner(Vector3(x0 + 4.0, 0.6, 2.0), -90.0, "banner_patternA_red")
	for z: float in [-1.7, 1.7]:
		var candle := Vector3(x0 + 2.6, 0.0, z)
		dungeon("candle_lit", candle, 0.0, Vector3(1.2, 1.2, 1.2))
		flame(candle + Vector3(0.0, 1.24, 0.0), 0.18)
	halloween("skull_candle", Vector3(x0 + 1.4, 0.0, -1.3), 200.0, Vector3(0.7, 0.7, 0.7))
	fire_light(Vector3(x0 + 2.5, 2.2, 0.0), 1.5, 8.0)


## Gated west door with graves glimpsed in the moonlit yard beyond.
func _build_entrance() -> void:
	var x0 := -(HALF.x + WALL_THICKNESS * 0.5)
	halloween("arch_gate", Vector3(x0, 0.0, 0.0), 90.0)
	block(Vector3(10.0, 0.1, 12.0), Vector3(x0 - 5.0, -0.06, 0.0), Vector3.ZERO, Color(0.06, 0.065, 0.07))
	halloween("gravestone", Vector3(x0 - 3.0, 0.0, -1.2), 80.0)
	halloween("grave_A_destroyed", Vector3(x0 - 4.5, 0.0, 1.6), 100.0)
	halloween("gravestone", Vector3(x0 - 6.5, 0.0, -0.2), 95.0)


## Bones, rubble and dead candles along the walls (outside where fighters stand), so the
## nave reads as long abandoned.
func _build_decay() -> void:
	var spots: Array[Vector3] = [
		Vector3(-3.0, 0.0, -HALF.y + 0.5), Vector3(3.5, 0.0, HALF.y - 0.5), Vector3(8.5, 0.0, -HALF.y + 0.45),
		Vector3(-9.0, 0.0, HALF.y - 0.45), Vector3(HALF.x - 0.45, 0.0, 6.5), Vector3(-HALF.x + 0.45, 0.0, 3.0),
	]
	for i in spots.size():
		var p := spots[i]
		halloween(["bone_A", "bone_B", "bone_C"][i % 3] as String, p + Vector3(0.0, 0.06, 0.0), 37.0 * float(i))
		if i % 2 == 0:
			halloween("skull", p + Vector3(0.6, 0.0, 0.0), 70.0 * float(i), Vector3(0.4, 0.4, 0.4))
		else:
			dungeon("rubble_half", p + Vector3(-0.7, 0.0, 0.0), 50.0 * float(i), Vector3(0.14, 0.12, 0.14))
		dungeon("candle_melted", p + Vector3(-0.3, 0.0, 0.25 * signf(-p.z)), 0.0, Vector3(0.7, 0.5, 0.7))


func _build_atmosphere() -> void:	# Moonlight through the collapsed west roof: one heavy shaft onto the middle of the nave
	# (the fighters' light pool), thinner ones through the roof gap and clerestory windows.
	light_shaft(Vector3(-6.5, 16.0, -6.0), Vector3(-0.5, 0.0, 0.0), 2.6, 4.6, 1.3)
	light_shaft(Vector3(-11.0, 14.0, -11.0), Vector3(-6.5, 0.0, -3.0), 1.4, 2.4, 0.8)
	for x: float in [-2.0, 2.0, 6.0]:
		light_shaft(Vector3(x - 2.0, 7.0, -HALF.y - 1.5), Vector3(x + 1.0, 0.0, -HALF.y + 5.0), 0.7, 1.2, 0.45)
	dust(Vector3(-3.5, 7.0, -3.0), Vector3(2.5, 6.0, 2.5), 60)
	ash(Vector3(-3.0, 7.0, -1.0), Vector3(9.0, 1.0, 8.0), look.ash_amount)
	_build_decay()
	embers(Vector3(-HALF.x + 2.0, 0.6, -HALF.y + 2.0), Vector3(1.5, 0.4, 1.5), look.ember_amount, look.ember_color)
	if burning:
		fire_light(Vector3(-10.0, 1.4, -8.6), 1.6, 9.0)
		for p: Vector3 in [Vector3(-10.8, 1.1, -8.6), Vector3(-10.0, 1.6, -8.8), Vector3(-9.6, 0.5, -9.3), Vector3(-11.2, 1.4, -7.6)]:
			flame(p, 0.55)
		embers(Vector3(0.0, 0.2, 0.0), Vector3(HALF.x, 0.2, HALF.y), look.ember_amount * 2, look.ember_color, 0.025)
		fire_light(Vector3(PILLARS[0].x + 0.6, 2.2, 0.0), 1.2, 9.0)
		for pillar: int in BROKEN_PILLARS:
			var p := PILLARS[pillar]
			flame(Vector3(p.x + 0.4, 1.7 + 0.5 * float(pillar), p.y - 0.2), 0.35)
			embers(Vector3(p.x, 1.9, p.y), Vector3(0.5, 0.2, 0.5), look.ember_amount >> 1, look.ember_color)


## A charred beam (box) from `from` to `to`.
func beam(from: Vector3, to: Vector3, thickness: float) -> MeshInstance3D:
	var axis := to - from
	var instance := block(Vector3(thickness, thickness, axis.length()), (from + to) * 0.5, Vector3.ZERO, CHAR_COLOR)
	instance.look_at_from_position(instance.position, to, Vector3.UP if absf(axis.normalized().y) < 0.95 else Vector3.RIGHT)
	return instance


func _banner(at_wall: Vector3, yaw: float, model: String) -> void:
	dungeon(model, Vector3(at_wall.x, at_wall.y, at_wall.z) - Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(0.0, 0.0, 0.5), yaw)


## A short row of floor candles against a wall; `seed` varies heights and spacing.
func _candle_row(center: Vector3, seed: int) -> void:
	for k in 3:
		var h := 0.35 + 0.22 * float(posmod(seed * 7 + k * 5, 4))
		var pos := center + Vector3(-0.45 + 0.42 * float(k) + 0.05 * float(posmod(seed + k, 3)), 0.0, 0.0)
		dungeon("candle_thin_lit" if k == 1 else "candle_lit", pos, 30.0 * float(k), Vector3(h, h, h))
		flame(pos + Vector3(0.0, 1.0 * h, 0.0), 0.1)


func _wall_torch(at_wall: Vector3, yaw: float) -> void:
	var basis := Basis(Vector3.UP, deg_to_rad(yaw))
	dungeon("torch_mounted", at_wall, yaw)
	flame(at_wall + basis * Vector3(0.0, 0.42, 0.3), 0.3)
