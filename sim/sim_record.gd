class_name SimRecord
extends RefCounted
## Base for plain-data sim state.
##
## Every script variable whose name does not start with "_" is state: it is copied by
## copy_from()/clone() and fed to the checksum, in declaration order. Allowed field types:
## int, bool, Vector3i, PackedInt32Array and Array of SimRecord. No floats (see Fx), no
## object references other than owned SimRecords, so a state can be copied and compared.

static var _fields_cache: Dictionary[Script, Array] = {}


func fields() -> Array[StringName]:
	var script: Script = get_script()
	var cached: Array = _fields_cache.get(script, [])
	if not cached.is_empty():
		var typed: Array[StringName] = []
		typed.assign(cached)
		return typed
	var names: Array[StringName] = []
	for prop in script.get_script_property_list():
		var usage: int = prop["usage"]
		var prop_name: String = prop["name"]
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE and not prop_name.begins_with("_"):
			names.append(StringName(prop_name))
	_fields_cache[script] = names
	return names


## Makes this record equal to `other` (same script), reusing nested records in place.
func copy_from(other: SimRecord) -> void:
	for field in fields():
		var value: Variant = other.get(field)
		match typeof(value):
			TYPE_ARRAY:
				_copy_records(get(field), value)
			TYPE_PACKED_INT32_ARRAY:
				var packed: PackedInt32Array = value
				set(field, packed.duplicate())
			_:
				set(field, value)


func clone() -> SimRecord:
	var copy: SimRecord = (get_script() as Script).new()
	copy.copy_from(self)
	return copy


## Appends every field as integers (arrays prefixed by their size) for checksums.
func write_ints(out: PackedInt64Array) -> void:
	for field in fields():
		var value: Variant = get(field)
		match typeof(value):
			TYPE_INT:
				out.append(value)
			TYPE_BOOL:
				out.append(1 if value else 0)
			TYPE_VECTOR3I:
				var v: Vector3i = value
				out.append(v.x)
				out.append(v.y)
				out.append(v.z)
			TYPE_PACKED_INT32_ARRAY:
				var packed: PackedInt32Array = value
				out.append(packed.size())
				for item in packed:
					out.append(item)
			TYPE_ARRAY:
				var records: Array = value
				out.append(records.size())
				for record: SimRecord in records:
					record.write_ints(out)
			_:
				push_error("SimRecord field %s has unsupported type %s" % [field, type_string(typeof(value))])


static func _copy_records(target: Array, source: Array) -> void:
	if target.size() > source.size():
		target.resize(source.size())
	for i in source.size():
		var from: SimRecord = source[i]
		if i < target.size():
			var to: SimRecord = target[i]
			if to.get_script() != from.get_script():
				target[i] = from.clone()
			else:
				to.copy_from(from)
		else:
			target.append(from.clone())
