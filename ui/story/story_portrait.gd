class_name StoryPortrait
extends SubViewport
## A dialogue portrait rendered live from the fighter's in-game model: its own small 3D
## world with the model idling, framed on the head and lit with an ember key and a cold rim.

const SIZE := Vector2i(256, 256)
## The rig's "head" bone sits at the neck; the (large) KayKit head is above it.
const HEAD_CENTER := 0.26
const DISTANCE := 1.45

var fighter: StringName = &""
var actor: StoryActorView
var camera: Camera3D


func _init() -> void:
	own_world_3d = true
	transparent_bg = true
	size = SIZE
	render_target_update_mode = SubViewport.UPDATE_ALWAYS


func setup(id: StringName) -> void:
	fighter = id
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.36, 0.45)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.68, 0.45)
	key.light_energy = 1.1
	key.rotation_degrees = Vector3(-25.0, 35.0, 0.0)
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(0.5, 0.62, 1.0)
	rim.light_energy = 1.4
	rim.rotation_degrees = Vector3(-15.0, 200.0, 0.0)
	add_child(rim)
	actor = StoryActorView.new()
	actor.rotation_degrees.y = 18.0
	add_child(actor)
	actor.setup(id, &"Idle")
	camera = Camera3D.new()
	camera.fov = 30.0
	add_child(camera)
	camera.current = true
	frame()


## Points the camera at the model's head.
func frame() -> void:
	var face := actor.head_position() + Vector3(0.0, HEAD_CENTER, 0.0)
	camera.position = face + Vector3(0.0, 0.05, DISTANCE)
	camera.look_at(face + Vector3(0.0, -0.06, 0.0))


func _process(_delta: float) -> void:
	if actor != null and not actor.is_stand_in():
		frame()
