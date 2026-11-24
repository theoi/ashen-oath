class_name EchoViews
extends Node3D
## Echo afterimages (sim-api "Echoes"): a smoky ember ghost of the caster appears at the cast
## position on ECHO, holds the move's first pose while the echo waits, plays the move from
## ECHO_CAST and burns away when the echo leaves state.echoes. Driven from state every frame,
## so rollback and restarts stay in step. Ghost models are pooled per fighter scene.

const FALLBACK_SCENE := "res://presentation/fighters/hollowed/hollowed.tscn"
## Seconds an echo takes to burn away after its move ends.
const FADE_TIME := 0.35
## How far the ghost burns through while it waits (the shader's dissolve, 0..1).
const WAITING_DISSOLVE := 0.25

var runner: MatchRunner

## Key "owner:cast" -> Ghost on screen.
var _ghosts: Dictionary[String, Ghost] = {}
var _pool: Array[Ghost] = []


class Ghost:
	var root: Node3D
	var pivot: Node3D
	var model: FighterModel
	var scene: String
	var fade := -1.0


func setup(match_runner: MatchRunner) -> void:
	runner = match_runner


## Number of ghosts on screen (fading ones included).
func ghost_count() -> int:
	return _ghosts.size()


func ghost_for(owner_slot: int, cast: int) -> FighterModel:
	var ghost: Ghost = _ghosts.get("%d:%d" % [owner_slot, cast])
	return ghost.model if ghost != null else null


func _process(delta: float) -> void:
	if runner == null or runner.sim == null:
		return
	var sim := runner.sim
	var live: Dictionary[String, bool] = {}
	for echo in sim.state.echoes:
		var key := "%d:%d" % [echo.owner, echo.cast]
		live[key] = true
		var ghost: Ghost = _ghosts.get(key)
		if ghost == null:
			ghost = _take(sim.fighter_data[echo.owner])
			_ghosts[key] = ghost
		_pose(ghost, sim, echo)
	for key: String in _ghosts.keys():
		if live.has(key):
			continue
		var ghost := _ghosts[key]
		if ghost.fade < 0.0:
			ghost.fade = 0.0
		ghost.fade += delta
		var t := clampf(ghost.fade / FADE_TIME, 0.0, 1.0)
		ghost.model.set_dissolve(lerpf(0.3, 1.0, t))
		if t >= 1.0:
			_ghosts.erase(key)
			ghost.root.visible = false
			_pool.append(ghost)


func _pose(ghost: Ghost, sim: Sim, echo: EchoState) -> void:
	ghost.fade = -1.0
	ghost.root.visible = true
	ghost.root.global_position = Fx.to_vec3(echo.pos)
	ghost.root.rotation = Vector3(0.0, Fx.angle_to_rad(echo.facing), 0.0)
	var move := sim.fighter_data[echo.owner].moves[echo.move_index]
	var clip := FighterPoser.attack_clip(move)
	var frame := 0.0 if echo.frame == 0 else float(echo.frame - 1) + clampf(runner.alpha(), 0.0, 1.0)
	ghost.model.pose(clip, FighterPoser.attack_time(move, clip, frame), clip, 0.0, 0.0)
	# Waiting: a faint smoky outline. Casting: solid ghost, burning away over the tail.
	var dissolve := WAITING_DISSOLVE if echo.frame == 0 else \
			lerpf(0.05, 0.3, clampf(float(echo.frame) / maxf(1.0, float(move.total_frames())), 0.0, 1.0))
	ghost.model.set_dissolve(dissolve)


func _take(data: FighterData) -> Ghost:
	var path := data.scene if data.scene != "" and ResourceLoader.exists(data.scene) else FALLBACK_SCENE
	for i in _pool.size():
		if _pool[i].scene == path:
			var reused := _pool[i]
			_pool.remove_at(i)
			return reused
	var ghost := Ghost.new()
	ghost.scene = path
	ghost.root = Node3D.new()
	ghost.root.name = "Echo"
	ghost.root.top_level = true
	add_child(ghost.root)
	ghost.pivot = Node3D.new()
	ghost.root.add_child(ghost.pivot)
	var body := Node3D.new()
	body.position.y = 0.0
	ghost.pivot.add_child(body)
	ghost.model = (load(path) as PackedScene).instantiate() as FighterModel
	# A smoky shade with an ember edge, whatever the caster looks like.
	ghost.model.shade = 1.0
	ghost.model.shade_edge = Color(1.0, 0.4, 0.12)
	body.add_child(ghost.model)
	ghost.model.build()
	ghost.model.set_status(Color(1.0, 0.35, 0.1), 0.6)
	_disable_shadows(ghost.model)
	return ghost


func _disable_shadows(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_disable_shadows(child)
