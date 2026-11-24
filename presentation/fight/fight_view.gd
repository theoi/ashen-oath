class_name FightView
extends Node3D
## A whole fight on screen: the arena scene, one FighterView per slot, the fight camera,
## FightFx and the MatchRunner that steps the sim. Either call start() with a SimConfig
## (FightView owns the runner) or show_match() with a runner you already started (a match screen
## that owns pause and HUD). HUDs read `runner.sim` and listen to `runner` signals.
##
## Presentation only. The sim runs at 60 Hz in the runner; everything here interpolates.

signal match_ended(winner_team: int)

const DEFAULT_ARENA_SCENE := "res://presentation/arenas/ashen_chapel/ashen_chapel.tscn"

var runner: MatchRunner
var arena: Node3D
var camera: FightCamera
var fx: FightFx
var views: Array[FighterView] = []


## Starts `config` with one input source per slot. `focus_slot` is the fighter the camera
## follows (the local player). `arena_scene` overrides ArenaData.scene when set.
func start(config: SimConfig, sources: Array[InputSource], focus_slot: int = 0, arena_scene: String = "") -> void:
	var own_runner := MatchRunner.new()
	own_runner.name = "MatchRunner"
	add_child(own_runner)
	own_runner.start(config, sources)
	show_match(own_runner, focus_slot, arena_scene)


## Shows a match driven by `match_runner` (already started). Device input sources get the
## fight camera so movement is camera-relative.
func show_match(match_runner: MatchRunner, focus_slot: int = 0, arena_scene: String = "") -> void:
	runner = match_runner
	var config := runner.sim.config
	var sources := runner.sources
	var scene_path := arena_scene
	if scene_path == "" and config.arena != null:
		scene_path = config.arena.scene
	if scene_path == "" or not ResourceLoader.exists(scene_path):
		scene_path = DEFAULT_ARENA_SCENE
	arena = (load(scene_path) as PackedScene).instantiate()
	add_child(arena)
	if arena is ArenaView:
		(arena as ArenaView).attach(runner)
	for slot in runner.sim.slot_count():
		var view := FighterView.new()
		add_child(view)
		view.setup(runner, slot)
		views.append(view)
	camera = FightCamera.new()
	camera.name = "FightCamera"
	add_child(camera)
	var bounds := config.arena.camera_bounds if config.arena != null else Rect2(-11.0, -9.0, 22.0, 18.0)
	camera.setup(runner, focus_slot, bounds)
	camera.make_current()
	if config.arena != null:
		ArenaCutaway.apply(arena, camera.yaw, config.arena.floor_polygon)
	for source in sources:
		if source is DeviceInputSource:
			(source as DeviceInputSource).camera = camera
	fx = FightFx.new()
	fx.name = "FightFx"
	add_child(fx)
	fx.setup(runner, views, camera)
	runner.match_ended.connect(func(team: int) -> void: match_ended.emit(team))

