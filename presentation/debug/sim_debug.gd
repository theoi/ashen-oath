extends Node3D
## Minimal playable view of the sim for development: capsule fighters with facing markers,
## active hitbox gizmos, effects, hazards and arena collision, plus a text readout.
## Keyboard / gamepad drive slot 0 (camera_* actions orbit the view).
##
## User args (after --):
##   --arena=res://content/arenas/<id>.tres   arena collision (default: training arena)
##   --fighters=N                              1-4 slots (slot 0 vs the rest)
##   --p2=bot|idle|guard                       opponents (default bot)
##   --demo                                    bots on every slot (clips, soak)
##   --replay=user://x.res                     play a saved Replay
##   --save-replay=user://x.res                save the replay on exit

const TEAM_COLORS: Array[Color] = [Color(0.3, 0.55, 1.0), Color(1.0, 0.35, 0.25), Color(0.4, 0.9, 0.4), Color(0.95, 0.8, 0.3)]
const HITBOX_POOL := 24
const DEFAULT_ARENA := "res://content/arenas/training_arena.tres"
const DEFAULT_FIGHTER := "res://content/test_fighter/test_fighter.tres"

var runner: MatchRunner
var _camera: Camera3D
var _yaw := 0.0
var _bodies: Array[MeshInstance3D] = []
var _body_materials: Array[StandardMaterial3D] = []
var _hitboxes: Array[MeshInstance3D] = []
var _effects: Dictionary[int, MeshInstance3D] = {}
var _hazards: Array[MeshInstance3D] = []
var _hud: Label
var _log: PackedStringArray = []
var _last_hit_tick: PackedInt32Array = PackedInt32Array([-99, -99, -99, -99])
var _save_replay := ""


func _ready() -> void:
	var args := _args()
	var config := SimConfig.new()
	config.rules = load("res://content/rules/default_rules.tres")
	config.arena = load(args.get("arena", DEFAULT_ARENA))
	config.seed = 1
	var count := clampi(int(args.get("fighters", "2")), 1, 4)
	var sources: Array[InputSource] = []
	var replay: Replay = null
	if args.has("replay"):
		replay = load(args["replay"]) as Replay
		config = replay.config
		count = replay.slot_count
	for i in count:
		if replay == null:
			var slot := SlotConfig.new()
			slot.fighter = load(DEFAULT_FIGHTER)
			slot.team = mini(i, 1)
			slot.start_soul = 50
			config.slots.append(slot)
	_save_replay = args.get("save-replay", "")
	_build_world(config.arena)
	runner = MatchRunner.new()
	add_child(runner)
	for i in count:
		if replay != null:
			sources.append(ReplayInputSource.new(replay, i))
		elif i == 0 and not args.has("demo"):
			sources.append(DeviceInputSource.new(_camera))
		else:
			match args.get("p2", "bot"):
				"idle":
					sources.append(null)
				"guard":
					sources.append(ScriptedInputSource.new(PackedInt32Array([SimInput.GUARD]), true))
				_:
					sources.append(DebugBot.new(17 + i))
	runner.start(config, sources)
	runner.event_emitted.connect(_on_event)
	_build_fighters()


func _exit_tree() -> void:
	if not _save_replay.is_empty() and runner != null and runner.replay != null:
		ResourceSaver.save(runner.replay, _save_replay)


func _process(delta: float) -> void:
	if runner == null or runner.sim == null:
		return
	var sim := runner.sim
	_yaw += Input.get_axis(DefaultBindings.CAMERA_RIGHT, DefaultBindings.CAMERA_LEFT) * delta * 2.0
	_update_fighters(sim)
	_update_hitboxes(sim)
	_update_effects(sim)
	_update_hazards(sim)
	_update_camera(sim)
	_update_hud(sim)


func _args() -> Dictionary:
	var result := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		result[parts[0]] = parts[1] if parts.size() > 1 else "true"
	return result


func _build_world(arena: ArenaData) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.06, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.7)
	env.ambient_light_energy = 0.6
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60.0, 30.0, 0.0)
	add_child(sun)
	var floor_mesh := ArrayMesh.new()
	var verts := PackedVector3Array()
	var poly := arena.floor_polygon
	for i in range(1, poly.size() - 1):
		for p: Vector2 in [poly[0], poly[i], poly[i + 1]]:
			verts.append(Vector3(p.x, 0.0, p.y))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	floor_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var floor_instance := MeshInstance3D.new()
	floor_instance.mesh = floor_mesh
	floor_instance.material_override = _material(Color(0.22, 0.22, 0.25), 1.0)
	floor_instance.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
	add_child(floor_instance)
	for obstacle in arena.obstacles:
		var pillar := MeshInstance3D.new()
		var length := obstacle.a.distance_to(obstacle.b)
		var box := BoxMesh.new()
		box.size = Vector3(obstacle.radius * 2.0, obstacle.height, length + obstacle.radius * 2.0)
		if length < 0.01:
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = obstacle.radius
			cylinder.bottom_radius = obstacle.radius
			cylinder.height = obstacle.height
			pillar.mesh = cylinder
		else:
			pillar.mesh = box
		var mid := (obstacle.a + obstacle.b) * 0.5
		pillar.position = Vector3(mid.x, obstacle.height * 0.5, mid.y)
		if length >= 0.01:
			var d := obstacle.b - obstacle.a
			pillar.rotation.y = atan2(d.x, d.y)
		# See-through so tall crypt obstacles never hide the fighters.
		pillar.material_override = _material(Color(0.45, 0.42, 0.4), 0.3)
		add_child(pillar)
	add_child(ArenaDebugDraw.build(arena))
	for hazard in arena.hazards:
		var vent := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = hazard.radius
		cylinder.bottom_radius = hazard.radius
		cylinder.height = hazard.height
		vent.mesh = cylinder
		vent.position = Vector3(hazard.center.x, hazard.height * 0.5, hazard.center.y)
		vent.material_override = _material(Color(1.0, 0.5, 0.1), 0.0)
		add_child(vent)
		_hazards.append(vent)
	_camera = Camera3D.new()
	_camera.fov = 60.0
	add_child(_camera)
	_camera.make_current()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	for _i in HITBOX_POOL:
		var gizmo := MeshInstance3D.new()
		gizmo.mesh = sphere
		gizmo.material_override = _material(Color(1.0, 0.1, 0.1), 0.45)
		gizmo.visible = false
		add_child(gizmo)
		_hitboxes.append(gizmo)
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(12.0, 8.0)
	_hud.add_theme_font_size_override("font_size", 15)
	_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override("outline_size", 4)
	layer.add_child(_hud)


func _build_fighters() -> void:
	var sim := runner.sim
	for f in sim.state.fighters:
		var data := sim.fighter_data[f.slot]
		var body := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = data.radius
		capsule.height = data.height
		body.mesh = capsule
		var material := _material(TEAM_COLORS[f.slot % TEAM_COLORS.size()], 1.0)
		body.material_override = material
		var nose := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.18, 0.18, 0.4)
		nose.mesh = box
		nose.position = Vector3(0.0, data.height * 0.25, data.radius)
		nose.material_override = _material(Color.WHITE, 1.0)
		body.add_child(nose)
		add_child(body)
		_bodies.append(body)
		_body_materials.append(material)


func _update_fighters(sim: Sim) -> void:
	for f in sim.state.fighters:
		var body := _bodies[f.slot]
		var data := sim.fighter_data[f.slot]
		var pos := runner.fighter_position(f.slot)
		var lying := f.action == FighterState.Action.KNOCKDOWN or f.action == FighterState.Action.KO and f.grounded
		body.position = pos + Vector3(0.0, data.radius if lying else data.height * 0.5, 0.0)
		body.rotation = Vector3(PI * 0.5 if lying else 0.0, Fx.angle_to_rad(f.facing), 0.0)
		var color := TEAM_COLORS[f.slot % TEAM_COLORS.size()]
		if f.ko:
			color = Color(0.3, 0.3, 0.3)
		elif sim.state.tick - _last_hit_tick[f.slot] < 6:
			color = Color.WHITE
		elif f.in_hitstun() or f.action == FighterState.Action.KNOCKDOWN:
			color = color.lerp(Color(1.0, 0.9, 0.2), 0.5)
		elif sim.guard_up(f):
			color = color.lerp(Color(0.6, 0.9, 1.0), 0.6)
		elif f.action == FighterState.Action.GRABBED:
			color = color.lerp(Color.MAGENTA, 0.5)
		_body_materials[f.slot].albedo_color = color
		_body_materials[f.slot].albedo_color.a = 0.45 if sim.is_invulnerable(f) and not f.ko else 1.0
		_body_materials[f.slot].transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if sim.is_invulnerable(f) else BaseMaterial3D.TRANSPARENCY_DISABLED


func _update_hitboxes(sim: Sim) -> void:
	var used := 0
	for f in sim.state.fighters:
		var move := sim.current_move(f)
		if move == null:
			continue
		var origin := runner.fighter_position(f.slot)
		var basis := Basis(Vector3.UP, Fx.angle_to_rad(f.facing))
		for hb in move.hitboxes:
			var first := hb.start_frame if hb.start_frame >= 0 else move.startup
			var last := hb.end_frame if hb.end_frame >= 0 else move.last_active_frame()
			if f.move_frame < first or f.move_frame > last or used >= HITBOX_POOL:
				continue
			var points: Array[Vector3] = [hb.offset]
			if hb.capsule:
				var steps := maxi(1, int(hb.offset.distance_to(hb.offset_end) / maxf(hb.radius, 0.1)))
				for i in range(1, steps + 1):
					points.append(hb.offset.lerp(hb.offset_end, float(i) / steps))
			for point in points:
				if used >= HITBOX_POOL:
					break
				var gizmo := _hitboxes[used]
				gizmo.visible = true
				gizmo.position = origin + basis * point
				gizmo.scale = Vector3.ONE * hb.radius
				used += 1
	for i in range(used, HITBOX_POOL):
		_hitboxes[i].visible = false


func _update_effects(sim: Sim) -> void:
	var alive := {}
	for e in sim.state.effects:
		alive[e.id] = true
		var ed := sim.effect_data(e)
		var gizmo: MeshInstance3D = _effects.get(e.id)
		if gizmo == null:
			gizmo = MeshInstance3D.new()
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 1.0
			cylinder.bottom_radius = 1.0
			cylinder.height = 1.0
			gizmo.mesh = cylinder
			gizmo.material_override = _material(Color(1.0, 0.9, 0.2), 0.6)
			add_child(gizmo)
			_effects[e.id] = gizmo
		var radius := maxf(Fx.to_m(e.radius), 0.05)
		var height := maxf(ed.height, radius * 2.0)
		gizmo.position = Fx.to_vec3(e.pos) + Vector3(0.0, height * 0.5 - (radius if ed.height <= 0.0 else 0.0), 0.0)
		gizmo.scale = Vector3(radius, height, radius)
		(gizmo.material_override as StandardMaterial3D).albedo_color.a = 0.2 if e.age <= ed.delay else 0.7
	for id: int in _effects.keys():
		if not alive.has(id):
			_effects[id].queue_free()
			_effects.erase(id)


func _update_hazards(sim: Sim) -> void:
	for i in _hazards.size():
		var phase := sim.hazard_phase(i)
		var material := _hazards[i].material_override as StandardMaterial3D
		material.albedo_color = [Color(1.0, 0.5, 0.1, 0.05), Color(1.0, 0.6, 0.1, 0.3), Color(1.0, 0.1, 0.05, 0.7)][phase]


func _update_camera(sim: Sim) -> void:
	var center := Vector3.ZERO
	var count := 0
	var spread := 0.0
	for f in sim.state.fighters:
		if not f.ko:
			center += runner.fighter_position(f.slot)
			count += 1
	if count == 0:
		return
	center /= count
	for f in sim.state.fighters:
		if not f.ko:
			spread = maxf(spread, center.distance_to(runner.fighter_position(f.slot)))
	var distance := 7.0 + spread * 1.2
	var back := Basis(Vector3.UP, _yaw) * Vector3(0.0, 0.0, -1.0)
	_camera.position = center - back * distance + Vector3(0.0, 3.5 + spread * 0.4, 0.0)
	_camera.look_at(center + Vector3(0.0, 1.0, 0.0))


func _update_hud(sim: Sim) -> void:
	var s := sim.state
	var lines := PackedStringArray()
	var timer := "∞" if s.round_timer < 0 else str(sim.seconds_left())
	lines.append("tick %d  round %d  %s  time %s  wins %s  checksum %x" % [s.tick, s.round_number,
			SimState.Phase.keys()[s.phase], timer, s.team_wins, sim.checksum() & 0xFFFFFFFF])
	for f in s.fighters:
		var move := sim.current_move(f)
		lines.append("P%d team %d  HP %d/%d  Soul %d  Guard %d  CD %s  %s%s%s  combo %d" % [f.slot + 1, f.team,
				f.hp, f.max_hp, f.soul_points(), f.guard_points(), f.cooldowns,
				FighterState.Action.keys()[f.action],
				(" %s f%d" % [move.id, f.move_frame]) if move != null else "",
				" [lock]" if f.hard_lock else "", f.combo_hits])
	lines.append("")
	lines.append_array(_log)
	_hud.text = "\n".join(lines)


func _on_event(event: SimEvent) -> void:
	match event.type:
		SimEvent.Type.HIT, SimEvent.Type.BLOCK, SimEvent.Type.PARRY, SimEvent.Type.GUARD_BREAK, \
				SimEvent.Type.ARMOR, SimEvent.Type.GRAB, SimEvent.Type.GRAB_TECH, SimEvent.Type.LAUNCH, \
				SimEvent.Type.WALL_SPLAT, SimEvent.Type.KNOCKDOWN, SimEvent.Type.AIR_TECH, \
				SimEvent.Type.TECH_ROLL, SimEvent.Type.JUGGLE_LIMIT, SimEvent.Type.PERFECT_DODGE, \
				SimEvent.Type.SUPER_FLASH, SimEvent.Type.BURST, SimEvent.Type.KO, SimEvent.Type.ROUND_END, \
				SimEvent.Type.MATCH_END, SimEvent.Type.FIGHT:
			if event.type == SimEvent.Type.HIT and event.target >= 0:
				_last_hit_tick[event.target] = event.tick
			var counter := " COUNTER" if event.flags & SimEvent.FLAG_COUNTER else ""
			_log.append("%d %s P%d>P%d %s %d%s" % [event.tick, SimEvent.Type.keys()[event.type],
					event.source + 1, event.target + 1, event.id, event.amount, counter])
			if _log.size() > 10:
				_log.remove_at(0)


func _material(color: Color, alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color, alpha)
	if alpha < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material
