extends Node3D
## Dev line-up of fighter models in an arena under its real lighting, for look checks and
## before/after sheets (tools/capture_screenshot-style runs under Xvfb).
##
## User args (after `--`):
##   --arena=res://content/arenas/NAME.tres    arena to stand in (default: Ashen Chapel)
##   --fighters=aldric,morrigan,...            fighter ids (default: all five)
##   --clip=Idle_Combat --time=0.4             pose for every model
##   --souls=N                                 stored souls shown on Morrigan's lantern
##   --cam=px,py,pz,tx,ty,tz                   camera position and look target
##   --shot=PATH --frames=N                    save a PNG after N frames, then quit

const FIGHTERS := "res://content/fighters/%s/%s.tres"
const DEFAULT_ARENA := "res://content/arenas/ashen_chapel.tres"
const DEFAULT_IDS: Array[String] = ["aldric", "morrigan", "gorrath", "hollowed", "oath_shade"]

var _models: Array[FighterModel] = []
## One idle sim per model so update_extras() runs (lanterns, chains, embers).
var _sims: Array[Sim] = []
var _clip: StringName = &"Idle_Combat"
var _time := 0.4
var _frames := 0
var _shot_frame := 30
var _shot_path := ""


func _ready() -> void:
	var args := _parse_args()
	var data: ArenaData = load(args.get("arena", DEFAULT_ARENA))
	add_child((load(data.scene) as PackedScene).instantiate())
	_clip = StringName(args.get("clip", "Idle_Combat"))
	_time = float(args.get("time", "0.4"))
	_shot_path = args.get("shot", "")
	_shot_frame = int(args.get("frames", "30"))
	var ids: Array[String] = DEFAULT_IDS
	if args.has("fighters"):
		ids.assign(String(args["fighters"]).split(",", false))
	var spacing := 1.5
	for i in ids.size():
		var fighter: FighterData = load(FIGHTERS % [ids[i], ids[i]])
		var model := (load(fighter.scene) as PackedScene).instantiate() as FighterModel
		model.position = Vector3((float(i) - float(ids.size() - 1) * 0.5) * spacing, 0.0, 0.0)
		add_child(model)
		model.build()
		_models.append(model)
		var config := SimConfig.new()
		config.rules = load("res://content/rules/default_rules.tres")
		config.arena = data
		for k in 2:
			var slot := SlotConfig.new()
			slot.fighter = fighter
			slot.team = k
			config.slots.append(slot)
		var sim := Sim.new(config)
		sim.fighter(0).vars[0] = int(args.get("souls", "2"))
		_sims.append(sim)
	var camera := Camera3D.new()
	camera.fov = 45.0
	add_child(camera)
	var cam := PackedFloat64Array([0.0, 1.5, 6.2, 0.0, 0.85, 0.0])
	if args.has("cam"):
		cam = PackedFloat64Array(Array(String(args["cam"]).split(",")).map(func(s: String) -> float: return s.to_float()))
	camera.look_at_from_position(Vector3(cam[0], cam[1], cam[2]), Vector3(cam[3], cam[4], cam[5]))
	camera.make_current()


func _process(delta: float) -> void:
	_time += delta
	for i in _models.size():
		_models[i].pose(_clip, fmod(_time, FighterClips.length(_clip)), _clip, 0.0, 0.0)
		_models[i].update_extras(_sims[i], _sims[i].fighter(0), delta)
	_frames += 1
	if _shot_path != "" and _frames == _shot_frame:
		get_viewport().get_texture().get_image().save_png(_shot_path)
		get_tree().quit()


func _parse_args() -> Dictionary:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var parts := arg.trim_prefix("--").split("=", true, 1)
			args[parts[0]] = parts[1] if parts.size() > 1 else ""
	return args
