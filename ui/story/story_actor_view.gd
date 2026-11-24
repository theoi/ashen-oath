class_name StoryActorView
extends Node3D
## A fighter's in-game model held in a story pose: the fighter's presentation scene
## (FighterData.scene) posed with one clip of the shared KayKit animation set. While a
## fighter has no posable model yet, a capsule stand-in takes its place.

var fighter: StringName = &""
var clip: StringName = &"Idle"
## Seconds into the clip to hold; negative loops the clip.
var hold_time := -1.0
## The fighter's model root (FighterModel) when it exists, else null.
var model: Node3D

var _time := 0.0
var _settle := 0
var _stand_in: Node3D


func setup(id: StringName, pose_clip: StringName = &"Idle", time: float = -1.0) -> void:
	fighter = id
	var path := MatchSetup.fighter_data(id).scene
	if not path.is_empty() and ResourceLoader.exists(path):
		var node := (load(path) as PackedScene).instantiate() as Node3D
		if node != null and node.has_method("pose"):
			model = node
			add_child(model)
		elif node != null:
			node.free()
	if model == null:
		_stand_in = _make_stand_in(id)
		add_child(_stand_in)
	set_pose(pose_clip, time)


func is_stand_in() -> bool:
	return model == null


func set_pose(pose_clip: StringName, time: float = -1.0) -> void:
	clip = pose_clip if _has_clip(pose_clip) else &"Idle"
	hold_time = time
	_time = 0.0
	_settle = 0
	_apply()


## World position of the rig's head bone, at the base of the head (portrait framing).
func head_position() -> Vector3:
	if model != null and model.has_method("bone_position"):
		return model.call("bone_position", &"head")
	return global_position + Vector3(0.0, 1.36 * scale.y, 0.0)


func _process(delta: float) -> void:
	if model == null:
		return
	if hold_time < 0.0:
		_time += delta
		_apply()
	elif _settle < 3:
		# The animation tree's first updates can land after the first seek; hold the pose.
		_settle += 1
		_apply()


func _apply() -> void:
	if model != null:
		var length := _clip_length(clip)
		var t := fposmod(_time, length) if hold_time < 0.0 else clampf(hold_time, 0.0, maxf(length - 0.001, 0.0))
		model.call("pose", clip, t, clip, t, 0.0)
	elif _stand_in != null:
		_pose_stand_in()


func _mixer() -> AnimationMixer:
	return model.get("tree") as AnimationMixer if model != null else null


func _has_clip(name: StringName) -> bool:
	if model == null:
		return true
	var mixer := _mixer()
	return mixer != null and mixer.has_animation(name)


func _clip_length(name: StringName) -> float:
	var mixer := _mixer()
	if mixer == null or not mixer.has_animation(name):
		return 1.0
	return maxf(0.05, mixer.get_animation(name).length)


# --- Stand-in -----------------------------------------------------------------------------

func _make_stand_in(id: StringName) -> Node3D:
	var color: Color = Roster.fighter(id).get("color", Palette.BONE)
	var material := StandardMaterial3D.new()
	material.albedo_color = color.darkened(0.55)
	material.roughness = 0.7
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.18
	material.rim_enabled = true
	material.rim = 0.5
	var root := Node3D.new()
	root.name = "StandIn"
	var body := MeshInstance3D.new()
	body.name = "Body"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.38
	capsule.height = 1.5
	body.mesh = capsule
	body.material_override = material
	body.position.y = 0.75
	root.add_child(body)
	var head := MeshInstance3D.new()
	head.name = "Head"
	var sphere := SphereMesh.new()
	sphere.radius = 0.2
	sphere.height = 0.4
	head.mesh = sphere
	head.material_override = material
	head.position = Vector3(0.0, 1.62, 0.04)
	root.add_child(head)
	return root


## Lying, sitting or standing, from the clip name.
func _pose_stand_in() -> void:
	var name := String(clip)
	_stand_in.rotation = Vector3.ZERO
	_stand_in.position = Vector3.ZERO
	_stand_in.scale = Vector3.ONE
	if name.contains("Lie") or name.contains("Death"):
		_stand_in.rotation.x = -PI * 0.5
		_stand_in.position = Vector3(0.0, 0.38, 0.0)
	elif name.contains("Sit"):
		_stand_in.scale = Vector3(1.0, 0.62, 1.0)
	elif name.contains("Hit"):
		_stand_in.rotation.x = -0.25
