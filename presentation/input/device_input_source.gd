class_name DeviceInputSource
extends InputSource
## Captures the local keyboard, mouse and gamepad through the InputMap (DefaultBindings
## actions, design-lost-ark §2) and turns movement and aim into world space using the camera,
## so the sim never sees the camera or the cursor.
##
## Aim (SimInput aim field), following whichever device was used last:
## - Mouse: the cursor ray-cast onto the floor plane (y = 0), as a point relative to the
##   fighter. Not used while the mouse is captured.
## - Gamepad / keyboard only: the aim actions (right stick, arrow keys) if deflected, else
##   the movement direction, else no aim (the sim then falls back to the soft-lock target or
##   facing).
## Aim assist, the stick ground-target minimum and the lock-on override are the sim's job
## (Sim.aim_point): capture sends the raw cursor point or stick direction.

enum AimDevice { NONE, MOUSE, PAD }

const PAD_AXIS_DEADZONE := 0.35

## Camera whose yaw makes movement camera-relative. Without one, forward is world -Z.
var camera: Camera3D
## Device the aim currently follows.
var aim_device: AimDevice = AimDevice.NONE

var _last_mouse := Vector2(-1.0, -1.0)


func _init(view_camera: Camera3D = null) -> void:
	camera = view_camera


func next_frame(sim: Sim, slot: int) -> int:
	var move := move_vector()
	var frame := SimInput.from_vector(buttons(), move)
	if sim == null or slot >= sim.slot_count():
		return frame
	return _with_aim(frame, sim.fighter(slot), move)


## SimInput button bits held now.
static func buttons() -> int:
	var held := 0
	held |= _button(DefaultBindings.BASIC, SimInput.BASIC)
	held |= _button(DefaultBindings.DASH, SimInput.DASH)
	held |= _button(DefaultBindings.AWAKEN, SimInput.AWAKEN)
	held |= _button(DefaultBindings.LOCK_ON, SimInput.LOCK)
	held |= _button(DefaultBindings.TARGET_NEXT, SimInput.TARGET_NEXT)
	var skills := DefaultBindings.ability_actions()
	for i in mini(skills.size(), SimInput.SKILLS.size()):
		held |= _button(skills[i], SimInput.SKILLS[i])
	var chord := DefaultBindings.held_ability_chord()
	if chord > 0 and chord <= SimInput.SKILLS.size():
		held |= SimInput.SKILLS[chord - 1]
	return held


## Movement in world x/z (length = stick deflection).
func move_vector() -> Vector2:
	return to_world(Input.get_vector(DefaultBindings.MOVE_LEFT, DefaultBindings.MOVE_RIGHT,
			DefaultBindings.MOVE_BACK, DefaultBindings.MOVE_FORWARD, DefaultBindings.STICK_DEADZONE))


func _with_aim(frame: int, f: FighterState, move: Vector2) -> int:
	_update_aim_device()
	var stick := Input.get_vector(DefaultBindings.AIM_LEFT, DefaultBindings.AIM_RIGHT,
			DefaultBindings.AIM_DOWN, DefaultBindings.AIM_UP, DefaultBindings.STICK_DEADZONE)
	if aim_device == AimDevice.MOUSE:
		var ground: Variant = cursor_on_floor()
		if ground != null:
			var point: Vector3 = ground
			var offset := point - Fx.to_vec3(f.pos)
			return SimInput.with_aim_point(frame, Vector2(offset.x, offset.z))
	if stick != Vector2.ZERO:
		return SimInput.with_aim_direction(frame, to_world(stick).normalized())
	if move != Vector2.ZERO:
		return SimInput.with_aim_direction(frame, move)
	return frame


## The point on the floor plane (y = 0) under the mouse cursor, or null.
func cursor_on_floor() -> Variant:
	if camera == null or not camera.is_inside_tree() or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		return null
	var cursor := camera.get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(cursor)
	var normal := camera.project_ray_normal(cursor)
	if normal.y > -0.0001:
		return null
	return origin + normal * (-origin.y / normal.y)


## Switches the aim to the mouse when the cursor moves and to the pad when a pad stick moves.
func _update_aim_device() -> void:
	if camera != null and camera.is_inside_tree() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		var cursor := camera.get_viewport().get_mouse_position()
		if _last_mouse.x >= 0.0 and cursor.distance_squared_to(_last_mouse) > 1.0:
			aim_device = AimDevice.MOUSE
		_last_mouse = cursor
	for device in Input.get_connected_joypads():
		for axis: JoyAxis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y]:
			if absf(Input.get_joy_axis(device, axis)) > PAD_AXIS_DEADZONE:
				aim_device = AimDevice.PAD
				return


## Camera-relative stick (x right, y forward) to a world x-z direction.
func to_world(stick: Vector2) -> Vector2:
	var forward := Vector3(0.0, 0.0, -1.0)
	var right := Vector3(1.0, 0.0, 0.0)
	if camera != null and camera.is_inside_tree():
		var basis := camera.global_basis
		forward = Vector3(-basis.z.x, 0.0, -basis.z.z)
		right = Vector3(basis.x.x, 0.0, basis.x.z)
		if forward.length_squared() < 0.0001:
			forward = Vector3(basis.y.x, 0.0, basis.y.z)
		forward = forward.normalized()
		right = right.normalized()
	var world := right * stick.x + forward * stick.y
	return Vector2(world.x, world.z)


static func _button(action: StringName, bit: int) -> int:
	if Input.is_action_pressed(action) and not DefaultBindings.is_chord_consumed(action):
		return bit
	return 0
