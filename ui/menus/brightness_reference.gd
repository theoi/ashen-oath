class_name BrightnessReference
extends SubViewportContainer
## Calibration swatch for the Brightness setting: a dim sword on black, rendered through the
## same filmic tonemap as the arenas, so it brightens and darkens with the setting.

## Linear albedo of the sword: just above black at the default brightness.
const SYMBOL_ALBEDO := 0.009
const SIZE := Vector2i(200, 72)


func _init() -> void:
	stretch = true
	custom_minimum_size = Vector2(SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var viewport := SubViewport.new()
	viewport.size = SIZE
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	viewport.add_child(world_env)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.15
	camera.position = Vector3(0.0, 0.0, 5.0)
	viewport.add_child(camera)

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(SYMBOL_ALBEDO, SYMBOL_ALBEDO, SYMBOL_ALBEDO).linear_to_srgb()
	# Sword pointing down: pommel, grip, crossguard, blade.
	for part: Array in [[Vector2(0.0, 0.47), Vector2(0.1, 0.08)], [Vector2(0.0, 0.36), Vector2(0.05, 0.16)],
			[Vector2(0.0, 0.26), Vector2(0.42, 0.06)], [Vector2(0.0, -0.08), Vector2(0.09, 0.62)]]:
		var box := BoxMesh.new()
		box.size = Vector3(part[1].x, part[1].y, 0.01)
		box.material = material
		var mesh := MeshInstance3D.new()
		mesh.mesh = box
		mesh.position = Vector3(part[0].x, part[0].y, 0.0)
		viewport.add_child(mesh)
