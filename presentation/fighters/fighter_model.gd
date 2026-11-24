class_name FighterModel
extends Node3D
## Root of a fighter's presentation scene (FighterData.scene): a KayKit model restyled
## "stylized grim", posed by an AnimationTree that FighterView drives from sim state.
##
## Subclass per fighter for extras (embers, lantern, chains) and move-specific procedural
## poses: override _build_extras(), update_extras() and adjust_pose().

const GRIM_SHADER := preload("res://presentation/fighters/shaders/fighter_grim.gdshader")
const MOLTEN_SHADER := preload("res://presentation/fighters/shaders/molten_weapon.gdshader")
const HIP_HEIGHT := 0.75

@export var model: PackedScene
@export var model_scale: float = 0.78
## Meshes of the KayKit model to hide (spare weapons and shields).
@export var hide_meshes: PackedStringArray = []
## Props held in the hands (models without built-in weapons, e.g. skeletons).
@export var right_hand_prop: PackedScene
@export var left_hand_prop: PackedScene
## Colour of meshes without an atlas texture (skeleton eyes), drawn glowing.
@export var eye_color: Color = Color(0.45, 0.8, 1.0)

@export_group("Palette")
@export var tint: Color = Color(0.86, 0.88, 0.95)
@export_range(0.0, 1.0) var desaturate: float = 0.55
@export var brightness: float = 0.9
@export var contrast: float = 1.12
@export var rim_strength: float = 0.6
@export var rim_color: Color = Color(0.65, 0.75, 1.0)
## Atlas cell (row * 8 + column) -> tint; alpha = how much original saturation it keeps.
@export var cell_tints: Dictionary[int, Color] = {}
## Bitmask of glowing atlas cells (row * 8 + column).
@export var glow_cells: int = 0
@export var glow_color: Color = Color(1.0, 0.45, 0.12)
@export var glow_energy: float = 2.5
@export var glow_pulse: float = 0.0
## Shadow/ember look (Oath-Shade).
@export_range(0.0, 1.0) var shade: float = 0.0
@export var shade_edge: Color = Color(1.0, 0.35, 0.08)

@export_group("Wear")
## Dark dirt patches gathering toward the feet (0..1).
@export_range(0.0, 1.0) var grime: float = 0.0
@export var grime_color: Color = Color(0.07, 0.06, 0.05)
@export var grime_scale: float = 5.0
## Pale scratches (0..1).
@export_range(0.0, 1.0) var wear: float = 0.0
## Bitmask of atlas cells that crack open and glow (Aldric's Oathfire).
@export var seam_cells: int = 0
@export var seam_color: Color = Color(1.0, 0.35, 0.06)
@export var seam_energy: float = 2.5
@export var seam_scale: float = 4.0
@export var seam_width: float = 0.06
@export_range(0.0, 1.0) var seam_density: float = 0.5

@export_group("Weapon")
## Mesh that gets the molten-crack material (empty = none).
@export var molten_mesh: StringName = &""
@export var crack_color: Color = Color(1.0, 0.38, 0.08)
## Bone attachment node holding the weapon, and the trail segment in its local space.
@export var trail_attachment: StringName = &"handslot_r"
@export var trail_base: Vector3 = Vector3(0.0, 0.35, 0.0)
@export var trail_tip: Vector3 = Vector3(0.0, 1.35, 0.0)
@export var trail_color: Color = Color(1.0, 0.55, 0.2, 0.8)

@export_group("Effects")
## Colour of sparks when this fighter's attacks connect.
@export var spark_color: Color = Color(1.0, 0.6, 0.25)
## Signature colour of abilities and super effects.
@export var accent_color: Color = Color(1.0, 0.45, 0.12)
## Burns away into ash and embers when knocked out (Hollowed).
@export var ash_on_death: bool = false

@export_group("Animation")
@export var idle_clip: StringName = &"Idle"
@export var run_clip: StringName = &"Running_A"
@export var guard_clip: StringName = &"Blocking"

var rig: Node3D
var skeleton: Skeleton3D
var tree: AnimationTree
var body_material: ShaderMaterial
var weapon_material: ShaderMaterial
var trail_node: Node3D

var _eye_materials: Array[StandardMaterial3D] = []
var _anim_a: AnimationNodeAnimation
var _anim_b: AnimationNodeAnimation
var _built := false


func _ready() -> void:
	build()


## Builds the model, materials and animation tree (idempotent).
func build() -> void:
	if _built:
		return
	_built = true
	if model == null:
		push_error("FighterModel %s has no model" % name)
		return
	rig = model.instantiate()
	rig.name = "Model"
	rig.scale = Vector3.ONE * model_scale
	add_child(rig)
	skeleton = rig.find_child("Skeleton3D", true, false)
	_add_hand_prop(right_hand_prop, &"handslot.r", "handslot_r")
	_add_hand_prop(left_hand_prop, &"handslot.l", "handslot_l")
	_make_materials()
	_apply_materials(rig)
	trail_node = rig.find_child(String(trail_attachment), true, false) as Node3D
	_build_tree()
	_build_extras()


## Shows clip `a` at `time_a` blended with clip `b` at `time_b` by `weight_b` (crossfade).
func pose(a: StringName, time_a: float, b: StringName, time_b: float, weight_b: float) -> void:
	if tree == null:
		return
	if _anim_a.animation != a:
		_anim_a.animation = a
	if _anim_b.animation != b:
		_anim_b.animation = b
	tree.set(&"parameters/seek_a/seek_request", time_a)
	tree.set(&"parameters/seek_b/seek_request", time_b)
	tree.set(&"parameters/mix/blend_amount", clampf(weight_b, 0.0, 1.0))
	tree.advance(0.0)


## Hit / armour / parry flash on every material of the fighter.
func set_flash(color: Color, amount: float) -> void:
	for material: ShaderMaterial in [body_material, weapon_material]:
		if material != null:
			material.set_shader_parameter(&"flash_color", color)
			material.set_shader_parameter(&"flash_amount", amount)


## Debuff tint (chill, ash) on the body: colour and 0..1 amount.
func set_status(color: Color, amount: float) -> void:
	if body_material != null:
		body_material.set_shader_parameter(&"status_color", color)
		body_material.set_shader_parameter(&"status_amount", amount)


## Armor-buff sheen on the body (0..1).
func set_sheen(amount: float) -> void:
	if body_material != null:
		body_material.set_shader_parameter(&"sheen_amount", amount)


## Ash dissolve amount (0 = whole, 1 = gone) on every material of the fighter.
func set_dissolve(amount: float) -> void:
	if body_material != null:
		body_material.set_shader_parameter(&"dissolve", amount)
	for material in _eye_materials:
		material.albedo_color.a = 1.0 - amount
		material.emission_energy_multiplier = 3.0 * (1.0 - amount)
	visible = amount < 0.999


## World positions of the weapon trail segment (base, tip).
func trail_segment() -> PackedVector3Array:
	if trail_node == null:
		return PackedVector3Array()
	var xf := trail_node.global_transform
	return PackedVector3Array([xf * trail_base, xf * trail_tip])


## World position of a skeleton bone (e.g. &"chest", &"hand.r").
func bone_position(bone: StringName) -> Vector3:
	if skeleton == null:
		return global_position
	var index := skeleton.find_bone(bone)
	if index < 0:
		return global_position
	return skeleton.global_transform * skeleton.get_bone_global_pose(index).origin


## Attaches `node` to a bone (follows the animation).
func attach_to_bone(bone: StringName, node: Node3D) -> BoneAttachment3D:
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = bone
	skeleton.add_child(attachment)
	attachment.add_child(node)
	return attachment


## Per-fighter extras (particles, props, lights). Called once after the model is built.
func _build_extras() -> void:
	pass


## Per-frame extras driven by sim state (read only).
func update_extras(_sim: Sim, _f: FighterState, _delta: float) -> void:
	pass


## Per-fighter procedural tweaks to a pose (super poses, ability leans).
func adjust_pose(_sim: Sim, _f: FighterState, _pose: FighterPose, _sub: float) -> void:
	pass


func _make_materials() -> void:
	var atlas := _find_atlas(rig)
	body_material = ShaderMaterial.new()
	body_material.shader = GRIM_SHADER
	body_material.set_shader_parameter(&"atlas", atlas)
	body_material.set_shader_parameter(&"cell_tints", _cell_tint_texture())
	body_material.set_shader_parameter(&"tint", tint)
	body_material.set_shader_parameter(&"desaturate", desaturate)
	body_material.set_shader_parameter(&"brightness", brightness)
	body_material.set_shader_parameter(&"contrast", contrast)
	body_material.set_shader_parameter(&"rim_strength", rim_strength)
	body_material.set_shader_parameter(&"rim_color", rim_color)
	body_material.set_shader_parameter(&"glow_cells", glow_cells)
	body_material.set_shader_parameter(&"glow_color", glow_color)
	body_material.set_shader_parameter(&"glow_energy", glow_energy)
	body_material.set_shader_parameter(&"glow_pulse", glow_pulse)
	body_material.set_shader_parameter(&"shade_amount", shade)
	body_material.set_shader_parameter(&"shade_edge", shade_edge)
	body_material.set_shader_parameter(&"grime", grime)
	body_material.set_shader_parameter(&"grime_color", grime_color)
	body_material.set_shader_parameter(&"grime_scale", grime_scale)
	body_material.set_shader_parameter(&"wear", wear)
	body_material.set_shader_parameter(&"crack_cells", seam_cells)
	body_material.set_shader_parameter(&"crack_color", seam_color)
	body_material.set_shader_parameter(&"crack_energy", seam_energy)
	body_material.set_shader_parameter(&"crack_scale", seam_scale)
	body_material.set_shader_parameter(&"crack_width", seam_width)
	body_material.set_shader_parameter(&"crack_density", seam_density)
	if molten_mesh != &"":
		weapon_material = ShaderMaterial.new()
		weapon_material.shader = MOLTEN_SHADER
		weapon_material.set_shader_parameter(&"atlas", atlas)
		weapon_material.set_shader_parameter(&"crack_color", crack_color)


func _apply_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance: MeshInstance3D = node
		if mesh_instance.name in hide_meshes:
			mesh_instance.visible = false
		elif not _has_atlas(mesh_instance):
			mesh_instance.material_override = _eye_material()
		elif weapon_material != null and mesh_instance.name == molten_mesh:
			mesh_instance.material_override = weapon_material
		else:
			mesh_instance.mesh = _with_rest_positions(mesh_instance.mesh)
			mesh_instance.material_override = body_material
	for child in node.get_children():
		_apply_materials(child)


## A copy of `mesh` with each vertex's bind-pose position in CUSTOM0, so the body shader
## can pin grime and cracks to the surface while the skeleton animates it. Copies are
## shared between fighters through TreeCache.
static func _with_rest_positions(mesh: Mesh) -> Mesh:
	if mesh == null:
		return mesh
	var cache: Dictionary = TreeCache.get_or_make(&"fighter_rest_meshes", func() -> Dictionary: return {})
	if cache.has(mesh):
		return cache[mesh]
	var baked := ArrayMesh.new()
	var format := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var rest := PackedFloat32Array()
		rest.resize(vertices.size() * 4)
		for i in vertices.size():
			rest[i * 4] = vertices[i].x
			rest[i * 4 + 1] = vertices[i].y
			rest[i * 4 + 2] = vertices[i].z
		arrays[Mesh.ARRAY_CUSTOM0] = rest
		var flags := format
		if arrays[Mesh.ARRAY_BONES] != null and (arrays[Mesh.ARRAY_BONES] as PackedInt32Array).size() > vertices.size() * 4:
			flags |= Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		baked.add_surface_from_arrays(mesh.surface_get_primitive_type(s), arrays, [], {}, flags)
		baked.surface_set_material(s, mesh.surface_get_material(s))
	cache[mesh] = baked
	return baked


func _add_hand_prop(prop: PackedScene, bone: StringName, attachment_name: String) -> void:
	if prop == null or skeleton == null:
		return
	var attachment := skeleton.get_node_or_null(attachment_name) as BoneAttachment3D
	if attachment == null:
		attachment = BoneAttachment3D.new()
		attachment.name = attachment_name
		attachment.bone_name = bone
		skeleton.add_child(attachment)
	attachment.add_child(prop.instantiate())


func _has_atlas(mesh_instance: MeshInstance3D) -> bool:
	var mesh := mesh_instance.mesh
	if mesh == null or mesh.get_surface_count() == 0:
		return false
	var material := mesh.surface_get_material(0) as BaseMaterial3D
	return material != null and material.albedo_texture != null


func _eye_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_eye_materials.append(material)
	material.albedo_color = eye_color
	material.emission_enabled = true
	material.emission = eye_color
	material.emission_energy_multiplier = 3.0
	return material


func _find_atlas(node: Node) -> Texture2D:
	if node is MeshInstance3D:
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null and mesh.get_surface_count() > 0:
			var material := mesh.surface_get_material(0) as BaseMaterial3D
			if material != null and material.albedo_texture != null:
				return material.albedo_texture
	for child in node.get_children():
		var found := _find_atlas(child)
		if found != null:
			return found
	return null


func _cell_tint_texture() -> ImageTexture:
	var image := Image.create(8, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 0.0))
	for cell: int in cell_tints:
		image.set_pixel(cell % 8, cell / 8, cell_tints[cell])
	return ImageTexture.create_from_image(image)


func _build_tree() -> void:
	var blend := AnimationNodeBlendTree.new()
	_anim_a = AnimationNodeAnimation.new()
	_anim_b = AnimationNodeAnimation.new()
	_anim_a.animation = idle_clip
	_anim_b.animation = idle_clip
	blend.add_node(&"a", _anim_a, Vector2(0, 0))
	blend.add_node(&"b", _anim_b, Vector2(0, 200))
	blend.add_node(&"seek_a", AnimationNodeTimeSeek.new(), Vector2(200, 0))
	blend.add_node(&"seek_b", AnimationNodeTimeSeek.new(), Vector2(200, 200))
	blend.add_node(&"mix", AnimationNodeBlend2.new(), Vector2(400, 100))
	blend.connect_node(&"seek_a", 0, &"a")
	blend.connect_node(&"seek_b", 0, &"b")
	blend.connect_node(&"mix", 0, &"seek_a")
	blend.connect_node(&"mix", 1, &"seek_b")
	blend.connect_node(&"output", 0, &"mix")
	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	tree.add_animation_library(&"", FighterClips.library())
	tree.tree_root = blend
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	add_child(tree)
	tree.root_node = tree.get_path_to(rig)
	tree.active = true
