class_name DeviceInputSource
extends InputSource
## Captures the local keyboard, mouse and gamepad through the InputMap (DefaultBindings
## action names) and turns movement and aim into world space using the camera, so the sim
## never sees the camera or the cursor.
##
## Aim (SimInput aim field), following whichever device was used last:
## - Mouse: the cursor ray-cast onto the floor plane (y = 0), as a point relative to the
##   fighter. Not used while the mouse is captured.
## - Gamepad / keyboard only: the right stick (camera actions) if deflected, else the
##   movement direction, else no aim (the sim then falls back to the soft-lock target or
##   facing).

enum AimDevice { NONE, MOUSE, PAD }

## Optional skill-kit actions; read when the InputMap has them. Slot i sets SimInput.SKILLS[i].
const SKILL_ACTIONS: Array[StringName] = [&"skill_1", &"skill_2", &"skill_3", &"skill_4", &"skill_5", &"skill_6"]
const BASIC_ACTION := &"basic_attack"
const DASH_ACTION := &"dash"
const AWAKEN_ACTION := &"awaken"
const PAD_AXIS_DEADZONE := 0.35

## Camera whose yaw makes movement camera-relative. Without one, forward is world -Z.
var camera: Camera3D
## Device the aim currently follows.
var aim_device: AimDevice = AimDevice.NONE

var _flick_ready: bool = true
var _last_mouse := Vector2(-1.0, -1.0)


func _init(view_camera: Camera3D = null) -> void:
	camera = view_camera


func next_frame(sim: Sim, slot: int) -> int:
	var buttons := 0
	buttons |= _button(DefaultBindings.LIGHT, SimInput.LIGHT)
	buttons |= _button(DefaultBindings.HEAVY, SimInput.HEAVY)
	buttons |= _button(DefaultBindings.DODGE, SimInput.DODGE)
	buttons |= _button(DefaultBindings.JUMP, SimInput.JUMP)
	buttons |= _button(DefaultBindings.GUARD, SimInput.GUARD)
	buttons |= _button(DefaultBindings.GRAB, SimInput.GRAB)
	buttons |= _button(DefaultBindings.ABILITY_1, SimInput.ABILITY_1)
	buttons |= _button(DefaultBindings.ABILITY_2, SimInput.ABILITY_2)
	buttons |= _button(DefaultBindings.ABILITY_3, SimInput.ABILITY_3)
	buttons |= _button(DefaultBindings.SUPER, SimInput.SUPER)
	buttons |= _button(DefaultBindings.LOCK_ON, SimInput.LOCK)
	buttons |= _optional(BASIC_ACTION, SimInput.BASIC)
	buttons |= _optional(DASH_ACTION, SimInput.DASH)
	buttons |= _optional(AWAKEN_ACTION, SimInput.AWAKEN)
	for i in SKILL_ACTIONS.size():
		buttons |= _optional(SKILL_ACTIONS[i], SimInput.SKILLS[i])
	var chord := DefaultBindings.held_ability_chord()
	if chord > 0:
		buttons |= SimInput.ABILITIES[chord - 1]
	var hard_lock := sim != null and slot < sim.slot_count() and sim.fighter(slot).hard_lock
	if hard_lock:
		var flick := absf(Input.get_axis(DefaultBindings.CAMERA_LEFT, DefaultBindings.CAMERA_RIGHT))
		if flick > 0.85 and _flick_ready:
			buttons |= SimInput.TARGET_NEXT
			_flick_ready = false
		elif flick < 0.4:
			_flick_ready = true
	var stick := Input.get_vector(DefaultBindings.MOVE_LEFT, DefaultBindings.MOVE_RIGHT,
			DefaultBindings.MOVE_BACK, DefaultBindings.MOVE_FORWARD, DefaultBindings.STICK_DEADZONE)
	var move := to_world(stick)
	var frame := SimInput.from_vector(buttons, move)
	if sim == null or slot >= sim.slot_count():
		return frame
	return _with_aim(frame, sim.fighter(slot), move)


func _with_aim(frame: int, f: FighterState, move: Vector2) -> int:
	_update_aim_device()
	var right := Input.get_vector(DefaultBindings.CAMERA_LEFT, DefaultBindings.CAMERA_RIGHT,
			DefaultBindings.CAMERA_DOWN, DefaultBindings.CAMERA_UP, DefaultBindings.STICK_DEADZONE)
	if aim_device == AimDevice.MOUSE:
		var ground: Variant = cursor_on_floor()
		if ground != null:
			var point: Vector3 = ground
			var offset := point - Fx.to_vec3(f.pos)
			return SimInput.with_aim_point(frame, Vector2(offset.x, offset.z))
	if right != Vector2.ZERO:
		return SimInput.with_aim_direction(frame, to_world(right).normalized())
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


static func _optional(action: StringName, bit: int) -> int:
	return bit if InputMap.has_action(action) and Input.is_action_pressed(action) else 0
