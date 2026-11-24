extends ArenaView
## Drowned Crypt: a flooded burial vault. Ankle-deep black water over the floor, coffins
## behind iron grilles along the long walls, a mausoleum glowing green through the east
## arch, and four grave-vent grates that glow, then erupt in spectral fire on a fixed
## schedule. Collision, spawns and the vent hazards are in content/arenas/drowned_crypt*.tres;
## the vents follow the sim's hazard phases through show_sim().
##
## `depths` dresses the deeper variant (fight 5): higher water, a stronger soul-light,
## hanging lanterns and more drifting souls.

const HALF := Vector2(12.0, 10.0)
const WALL_THICKNESS := 1.0
const WALL_HEIGHT := 4.0
## wall_pillar pilasters stick out this far; those pieces sit further out so their faces
## line up with the collision wall.
const PILASTER_DEPTH := 0.25
const CEILING := 9.0
const PILLARS: Array[Vector2] = [Vector2(-9.0, 0.0), Vector2(9.0, 0.0), Vector2(0.0, -6.5), Vector2(0.0, 6.5)]
## Grave-vent grate centres; each is a 4 x 4 m grate tile on the floor grid. The hazards in
## the arena's ArenaData sit on these.
const VENTS: Array[Vector2] = [Vector2(-6.0, -4.0), Vector2(6.0, 4.0), Vector2(6.0, -4.0), Vector2(-6.0, 4.0)]
## Coffin niches (x) behind gated walls on both long walls.
const NICHES: Array[float] = [-6.0, 6.0]
const SPIRIT_FIRE_SHADER := preload("res://presentation/arenas/shaders/spirit_fire.gdshader")
const VENT_GLOW_SHADER := preload("res://presentation/arenas/shaders/vent_glow.gdshader")
const VENT_FIRE_HEIGHT := 3.2
const VENT_FIRE_RADIUS := 1.5

@export var depths := false

var _vent_glows: Array[ShaderMaterial] = []
var _vent_fires: Array[ShaderMaterial] = []
var _vent_fire_meshes: Array[MeshInstance3D] = []
var _vent_lights: Array[OmniLight3D] = []
var _vent_sparks: Array[CPUParticles3D] = []
## Sim hazard index -> vent visual index (by nearest grate), built on first show_sim().
var _hazard_vents: PackedInt32Array = []


## Visual state of hazard `hazard` this tick: x = telegraph charge (0..1], y = fire (0..1].
## Lit exactly on the ticks the sim reports warn (phase 1) or active (phase 2).
static func hazard_visual(sim: Sim, hazard: int) -> Vector2:
	var phase := sim.hazard_phase(hazard)
	if phase == 0:
		return Vector2.ZERO
	var h := sim.arena.hazards[hazard]
	var cycle_tick := (sim.state.round_tick - h.offset) % h.period
	if phase == 1:
		return Vector2(float(cycle_tick + 1) / float(h.warn), 0.0)
	var t := float(cycle_tick - h.warn + 1) / float(h.active)
	return Vector2(0.0, minf(1.0, t * 6.0) * (1.0 - 0.9 * smoothstep(0.7, 1.0, t)))


func show_sim(sim: Sim) -> void:
	var hazards := sim.arena.hazards
	if _hazard_vents.size() != hazards.size():
		_hazard_vents.resize(hazards.size())
		for i in hazards.size():
			_hazard_vents[i] = _nearest_vent(hazards[i].center)
	for vent in VENTS.size():
		_show_vent(vent, Vector2.ZERO)
	for i in hazards.size():
		var state := hazard_visual(sim, i)
		if state != Vector2.ZERO:
			_show_vent(_hazard_vents[i], state)


func _show_vent(vent: int, state: Vector2) -> void:
	_vent_glows[vent].set_shader_parameter("charge", state.x)
	_vent_fires[vent].set_shader_parameter("intensity", state.y)
	_vent_fire_meshes[vent].visible = state.y > 0.0
	_vent_lights[vent].visible = state.x > 0.0 or state.y > 0.0
	_vent_lights[vent].light_energy = look.soul_light_energy * (state.x * 0.8 + state.y * 3.0)
	_vent_sparks[vent].emitting = state.y > 0.2


func _nearest_vent(center: Vector2) -> int:
	var best := 0
	for i in VENTS.size():
		if VENTS[i].distance_squared_to(center) < VENTS[best].distance_squared_to(center):
			best = i
	return best

func _build_layout() -> void:
	_build_floor()
	_build_long_walls()
	_build_end_walls()
	_build_corners()
	_build_ceiling()
	_build_pillars()
	_build_mausoleum()
	_build_vents()
	_build_atmosphere()


func _build_floor() -> void:
	for ix in 6:
		for iz in 5:
			var center := Vector2(-10.0 + ix * 4.0, -8.0 + iz * 4.0)
			if center in VENTS:
				dungeon("floor_tile_big_grate", Vector3(center.x, -0.05, center.y))
			else:
				dungeon("floor_tile_large", Vector3(center.x, -0.05, center.y), 90.0 * float((ix * 3 + iz) % 4))
	water(Vector2(1.0, 0.0), Vector2(2.0 * HALF.x + 8.0, 2.0 * HALF.y + 8.0))


func _build_long_walls() -> void:
	for side: float in [-1.0, 1.0]:
		var z := side * (HALF.y + WALL_THICKNESS * 0.5)
		var yaw := 0.0 if side < 0.0 else 180.0
		var xs: Array[float] = [-10.0, -6.0, -2.0, 2.0, 6.0, 10.0]
		for i in xs.size():
			var x := xs[i]
			if x in NICHES:
				dungeon("wall_gated", Vector3(x, 0.0, z), yaw)
				_build_niche(x, side)
			else:
				var inset := PILASTER_DEPTH if i % 2 == 0 else 0.0
				dungeon("wall_pillar" if i % 2 == 0 else "wall", Vector3(x, 0.0, z + side * inset), yaw)
			dungeon("wall", Vector3(x, WALL_HEIGHT, z), yaw)
		_wall_lantern(Vector3(-2.0, 0.0, side * (HALF.y - 0.2)), yaw)
		_wall_lantern(Vector3(2.0, 0.0, side * (HALF.y - 0.2)), yaw)
		# One light for both lanterns keeps the Compatibility renderer's light passes down.
		steady_light(Vector3(0.0, 2.7, side * (HALF.y - 0.6)), look.soul_color, look.soul_light_energy * 0.9, 6.5)


## A sarcophagus behind an iron grille, lit by a soul lantern.
func _build_niche(x: float, side: float) -> void:
	var yaw := 0.0 if side < 0.0 else 180.0
	dungeon("wall", Vector3(x, 0.0, side * (HALF.y + 4.0)), yaw)
	for dx: float in [-2.5, 2.5]:
		dungeon("wall", Vector3(x + dx, 0.0, side * (HALF.y + 2.5)), 90.0, Vector3(1.0, 1.0, 1.0))
	dungeon("floor_tile_large", Vector3(x, -0.05, side * (HALF.y + 2.5)))
	halloween("coffin", Vector3(x, 0.0, side * (HALF.y + 2.5)), 90.0)
	halloween("lantern_standing", Vector3(x + 1.5, 0.0, side * (HALF.y + 3.3)))
	halloween("skull", Vector3(x - 1.4, 0.0, side * (HALF.y + 1.6)), 30.0 * side, Vector3(0.5, 0.5, 0.5))
	steady_light(Vector3(x + 1.2, 1.2, side * (HALF.y + 2.4)), look.soul_color, look.soul_light_energy * 0.8, 5.0)


func _build_end_walls() -> void:
	for side: float in [-1.0, 1.0]:
		var x := side * (HALF.x + WALL_THICKNESS * 0.5)
		var yaw := 90.0 if side < 0.0 else -90.0
		for z: float in [-8.0, -4.0, 0.0, 4.0, 8.0]:
			if side > 0.0 and z == 0.0:
				continue
			var model := "wall_gated" if side < 0.0 and z == 0.0 else ("wall_pillar" if absf(z) > 6.0 else "wall")
			var inset := PILASTER_DEPTH if model == "wall_pillar" else 0.0
			dungeon(model, Vector3(x + side * inset, 0.0, z), yaw)
			dungeon("wall", Vector3(x, WALL_HEIGHT, z), yaw)
	# The west grille lets a little cold light in from the stair beyond.
	steady_light(Vector3(-HALF.x - 2.0, 2.0, 0.0), look.key_color, 1.0, 6.0)


func _build_corners() -> void:
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			dungeon("pillar", Vector3(sx * (HALF.x + 0.5), 0.0, sz * (HALF.y + 0.5)))
			dungeon("pillar", Vector3(sx * (HALF.x + 0.5), WALL_HEIGHT, sz * (HALF.y + 0.5)))
			# Bone piles fill the chamfered corners, outside the floor polygon.
			var c := Vector3(sx * (HALF.x - 0.4), 0.0, sz * (HALF.y - 0.4))
			halloween("ribcage", c + Vector3(-sx * 0.2, 0.15, -sz * 0.1), 40.0 * sx * sz, Vector3(0.7, 0.7, 0.7))
			halloween("bone_C", c + Vector3(-sx * 0.8, 0.06, 0.0), 70.0 * sz)
			halloween("bone_A", c + Vector3(0.0, 0.06, -sz * 0.7), 20.0 * sx)
			halloween("skull", c + Vector3(-sx * 0.5, 0.0, -sz * 0.45), 150.0 * sx, Vector3(0.45, 0.45, 0.45))
	for p: Vector3 in [Vector3(HALF.x - 0.75, 0.0, -HALF.y + 0.75), Vector3(-HALF.x + 0.75, 0.0, HALF.y - 0.75)]:
		halloween("candle_melted", p, 20.0)
		flame(p + Vector3(-0.09, 0.61, -0.02), 0.11)
		flame(p + Vector3(0.08, 0.53, 0.05), 0.1)
		fire_light(p + Vector3(0.0, 1.0, 0.0), 0.5, 4.0)


## A low vault: dark ribs over the nave, lost in fog.
func _build_ceiling() -> void:
	# The vault casts no shadow so the key light can stand in for light leaking through it.
	var vault := block(Vector3(2.0 * HALF.x + 4.0, 0.4, 2.0 * HALF.y + 4.0), Vector3(0.0, CEILING, 0.0), Vector3.ZERO, Color(0.02, 0.02, 0.025))
	vault.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for x: float in [-8.0, -2.0, 2.0, 8.0]:
		var rib := block(Vector3(0.7, 0.8, 2.0 * HALF.y + 2.0), Vector3(x, CEILING - 0.5, 0.0), Vector3.ZERO, Color(0.06, 0.065, 0.07))
		rib.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_pillars() -> void:
	for i in PILLARS.size():
		var p := PILLARS[i]
		dungeon("pillar", Vector3(p.x, 0.0, p.y), 90.0 * float(i))
		dungeon("pillar", Vector3(p.x, WALL_HEIGHT, p.y), 90.0 * float(i + 1), Vector3(1.0, 1.25, 1.0))
		if depths:
			var hang := Vector3(p.x + (0.9 if p.x > 0.0 else -0.9), 3.7, p.y)
			halloween("lantern_hanging", hang, 0.0, Vector3(0.8, 0.8, 0.8))
			block(Vector3(0.05, 0.9, 0.05), hang + Vector3(0.0, 0.45, 0.0), Vector3.ZERO, Color(0.05, 0.05, 0.05))
	halloween("bone_B", Vector3(-1.2, 0.05, -7.0), 35.0)
	halloween("bone_A", Vector3(-8.2, 0.05, 1.1), 110.0)


## The tomb chamber beyond the east arch, glowing with soul-light.
func _build_mausoleum() -> void:
	var x0 := HALF.x + WALL_THICKNESS * 0.5
	halloween("arch_gate", Vector3(x0, 0.0, 0.0), 90.0)
	for dz: float in [-4.0, 0.0, 4.0]:
		dungeon("floor_tile_large", Vector3(x0 + 3.0, -0.05, dz))
		dungeon("floor_tile_large", Vector3(x0 + 7.0, -0.05, dz))
	for side: float in [-1.0, 1.0]:
		for dx: float in [2.5, 6.5]:
			dungeon("wall", Vector3(x0 + dx, 0.0, side * 5.5), 0.0 if side < 0.0 else 180.0)
			dungeon("wall", Vector3(x0 + dx, WALL_HEIGHT, side * 5.5), 0.0 if side < 0.0 else 180.0)
	halloween("crypt", Vector3(x0 + 6.0, 0.0, 0.0), -90.0, Vector3(0.62, 0.62, 0.62))
	for dz: float in [-2.6, 2.6]:
		halloween("lantern_standing", Vector3(x0 + 2.4, 0.0, dz), 0.0, Vector3(1.2, 1.2, 1.2))
	steady_light(Vector3(x0 + 3.0, 2.0, 0.0), look.soul_color, look.soul_light_energy * 2.0, 9.0)
	soul_motes(Vector3(x0 + 3.5, 0.8, 0.0), Vector3(2.0, 0.6, 3.0), look.mote_amount >> 1)


func _build_vents() -> void:
	var noise := noise_texture()
	for i in VENTS.size():
		var v := VENTS[i]
		var glow_material := ShaderMaterial.new()
		glow_material.shader = VENT_GLOW_SHADER
		glow_material.set_shader_parameter("color", look.soul_color)
		var glow_mesh := PlaneMesh.new()
		glow_mesh.size = Vector2(3.6, 3.6)
		var glow := MeshInstance3D.new()
		glow.mesh = glow_mesh
		glow.material_override = glow_material
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glow.position = Vector3(v.x, look.water_level + 0.02, v.y)
		add_child(glow)
		_vent_glows.append(glow_material)

		var fire_material := ShaderMaterial.new()
		fire_material.shader = SPIRIT_FIRE_SHADER
		fire_material.set_shader_parameter("noise", noise)
		fire_material.set_shader_parameter("edge_color", look.soul_color)
		var fire_mesh := CylinderMesh.new()
		fire_mesh.top_radius = VENT_FIRE_RADIUS * 0.45
		fire_mesh.bottom_radius = VENT_FIRE_RADIUS
		fire_mesh.height = VENT_FIRE_HEIGHT
		fire_mesh.cap_top = false
		fire_mesh.cap_bottom = false
		fire_mesh.radial_segments = 20
		var fire := MeshInstance3D.new()
		fire.mesh = fire_mesh
		fire.material_override = fire_material
		fire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fire.position = Vector3(v.x, VENT_FIRE_HEIGHT * 0.5, v.y)
		fire.visible = false
		add_child(fire)
		_vent_fires.append(fire_material)
		_vent_fire_meshes.append(fire)

		var light := steady_light(Vector3(v.x, 1.2, v.y), look.soul_color, 0.0, 7.0)
		light.visible = false
		_vent_lights.append(light)

		var sparks := embers(Vector3(v.x, 0.3, v.y), Vector3(1.4, 0.1, 1.4), 40, look.soul_color, 0.05)
		sparks.initial_velocity_min = 2.0
		sparks.initial_velocity_max = 4.5
		sparks.lifetime = 1.2
		sparks.preprocess = 0.0
		sparks.visible = true
		sparks.emitting = false
		_vent_sparks.append(sparks)


func _build_atmosphere() -> void:
	soul_motes(Vector3(0.0, look.water_level + 0.1, 0.0), Vector3(HALF.x, 0.05, HALF.y), look.mote_amount)
	ash(Vector3(0.0, 6.0, 0.0), Vector3(HALF.x, 1.0, HALF.y), look.ash_amount)
	# Pale light falls through a broken grate in the vault.
	light_shaft(Vector3(-4.0, CEILING, 2.0), Vector3(-2.5, 0.0, 0.5), 0.9, 1.8, 1.0)
	light_shaft(Vector3(5.0, CEILING, -2.5), Vector3(3.5, 0.0, -1.5), 0.7, 1.5, 0.7)
	if depths:
		# Soul-light welling up from the deep water around the pillars.
		for p: Vector2 in [Vector2(-5.0, 0.0), Vector2(5.0, 0.0)]:
			steady_light(Vector3(p.x, 0.6, p.y), look.soul_color, look.soul_light_energy * 0.7, 8.0)


## A soul lantern on a stone bracket above head height, so fighters at the wall pass under.
func _wall_lantern(at: Vector3, yaw: float) -> void:
	var shelf := at + Vector3(0.0, 2.3, 0.0)
	block(Vector3(0.8, 0.15, 0.6), shelf + Vector3(0.0, -0.08, 0.0), Vector3(0.0, yaw, 0.0), Color(0.07, 0.08, 0.08))
	halloween("lantern_standing", shelf, yaw, Vector3(0.75, 0.75, 0.75))
