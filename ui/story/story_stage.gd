class_name StoryStage
extends Node3D
## The set for story stills: a dressed arena (its presentation scene), extra props, posed
## actors and a fixed camera. Presentation only; no sim runs here.

var camera: Camera3D
var arena: Node3D
var actors: Array[StoryActorView] = []

var _defs: Array[StoryActor] = []


func build(arena_id: StringName, actor_defs: Array[StoryActor], props: Array[StoryProp] = []) -> void:
	arena = _make_arena(arena_id)
	add_child(arena)
	if arena is ArenaView:
		for prop in props:
			_place_prop(arena as ArenaView, prop)
	_defs = actor_defs
	for def in actor_defs:
		var view := StoryActorView.new()
		add_child(view)
		view.position = def.position
		view.rotation_degrees.y = def.facing_degrees
		view.scale = Vector3.ONE * def.scale
		view.setup(def.fighter, def.pose, def.pose_time)
		actors.append(view)
	camera = Camera3D.new()
	camera.fov = 50.0
	add_child(camera)
	camera.make_current()
	set_shot(StoryShot.new())


func set_shot(shot: StoryShot) -> void:
	camera.fov = shot.fov
	camera.position = shot.position
	if not shot.position.is_equal_approx(shot.target):
		camera.look_at(shot.target)


## Shows the actors present at line `index`.
func show_line(index: int) -> void:
	for i in actors.size():
		actors[i].visible = _defs[i].is_present(index)


func _make_arena(arena_id: StringName) -> Node3D:
	if not arena_id.is_empty():
		var data := MatchSetup.arena_data(arena_id)
		var scene := MatchSetup.arena_scene(arena_id, data)
		if scene != null:
			return scene.instantiate() as Node3D
	return _darkness()


func _place_prop(view: ArenaView, prop: StoryProp) -> void:
	var path := (ArenaView.HALLOWEEN if prop.kit == StoryProp.Kit.HALLOWEEN else ArenaView.DUNGEON) % prop.model
	if not ResourceLoader.exists(path):
		push_warning("story prop %s not found" % path)
		return
	var node: Node3D
	if prop.kit == StoryProp.Kit.HALLOWEEN:
		node = view.halloween(prop.model, prop.position, prop.yaw_degrees, prop.scale)
	else:
		node = view.dungeon(prop.model, prop.position, prop.yaw_degrees, prop.scale)
	node.rotation_degrees.x = prop.rotation_degrees.x
	node.rotation_degrees.z = prop.rotation_degrees.z


## A black, faintly lit void for scenes without an arena.
func _darkness() -> Node3D:
	var root := Node3D.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.008, 0.012)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.3, 0.4)
	env.ambient_light_energy = 0.4
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	root.add_child(world_env)
	var light := DirectionalLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.35)
	light.rotation_degrees = Vector3(-35.0, 30.0, 0.0)
	root.add_child(light)
	return root
