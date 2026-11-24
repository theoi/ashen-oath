class_name AiDifficulty
extends Resource
## CPU opponent difficulty knobs (design §6). The four presets live in
## content/ai/difficulty/ and are loaded with AiDifficulty.preset(level). Chances are
## percent (0-100), times are 60 Hz frames.

## Same order as MatchConfig.Difficulty.
enum Level { EASY, NORMAL, HARD, NIGHTMARE }

const PRESET_PATHS: PackedStringArray = [
	"res://content/ai/difficulty/easy.tres",
	"res://content/ai/difficulty/normal.tres",
	"res://content/ai/difficulty/hard.tres",
	"res://content/ai/difficulty/nightmare.tres",
]

@export var level: Level = Level.NORMAL
@export var display_name: String = "Normal"

@export_group("Reaction")
## Frames between an attack becoming visible and the CPU responding to it.
@export var reaction_delay: int = 20
## Extra random delay, 0..jitter frames.
@export var reaction_jitter: int = 4
## Chance to respond at all (block, parry or dodge) to a visible attack.
@export_range(0, 100) var defend_chance: int = 50
## Of the responses: share attempted as a parry, then share done as a dodge (the rest block).
@export_range(0, 100) var parry_percent: int = 5
@export_range(0, 100) var dodge_percent: int = 25
## Chance per decision to raise guard pre-emptively when the opponent is close and acting.
@export_range(0, 100) var anticipate_guard_percent: int = 30
## Chance to keep blocking a string after the first blocked hit.
@export_range(0, 100) var hold_guard_percent: int = 50
## Air tech, tech roll and grab tech chance.
@export_range(0, 100) var tech_chance: int = 25

@export_group("Offense")
## Chance to punish an opponent's unsafe recovery when a move can reach it in time.
@export_range(0, 100) var punish_chance: int = 40
## 0 single hits, 1 basic strings, 2 strings + ability cancels, 3 optimal routes and juggles.
@export_range(0, 3) var combo_level: int = 1
## 0 never, 1 sometimes when in range, 2 when it should connect, 3 saved for punishes/combos.
@export_range(0, 3) var super_use: int = 1
## Chance to Soul Burst out of a combo when it has the meter.
@export_range(0, 100) var burst_chance: int = 30
## Minimum frames between offensive commitments outside combos.
@export var attack_gap: int = 24
## Scales offensive intent scores, percent.
@export var aggression: int = 100

@export_group("Skill kit")
## Ground-target aim error per axis, centimeters (design-lost-ark 1.10).
@export var aim_error_cm: int = 80
## Chance to answer a seen attack with a ready stance skill (Bulwark).
@export_range(0, 100) var stance_chance: int = 30
## Chance to fire a ready ⚡Counter skill into an opponent's counter window.
@export_range(0, 100) var counter_chance: int = 30
## Random error on the charge release, frames either side of the perfect zone's middle.
@export var charge_jitter: int = 10

@export_group("Noise")
## Frames between strategy decisions.
@export var strategy_period: int = 6
## Chance per strategy decision to hesitate (stand idle) for hesitation_ticks.
@export_range(0, 100) var hesitation_percent: int = 15
@export var hesitation_ticks: int = 20
## Chance to swing at an opponent slightly out of range.
@export_range(0, 100) var whiff_percent: int = 8
## Random spread added to movement direction, degrees.
@export var aim_noise_degrees: int = 15

@export_group("Crowd fights")
## Enemies on one team that may commit to an attack at the same time (1v2 fairness).
@export var attack_tokens: int = 1
## The same for wave enemies (design-lost-ark 5.4: 2, 3 on Hard, 4 on Nightmare).
@export var wave_attack_tokens: int = 2


## The preset for `level` (0 Easy .. 3 Nightmare), optionally capped (story fight 1 uses
## cap = Level.EASY so the tutorial fight stays Easy whatever difficulty was chosen).
static func preset(level_value: int, cap: int = -1) -> AiDifficulty:
	var index := clampi(level_value, 0, PRESET_PATHS.size() - 1)
	if cap >= 0:
		index = mini(index, cap)
	return load(PRESET_PATHS[index]) as AiDifficulty
