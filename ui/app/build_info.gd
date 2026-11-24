class_name BuildInfo
extends RefCounted
## Build label from res://build_info.json (written by tools/export_web.sh; absent in editor runs).

## Printed once the first screen has rendered; web smoke tests wait for it in the browser console.
const READY_MARKER := "ASHEN_OATH_READY"
const PATH := "res://build_info.json"


static func label() -> String:
	if not FileAccess.file_exists(PATH):
		return "dev build"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if parsed is not Dictionary:
		return "unknown build"
	var info: Dictionary = parsed
	return "build %s (%s)" % [info.get("commit", "?"), info.get("date", "?")]
