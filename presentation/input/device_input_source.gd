class_name DeviceInputSource
extends InputSource
## Captures the local keyboard, mouse buttons and gamepad through the InputMap
## (DefaultBindings action names) and turns movement into a world-space stick using the
## camera's yaw, so the sim never sees the camera.

## Camera whose yaw makes movement camera-relative. Without one, forward is world -Z.
var camera: Camera3D

var _flick_ready: bool = true


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
	var chord := DefaultBindings.held_ability_chord()
	if chord > 0:
		buttons |= SimInput.ABILITIES[chord - 1]
	if sim != null and slot < sim.slot_count() and sim.fighter(slot).hard_lock:
		var flick := absf(Input.get_axis(DefaultBindings.CAMERA_LEFT, DefaultBindings.CAMERA_RIGHT))
		if flick > 0.85 and _flick_ready:
			buttons |= SimInput.TARGET_NEXT
			_flick_ready = false
		elif flick < 0.4:
			_flick_ready = true
	var stick := Input.get_vector(DefaultBindings.MOVE_LEFT, DefaultBindings.MOVE_RIGHT,
			DefaultBindings.MOVE_BACK, DefaultBindings.MOVE_FORWARD, DefaultBindings.STICK_DEADZONE)
	return SimInput.from_vector(buttons, to_world(stick))


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
