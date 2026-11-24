extends Node3D
## Fight sandbox: a real match in a real arena with real fighters, for development, clips
## and the look-and-feel check-in. Slot 0 is the local player unless --cpu1 is given.
##
## User args (after `--`):
##   --p1=aldric --p2=hollowed     fighter ids (content/fighters/<id>/<id>.tres)
##   --arena=res://content/arenas/ashen_chapel.tres
##   --cpu1                        slot 0 is a sparring CPU too (attract mode, clips)
##   --demo                        slot 0 plays Aldric's kit on a loop (ShowcaseInputSource)
##   --seed=N                      RNG seed for the sim and the sparring CPUs
##   --soul=N                      starting Soul for both fighters (super demos)
##   --shot=PATH --frames=N        save a PNG after N frames, then quit
##   --every=N                     with --shot=DIR: save DIR/shot_<frame>.png every N frames
##   --spectator                   side-on spectator camera instead of over the shoulder
##   --side                        fixed side camera on the fighters (model checks)

const FIGHTERS := "res://content/fighters/%s/%s.tres"
const DEFAULT_ARENA := "res://content/arenas/ashen_chapel.tres"

var fight: FightView
var _shot_path := ""
var _shot_frame := 0
var _shot_every := 0
var _frames := 0
var _hud: Label
var _side_camera: Camera3D


func _ready() -> void:
	var args := _parse_args()
	var config := SimConfig.new()
	config.rules = load("res://content/rules/default_rules.tres")
	config.arena = load(args.get("arena", DEFAULT_ARENA))
	config.seed = int(args.get("seed", "7"))
	var ids: Array[String] = [args.get("p1", "aldric"), args.get("p2", "hollowed")]
	for i in ids.size():
		var slot := SlotConfig.new()
		slot.fighter = load(FIGHTERS % [ids[i], ids[i]])
		slot.team = i
		slot.start_soul = int(args.get("soul", "0"))
		config.slots.append(slot)
	var sources: Array[InputSource] = []
	var cpu1 := args.has("cpu1") or args.has("demo")
	if args.has("demo"):
		sources.append(ShowcaseInputSource.aldric())
	elif cpu1:
		sources.append(SparringInputSource.new(config.seed * 31 + 1))
	else:
		sources.append(DeviceInputSource.new())
	sources.append(SparringInputSource.new(config.seed * 17 + 5))
	fight = FightView.new()
	add_child(fight)
	fight.start(config, sources, 0)
	fight.camera.player_control = not cpu1
	fight.camera.spectator = args.has("spectator")
	if not cpu1 and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_shot_path = args.get("shot", "")
	_shot_frame = int(args.get("frames", "90"))
	_shot_every = int(args.get("every", "0"))
	_build_hud()
	if args.has("side"):
		_side_camera = Camera3D.new()
		_side_camera.fov = 40.0
		add_child(_side_camera)
		_side_camera.make_current()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED


func _process(_delta: float) -> void:
	_frames += 1
	if _side_camera != null:
		var a := fight.runner.fighter_position(0)
		var b := fight.runner.fighter_position(1)
		var mid := (a + b) * 0.5 + Vector3.UP * 0.9
		var axis := (b - a).normalized()
		var side := Vector3(-axis.z, 0.0, axis.x)
		_side_camera.global_position = mid + side * 6.5 + Vector3.UP * 0.6
		_side_camera.look_at(mid, Vector3.UP)
	_update_hud()
	if _shot_path != "" and _shot_every > 0 and _frames % _shot_every == 0:
		get_viewport().get_texture().get_image().save_png("%s/shot_%05d.png" % [_shot_path, _frames])
	if _shot_path != "" and _frames == _shot_frame:
		if _shot_every > 0:
			get_tree().quit()
			return
		get_viewport().get_texture().get_image().save_png(_shot_path)
		print("saved ", _shot_path)
		get_tree().quit()


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(24, 16)
	_hud.add_theme_font_size_override(&"font_size", 18)
	layer.add_child(_hud)


func _update_hud() -> void:
	var sim := fight.runner.sim
	var parts := PackedStringArray()
	for f in sim.state.fighters:
		var data := sim.fighter_data[f.slot]
		parts.append("%s  HP %d/%d  Soul %d  Guard %d" % [data.display_name, f.hp, f.max_hp, f.soul_points(), f.guard_points()])
	_hud.text = "   |   ".join(parts)


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
