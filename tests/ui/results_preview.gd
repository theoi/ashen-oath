extends Node
## Dev view of the versus results screen over the menu backdrop, for screenshots:
##   SCENE=res://tests/ui/results_preview.tscn tools/capture_screenshot.sh /tmp/results.png 30

const BACKDROP := preload("res://presentation/menu_backdrop/menu_backdrop.tscn")


func _ready() -> void:
	add_child(BACKDROP.instantiate())
	var config := MatchConfig.versus(&"aldric", &"gorrath", &"drowned_crypt", MatchConfig.Difficulty.HARD)
	var result := MatchResult.new()
	result.config = config
	result.winner_team = 0
	result.round_wins = [2, 1]
	result.rounds_played = 3
	GameFlow.current_match = config
	GameFlow.last_result = result
	var layer := CanvasLayer.new()
	add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.008, 0.012, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var screens := ScreenStack.new()
	layer.add_child(screens)
	screens.set_screens([&"results"])
