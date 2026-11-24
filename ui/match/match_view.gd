class_name MatchView
extends Node3D
## What a match looks like until the real fighter presentation lands: the arena scene (or a
## dark floor) with capsule stand-ins at the sim positions, and a camera behind the local
## player that keeps the opponents in view. Reads the runner only.

const FALLBACK_STAGE := preload("res://presentation/menu_backdrop/menu_backdrop.tscn")
const CAMERA_DISTANCE := 6.5
const CAMERA_HEIGHT := 3.2
const CAMERA_FOLLOW := 6.0

var runner: MatchRunner
var camera: Camera3D

var _arena: Node
var _bodies: Array[Node3D] = []
var _player_slot := 0


func setup(p_runner: MatchRunner, arena_scene: PackedScene, player_slot: int) -> void:
	runner = p_runner
	_player_slot = player_slot
	_arena = arena_scene.instantiate() if arena_scene != null else FALLBACK_STAGE.instantiate()
	add_child(_arena)
	camera = Camera3D.new()
	camera.fov = 60.0
	add_child(camera)
	camera.make_current()
	runner.stepped.connect(_on_stepped)


func _on_stepped(_events: Array[SimEvent]) -> void:
	if _arena is ArenaView:
		(_arena as ArenaView).set_sim_tick(runner.sim.state.tick)


func _process(delta: float) -> void:
	if runner == null or runner.sim == null:
		return
	var sim := runner.sim
	while _bodies.size() < sim.slot_count():
		_bodies.append(_make_body(_bodies.size()))
	for slot in sim.slot_count():
		var f := sim.fighter(slot)
		_bodies[slot].position = runner.fighter_position(slot)
		_bodies[slot].rotation.y = Fx.angle_to_rad(f.facing)
		_bodies[slot].visible = true
		_bodies[slot].scale = Vector3(1.0, 0.35, 1.0) if f.ko else Vector3.ONE
	_follow(delta)


func _follow(delta: float) -> void:
	var player := runner.fighter_position(_player_slot)
	var focus := Vector3.ZERO
	var count := 0
	for slot in runner.sim.slot_count():
		if slot != _player_slot and not runner.sim.fighter(slot).ko:
			focus += runner.fighter_position(slot)
			count += 1
	focus = focus / count if count > 0 else player + Vector3(0.0, 0.0, -1.0)
	var away := player - focus
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3.BACK
	var target := player + away * CAMERA_DISTANCE + Vector3.UP * CAMERA_HEIGHT
	camera.position = camera.position.lerp(target, clampf(delta * CAMERA_FOLLOW, 0.0, 1.0)) if camera.position != Vector3.ZERO else target
	camera.look_at(player.lerp(focus, 0.35) + Vector3.UP * 1.1)


func _make_body(slot: int) -> Node3D:
	var root := Node3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.45
	mesh.height = 1.8
	var material := StandardMaterial3D.new()
	var team := runner.sim.fighter(slot).team
	material.albedo_color = Palette.TEAMS[team % Palette.TEAMS.size()].darkened(0.25)
	material.emission_enabled = true
	material.emission = Palette.TEAMS[team % Palette.TEAMS.size()]
	material.emission_energy_multiplier = 0.25
	var body := MeshInstance3D.new()
	body.mesh = mesh
	body.material_override = material
	body.position.y = 0.9
	root.add_child(body)
	var nose := MeshInstance3D.new()
	var nose_mesh := BoxMesh.new()
	nose_mesh.size = Vector3(0.18, 0.18, 0.4)
	nose.mesh = nose_mesh
	nose.material_override = material
	nose.position = Vector3(0.0, 1.4, 0.45)
	root.add_child(nose)
	add_child(root)
	return root
