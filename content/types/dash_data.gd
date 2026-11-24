class_name DashData
extends Resource
## The skill-kit dash (design-lost-ark §1.4). Setting FighterData.dash makes the fighter a
## skill-kit fighter: DASH dashes instead of rolling, bursts in hitstun / grabbed / wall
## splat, and quick-rises from knockdown. Frames count from 1 = the tick the dash starts.

## Dash charges; spent charges come back one at a time, `recharge_frames` each.
@export var charges: int = 2
@export var recharge_frames: int = 240
## Total length, travel included.
@export var frames: int = 18
## Frames spent moving (the rest is recovery).
@export var travel_frames: int = 12
@export var distance: float = 4.5
@export var invuln_start: int = 1
@export var invuln_end: int = 10
## From this frame, skills, the basic attack, the awakening and another dash can start.
@export var skill_cancel_frame: int = 8
## A hit dodged within this many frames of invuln_start is a perfect dash.
@export var perfect_frames: int = 5

@export_group("Quick rise")
## Knockdown frames before DASH can quick-rise (keeps OTG follow-ups possible).
@export var rise_after: int = 10
@export var rise_frames: int = 20
@export var rise_invuln: int = 14
## Roll distance toward the stick (stands in place without stick input).
@export var rise_distance: float = 2.0
