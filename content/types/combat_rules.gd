class_name CombatRules
extends Resource
## Universal combat numbers (design §2). Frames are 60 Hz ticks, distances meters.
## content/rules/default_rules.tres holds the tuned values.

@export_group("Input")
@export var buffer_frames: int = 8

## Frames after the last active frame in which lights/heavies can be cancelled into
## abilities on contact (and abilities into supers on hit).
@export var cancel_window_frames: int = 12

@export_group("Movement")
@export var landing_frames: int = 3
@export var whiff_landing_frames: int = 14
## Gravity for launched/juggled fighters, m/s².
@export var juggle_gravity: float = 26.0
## Fighters push each other apart at this fraction of the overlap per frame (percent).
@export var body_push_percent: int = 50

@export_group("Targeting")
@export var light_tracking: float = 8.0
@export var heavy_tracking: float = 3.0
@export var ability_tracking: float = 5.0
## Attacks snap to the nearest enemy within this half-angle of the stick...
@export var soft_lock_cone: float = 60.0
## ...or the nearest enemy overall within this range.
@export var soft_lock_range: float = 12.0

@export_group("Guard")
@export var guard_arc: float = 200.0
@export var guard_startup: int = 2
@export var guard_speed_percent: int = 40
@export var guard_gauge: int = 100
@export var guard_damage_light: int = 8
@export var guard_damage_heavy: int = 22
@export var guard_damage_ability: int = 25
@export var guard_damage_super: int = 40
@export var guard_regen_delay: int = 45
@export var guard_regen_per_second: int = 30
@export var guard_break_frames: int = 60
@export var chip_ability_percent: int = 12
@export var chip_super_percent: int = 20

@export_group("Parry")
@export var parry_lockout: int = 20
@export var parry_stagger: int = 24
@export var parry_soul: int = 10
@export var parry_guard_refill: int = 20

@export_group("Hitstop")
@export var hitstop_light: int = 5
@export var hitstop_heavy: int = 9
@export var hitstop_ability: int = 8
@export var hitstop_super: int = 10
@export var hitstop_super_final: int = 16

@export_group("Counter hits")
@export var counter_hitstun_percent: int = 150
@export var counter_damage_percent: int = 115

@export_group("Juggles and knockdown")
@export var juggle_points: int = 6
## Minimum pop for hits on airborne victims without a launch height, meters.
@export var juggle_pop: float = 0.6
@export var air_tech_invuln: int = 10
@export var air_tech_frames: int = 14
@export var knockdown_frames: int = 40
@export var tech_roll_window: int = 6
@export var tech_roll_frames: int = 20
@export var tech_roll_distance: float = 2.5
@export var getup_stand_frames: int = 20
@export var getup_stand_invuln: int = 12
@export var getup_roll_frames: int = 26
@export var getup_roll_invuln: int = 16
@export var getup_roll_distance: float = 2.5
@export var wall_splat_frames: int = 30
## Knockback speed (m/s) needed for a wall_splat hit to splat on contact.
@export var wall_splat_min_speed: float = 3.0
@export var grab_tech_window: int = 10
@export var grab_tech_push: float = 1.5
@export var grab_tech_stun: int = 16
@export var grab_whiff_recovery: int = 30

@export_group("Scaling")
## Hits before scaling starts (hits 1-2 at 100%).
@export var scaling_free_hits: int = 2
@export var scaling_step_percent: int = 10
@export var scaling_floor_percent: int = 40
@export var super_scaling_floor_percent: int = 60
@export var combo_decay_frames: int = 240
@export var combo_decay_hitstun_percent: int = 50

@export_group("Soul")
@export var soul_max: int = 100
@export var soul_per_100_dealt: int = 8
@export var soul_per_100_taken: int = 6
@export var perfect_dodge_soul: int = 5
## Perfect dodge: hit connects within this many frames of the first invincible frame.
@export var perfect_dodge_frames: int = 4
@export var super_cost: int = 100
@export var super_flash_frames: int = 20
@export var burst_cost: int = 50
@export var burst_frames: int = 30
@export var burst_invuln: int = 20
@export var burst_radius: float = 4.0
@export var burst_knockback: float = 4.0

@export_group("Rounds")
@export var round_seconds: int = 99
@export var rounds_to_win: int = 2
@export var round_intro_frames: int = 90
@export var round_end_frames: int = 150
@export var ko_slowdown_frames: int = 0
