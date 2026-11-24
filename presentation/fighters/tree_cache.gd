class_name TreeCache
extends RefCounted
## Process-wide cache for presentation resources, stored as metadata on the SceneTree.
##
## Use this instead of a `static var` holding a Resource: in Godot 4.7.2 static Resource
## vars are released after the engine has shut down and crash on quit ("double free").
## The SceneTree is freed early in shutdown, taking these with it.


## The value cached under `key`, built with `make` on first use. Without a SceneTree the
## value is built every call and not cached.
static func get_or_make(key: StringName, make: Callable) -> Variant:
	var tree := Engine.get_main_loop()
	if tree == null:
		return make.call()
	if not tree.has_meta(key):
		tree.set_meta(key, make.call())
	return tree.get_meta(key)
