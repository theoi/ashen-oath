extends Node
## Autoload `Sound`: plays sound cues (see sound_cues.gd) from a small pool of players.
##
## Keeps playing while the tree is paused, so pause-menu sounds work. Pitch variation uses
## its own RNG: it is presentation only and never touches the simulation.

const UI_VOICES := 6
const SFX_VOICES := 20

var _streams: Dictionary[StringName, Array] = {}
var _ui_players: Array[AudioStreamPlayer] = []
var _sfx_players: Array[AudioStreamPlayer] = []
var _rng := RandomNumberGenerator.new()
var _quiet_focus_frame := -1
## Headless runs (tests, CI) have no audio output. Playbacks still running when they quit are
## reported as leaked objects, so headless runs pick and set up streams but never start them.
var _silent := DisplayServer.get_name() == "headless"
## The last cue played, for tests.
var last_cue: StringName


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in UI_VOICES:
		_ui_players.append(_make_player())
	for i in SFX_VOICES:
		_sfx_players.append(_make_player())
	get_viewport().gui_focus_changed.connect(_on_focus_changed)


func has_cue(id: StringName) -> bool:
	return SoundCues.TABLE.has(id)


## Plays `id`. Unknown ids are ignored so content can name cues before their files exist.
func play(id: StringName, volume_offset_db: float = 0.0) -> void:
	if not SoundCues.TABLE.has(id):
		return
	var row: Array = SoundCues.TABLE[id]
	var streams := _load(id, row[0])
	if streams.is_empty():
		return
	var bus: StringName = row[1]
	var player := _free_player(_ui_players if bus == SoundCues.UI else _sfx_players)
	player.stream = streams[_rng.randi_range(0, streams.size() - 1)]
	player.bus = bus
	player.volume_db = float(row[2]) + volume_offset_db
	var jitter: float = row[4]
	player.pitch_scale = float(row[3]) * (1.0 + _rng.randf_range(-jitter, jitter))
	last_cue = id
	if not _silent:
		player.play()


## Skips the focus "move" tick for focus changes made by code this frame (screens opening).
func quiet_focus_sound() -> void:
	_quiet_focus_frame = Engine.get_process_frames()


func _on_focus_changed(_control: Control) -> void:
	if Engine.get_process_frames() != _quiet_focus_frame:
		play(&"ui_move")


func _load(id: StringName, paths: Array) -> Array:
	if not _streams.has(id):
		var loaded: Array = []
		for path: String in paths:
			var stream := load(path) as AudioStream
			if stream != null:
				loaded.append(stream)
		_streams[id] = loaded
	return _streams[id]


func _make_player() -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	add_child(player)
	return player


func _free_player(pool: Array[AudioStreamPlayer]) -> AudioStreamPlayer:
	var oldest := pool[0]
	for player in pool:
		if not player.playing:
			return player
		if player.get_playback_position() > oldest.get_playback_position():
			oldest = player
	return oldest
