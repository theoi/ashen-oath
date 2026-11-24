extends Node3D
## Dev viewer for arena scenes: loads an arena, drives its sim tick at 60 Hz, places
## stand-in fighters for scale and frames it from preset cameras. Also used to render
## screenshots and clips headlessly under Xvfb.
##
## User args (after `--`):
##   --arena=res://...tscn   arena scene (default: Ashen Chapel)
##   --view=NAME             camera preset: overview, fight, low, east, west, top (default overview)
##   --cam=px,py,pz,tx,ty,tz custom camera position and look target
##   --orbit                 slowly orbit the arena (clips)
##   --tick=N                starting sim tick (hazard phases)
##   --dummies=N             stand-in fighters, 0-4 (default 2)
##   --shot=PATH             save a PNG after --frames frames, then quit
##   --frames=N              frames to wait before the shot (default 45)

const DEFAULT_ARENA := "res://presentation/arenas/ashen_chapel/ashen_chapel.tscn"
const DUMMY_SPOTS: Array[Vector3] = [Vector3(-3.0, 0.0, 0.5), Vector3(3.0, 0.0, -0.5), Vector3(4.5, 0.0, 3.0), Vector3(-4.5, 0.0, -3.0)]
## name -> [camera position, look target]
const VIEWS := {
	"overview": [Vector3(0.0, 7.2, 9.6), Vector3(0.0, 0.0, -2.5)],
	"fight": [Vector3(-1.5, 3.2, 8.5), Vector3(0.5, 1.1, -1.0)],
	"low": [Vector3(-9.0, 1.6, 7.0), Vector3(4.0, 1.8, -3.0)],
	"east": [Vector3(-8.0, 3.5, 2.0), Vector3(10.0, 2.0, -0.5)],
	"west": [Vector3(8.0, 3.5, -2.0), Vector3(-10.0, 2.5, 0.5)],
	"top": [Vector3(0.0, 30.0, 0.1), Vector3(0.0, 0.0, 0.0)],
}

var _arena: ArenaView
var _camera: Camera3D
var _tick := 0
var _frames := 0
var _shot_path := ""
var _shot_frame := 45
var _orbit := false
var _time := 0.0


func _ready() -> void:
	var args := _parse_args()
	var arena_path: String = args.get("arena", DEFAULT_ARENA)
	var scene: PackedScene = load(arena_path)
	_arena = scene.instantiate()
	add_child(_arena)
	_tick = int(args.get("tick", "0"))
	_shot_path = args.get("shot", "")
	_shot_frame = int(args.get("frames", "45"))
	_orbit = args.has("orbit")
	_add_dummies(clampi(int(args.get("dummies", "2")), 0, DUMMY_SPOTS.size()))
	_camera = Camera3D.new()
	_camera.fov = 55.0
	add_child(_camera)
	var view: Array = VIEWS.get(args.get("view", "overview"), VIEWS["overview"])
	if args.has("cam"):
		view = _parse_cam(args["cam"])
	_camera.position = view[0]
	_camera.look_at(view[1])
	_camera.make_current()
	_arena.set_sim_tick(_tick)


func _physics_process(_delta: float) -> void:
	_tick += 1
	_arena.set_sim_tick(_tick)


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
		print("saved %s draw_calls=%d objects=%d primitives=%d" % [_shot_path,
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
		get_tree().quit()


func _add_dummies(count: int) -> void:
	var armor := StandardMaterial3D.new()
	armor.albedo_color = Color(0.45, 0.42, 0.4)
	armor.roughness = 0.6
	armor.rim_enabled = true
	armor.rim = 0.6
	for i in count:
		var body := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.4
		capsule.height = 1.8
		body.mesh = capsule
		body.material_override = armor
		body.position = DUMMY_SPOTS[i] + Vector3(0.0, 0.9, 0.0)
		add_child(body)


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
