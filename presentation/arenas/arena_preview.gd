extends Node3D
## Dev viewer for arenas: loads an ArenaData, instances its presentation scene and runs a
## real Sim on it with idle stand-in fighters at the arena's spawn points, so hazards play
## on the sim's schedule. Optionally draws the collision data over the scene. Also renders
## screenshots and clips headlessly under Xvfb (tools/arena_shot.sh, tools/capture_clip.sh).
##
## User args (after `--`):
##   --arena=res://content/arenas/NAME.tres   ArenaData to show (default: Ashen Chapel)
##   --view=NAME             camera preset: overview, fight, low, east, west, top
##   --cam=px,py,pz,tx,ty,tz custom camera position and look target
##   --orbit                 slowly orbit the arena (clips)
##   --tick=N                fast-forward N ticks into the fight before showing it
##   --hold                  stop the sim there (shots of one hazard phase)
##   --fighters=N            stand-in fighters on spawn points 0..N-1, 1-4 (default 2)
##   --debug                 draw floor walls, obstacles, hazards, spawns and camera bounds
##   --shot=PATH             save a PNG after --frames rendered frames, then quit
##   --frames=N              frames to wait before the shot (default 45)

const DEFAULT_ARENA := "res://content/arenas/ashen_chapel.tres"
const RULES := "res://content/rules/default_rules.tres"
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

var _camera: Camera3D
var _dummies: Array[Node3D] = []
var _frames := 0
var _shot_path := ""
var _shot_frame := 45
var _orbit := false
var _time := 0.0
var _neutral := PackedInt32Array()
var _hold := false


func _ready() -> void:
	var args := _parse_args()
	var data: ArenaData = load(args.get("arena", DEFAULT_ARENA))
	var scene: PackedScene = load(data.scene)
	arena = scene.instantiate()
	add_child(arena)
	_shot_path = args.get("shot", "")
	_shot_frame = int(args.get("frames", "45"))
	_orbit = args.has("orbit")
	_hold = args.has("hold")
	_start_sim(data, clampi(int(args.get("fighters", "2")), 1, 4), int(args.get("tick", "0")))
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
	_camera.make_current()


func _physics_process(_delta: float) -> void:
	if _hold:
		return
	sim.step(_neutral)
	_show()


func _process(delta: float) -> void:
	_time += delta
	if _orbit:
		var angle := _time * 0.18
		_camera.position = Vector3(sin(angle) * 11.0, 4.5, cos(angle) * 9.0)
		_camera.look_at(Vector3(0.0, 1.2, 0.0))
	_frames += 1
	if not _shot_path.is_empty() and _frames == _shot_frame:
		var image := get_viewport().get_texture().get_image()
		image.save_png(_shot_path)
		print("saved %s round_tick=%d draw_calls=%d primitives=%d" % [_shot_path, sim.state.round_tick,
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
		get_tree().quit()


func _start_sim(data: ArenaData, fighters: int, ticks: int) -> void:
	var config := SimConfig.new()
	config.arena = data
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
	for i in _dummies.size():
		_dummies[i].position = Fx.to_vec3(sim.state.fighters[i].pos) + Vector3(0.0, 0.9, 0.0)


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
