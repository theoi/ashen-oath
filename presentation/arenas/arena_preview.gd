extends Node3D
## Dev viewer for arenas: loads an ArenaData and shows its presentation scene, either with a
## real Sim and idle capsule stand-ins on the spawn points (hazards play on the sim's
## schedule), or with real fighters sparring through FightView (--real). Optionally draws
## the collision data. Also renders screenshots and clips headlessly under Xvfb
## (tools/arena_shot.sh, tools/capture_clip.sh).
##
## User args (after `--`):
##   --arena=res://content/arenas/NAME.tres   ArenaData to show (default: Ashen Chapel)
##   --real=aldric,gorrath   real fighters sparring (CPU sparring partners, --seed=N)
##   --game                  the gameplay camera (design-lost-ark.md §3: 52° pitch, 15-20 m,
##                           40° FOV, ArenaData.camera_yaw) with camera-side cutaways; on by
##                           default with --real
##   --view=NAME             free camera preset: overview, fight, low, east, west, top
##   --cam=px,py,pz,tx,ty,tz custom camera position and look target
##   --orbit                 slowly orbit the arena (clips)
##   --tick=N                fast-forward N ticks into the fight before showing it
##   --hold                  stop the sim there (shots of one hazard phase; capsules only)
##   --fighters=N            capsule stand-ins on spawn points 0..N-1, 1-4 (default 2)
##   --debug                 draw floor walls, obstacles, hazards, spawns and camera bounds
##   --shot=PATH             save a PNG after --frames rendered frames, then quit
##   --frames=N              frames to wait before the shot (default 45)

const DEFAULT_ARENA := "res://content/arenas/ashen_chapel.tres"
const RULES := "res://content/rules/default_rules.tres"
const FIGHTERS := "res://content/fighters/%s/%s.tres"
const GAME_PITCH := 52.0
const GAME_FOV := 40.0
const GAME_DISTANCE := 15.0
const GAME_MAX_DISTANCE := 20.0
## name -> [camera position, look target]
const VIEWS := {
	"overview": [Vector3(0.0, 7.2, 9.6), Vector3(0.0, 0.0, -2.5)],
	"fight": [Vector3(-1.5, 3.2, 8.5), Vector3(0.5, 1.1, -1.0)],
	"low": [Vector3(-9.0, 1.6, 7.0), Vector3(4.0, 1.8, -3.0)],
	"east": [Vector3(-8.0, 3.5, 2.0), Vector3(10.0, 2.0, -0.5)],
	"west": [Vector3(8.0, 3.5, -2.0), Vector3(-10.0, 2.5, 0.5)],
	"top": [Vector3(0.0, 7.5, 0.0), Vector3(0.0, 0.0, -0.001)],
}

var sim: Sim
var arena: ArenaView
var data: ArenaData

var _fight: FightView
var _camera: Camera3D
var _dummies: Array[Node3D] = []
var _frames := 0
var _shot_path := ""
var _shot_frame := 45
var _orbit := false
var _game := false
var _time := 0.0
var _neutral := PackedInt32Array()
var _hold := false
var _focus := Vector3.ZERO


func _ready() -> void:
	var args := _parse_args()
	data = load(args.get("arena", DEFAULT_ARENA))
	_shot_path = args.get("shot", "")
	_shot_frame = int(args.get("frames", "45"))
	_orbit = args.has("orbit")
	_hold = args.has("hold")
	_game = args.has("game") or args.has("real")
	if args.has("real"):
		_start_fight(data, (args["real"] as String).split(","), int(args.get("seed", "3")))
	else:
		var scene: PackedScene = load(data.scene)
		arena = scene.instantiate()
		add_child(arena)
		_start_sim(data, clampi(int(args.get("fighters", "2")), 1, 4), int(args.get("tick", "0")))
		if _game:
			arena.apply_gameplay_camera(data)
	if args.has("debug"):
		add_child(ArenaDebugDraw.build(data))
	_camera = Camera3D.new()
	_camera.fov = 55.0
	add_child(_camera)
	var view: Array = VIEWS.get(args.get("view", "overview"), VIEWS["overview"])
	if args.has("cam"):
		view = _parse_cam(args["cam"])
	_camera.position = view[0]
	_camera.look_at(view[1])
	if args.get("view", "") == "top":
		# Orthographic from just under the roof line so floor, walls and debug lines align.
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.size = 30.0
		_camera.near = 0.05
	if _game:
		_camera.fov = GAME_FOV
		_focus = _wanted_focus()
		_place_game_camera(1.0)
	_camera.make_current()


func _physics_process(_delta: float) -> void:
	if _fight != null or _hold:
		return
	sim.step(_neutral)
	_show()


func _process(delta: float) -> void:
	_time += delta
	if _orbit:
		var angle := _time * 0.18
		_camera.position = Vector3(sin(angle) * 11.0, 4.5, cos(angle) * 9.0)
		_camera.look_at(Vector3(0.0, 1.2, 0.0))
	elif _game:
		_place_game_camera(1.0 - exp(-delta / 0.25))
	_frames += 1
	if not _shot_path.is_empty() and _frames == _shot_frame:
		var image := get_viewport().get_texture().get_image()
		image.save_png(_shot_path)
		print("saved %s round_tick=%d draw_calls=%d primitives=%d" % [_shot_path, _sim().state.round_tick,
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
		get_tree().quit()


## Approximates the design's gameplay camera: focus = player x 0.6 + enemy x 0.4, pulled
## back from 15 m toward 20 m as the fighters separate, fixed yaw, clamped to camera bounds.
func _place_game_camera(blend: float) -> void:
	var points := _fighter_points()
	_focus = _focus.lerp(_wanted_focus(), blend)
	var separation := points[0].distance_to(points[1]) if points.size() > 1 else 0.0
	var distance := clampf(GAME_DISTANCE + (separation - 6.0) * 0.6, GAME_DISTANCE, GAME_MAX_DISTANCE)
	var yaw := deg_to_rad(data.camera_yaw)
	var pitch := deg_to_rad(GAME_PITCH)
	var back := Vector3(-sin(yaw), 0.0, -cos(yaw)) * cos(pitch) * distance
	_camera.position = _focus + back + Vector3.UP * sin(pitch) * distance
	_camera.look_at(_focus)


func _wanted_focus() -> Vector3:
	var points := _fighter_points()
	var focus := points[0] * 0.6 + points[1] * 0.4 if points.size() > 1 else points[0]
	var bounds := data.camera_bounds
	focus.x = clampf(focus.x, bounds.position.x, bounds.end.x)
	focus.z = clampf(focus.z, bounds.position.y, bounds.end.y)
	return Vector3(focus.x, 0.8, focus.z)


func _fighter_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	if _fight != null:
		for slot in _fight.runner.sim.slot_count():
			points.append(_fight.runner.fighter_position(slot))
	else:
		for f in sim.state.fighters:
			points.append(Fx.to_vec3(f.pos))
	return points


func _sim() -> Sim:
	return _fight.runner.sim if _fight != null else sim


func _start_fight(arena_data: ArenaData, ids: PackedStringArray, seed_value: int) -> void:
	var config := SimConfig.new()
	config.arena = arena_data
	config.rules = load(RULES)
	config.seed = seed_value
	var sources: Array[InputSource] = []
	for i in ids.size():
		var slot := SlotConfig.new()
		slot.fighter = load(FIGHTERS % [ids[i], ids[i]])
		slot.team = 0 if i == 0 else 1
		config.slots.append(slot)
		sources.append(SparringInputSource.new(seed_value * 31 + i * 17 + 1))
	_fight = FightView.new()
	add_child(_fight)
	_fight.start(config, sources, 0)
	_fight.camera.player_control = false
	arena = _fight.arena as ArenaView


func _start_sim(arena_data: ArenaData, fighters: int, ticks: int) -> void:
	var config := SimConfig.new()
	config.arena = arena_data
	config.rules = load(RULES)
	config.round_seconds = -1
	for i in fighters:
		var slot := SlotConfig.new()
		slot.fighter = FighterData.new()
		slot.team = 0 if i == 0 else 1
		config.slots.append(slot)
	sim = Sim.new(config)
	_neutral.resize(fighters)
	while sim.state.phase != SimState.Phase.FIGHT:
		sim.step(_neutral)
	for _i in ticks:
		sim.step(_neutral)
	_add_dummies(fighters)
	_show()


func _show() -> void:
	arena.show_sim(sim)
	var points: Array[Vector3] = []
	for i in _dummies.size():
		var p := Fx.to_vec3(sim.state.fighters[i].pos)
		_dummies[i].position = p + Vector3(0.0, 0.9, 0.0)
		points.append(p)
	if _game:
		arena.follow_fighters(points, 1.0 / 60.0)


func _add_dummies(count: int) -> void:
	var colors: Array[Color] = [Color(0.55, 0.5, 0.45), Color(0.42, 0.45, 0.5), Color(0.42, 0.45, 0.5), Color(0.55, 0.5, 0.45)]
	for i in count:
		var material := StandardMaterial3D.new()
		material.albedo_color = colors[i]
		material.roughness = 0.6
		material.rim_enabled = true
		material.rim = 0.6
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.45
		capsule.height = 1.8
		var body := MeshInstance3D.new()
		body.mesh = capsule
		body.material_override = material
		add_child(body)
		_dummies.append(body)


## "px,py,pz,tx,ty,tz" -> [position, target]
func _parse_cam(text: String) -> Array:
	var v := text.split_floats(",")
	if v.size() != 6:
		return VIEWS["overview"]
	return [Vector3(v[0], v[1], v[2]), Vector3(v[3], v[4], v[5])]


func _parse_args() -> Dictionary:
	var parsed := {}
	for arg in OS.get_cmdline_user_args():
		var trimmed := arg.trim_prefix("--")
		var eq := trimmed.find("=")
		if eq < 0:
			parsed[trimmed] = "1"
		else:
			parsed[trimmed.substr(0, eq)] = trimmed.substr(eq + 1)
	return parsed
