class_name MatchResult
extends RefCounted
## How a match ended.

var config: MatchConfig
var winner_team := -1
## Rounds won per team.
var round_wins: Array[int] = []
var rounds_played := 0


## True when the local player's team (slot 0) won.
func player_won() -> bool:
	return config != null and not config.teams.is_empty() and winner_team == config.teams[0]
