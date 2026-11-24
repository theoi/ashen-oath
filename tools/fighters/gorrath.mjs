import { writeFighter, KIND, REACTION, ANCHOR, v3, sn } from './gen.mjs';

const repo = process.argv[2];
const axe = (reach = 2.0, y = 1.1, r = 0.6) => ({ offset: v3(0, y, 0.5), offset_end: v3(0, y, reach), capsule: true, radius: r });
// Trait Unbroken: every heavy absorbs one hit from frame 6 through its active frames at 50%.
const unbroken = (startup, active) => ({ armor_start: 6, armor_end: startup + active - 1, armor_hits: 1, armor_damage_percent: 50 });

export const moves = [
  { id: 'gorrath_l1', kind: KIND.LIGHT, startup: 8, active: 3, recovery: 14, animation: 'Unarmed_Melee_Attack_Punch_A', next_light: 'gorrath_l2', next_heavy: 'gorrath_lh',
    hitboxes: [{ ...axe(1.5, 1.2, 0.5), hit: { damage: 45, hitstun: 17, blockstun: 12, knockback: 0.4, cue: 'hit_heavy' } }] },
  { id: 'gorrath_l2', kind: KIND.LIGHT, startup: 8, active: 3, recovery: 15, animation: 'Unarmed_Melee_Attack_Punch_B', next_light: 'gorrath_l3', next_heavy: 'gorrath_llh',
    hitboxes: [{ ...axe(1.5, 1.2, 0.5), hit: { damage: 45, hitstun: 18, blockstun: 12, knockback: 0.4, cue: 'hit_heavy' } }] },
  { id: 'gorrath_l3', kind: KIND.LIGHT, startup: 15, active: 3, recovery: 20, animation: '2H_Melee_Attack_Chop',
    motions: [{ start_frame: 4, end_frame: 13, forward_speed: 2.5, stop_at_distance: 1.1 }],
    hitboxes: [{ ...axe(2.0, 1.0, 0.65), hit: { damage: 65, hitstun: 22, blockstun: 10, knockback: 1.8, block_pushback: 0.9, cue: 'hit_heavy_blade' } }] },
  { id: 'gorrath_llh', kind: KIND.HEAVY, startup: 18, active: 4, recovery: 26, animation: '2H_Melee_Attack_Slice', ...unbroken(18, 4),
    hitboxes: [{ ...axe(2.0, 1.2, 0.65), hit: { damage: 80, hitstun: 26, blockstun: 12, reaction: REACTION.LAUNCH, launch_height: 1.9, knockback: 0.4, juggle_cost: 2, cue: 'hit_heavy_blade' } }] },
  { id: 'gorrath_lh', kind: KIND.HEAVY, startup: 18, active: 4, recovery: 26, animation: '2H_Melee_Attack_Slice', ...unbroken(18, 4),
    hitboxes: [{ ...axe(2.1, 0.45, 0.6), hit: { damage: 85, hitstun: 22, blockstun: 12, reaction: REACTION.KNOCKDOWN, knockback: 1.4, cue: 'hit_heavy_blade' } }] },
  { id: 'gorrath_h1', kind: KIND.HEAVY, startup: 22, active: 5, recovery: 28, animation: '2H_Melee_Attack_Chop', next_heavy: 'gorrath_h2', ...unbroken(22, 5),
    chargeable: true, charge_frame: 12, charge_max: 40, charge_damage_percent: 50, full_charge_guard_break: true,
    motions: [{ start_frame: 14, end_frame: 22, forward_speed: 2.0, stop_at_distance: 1.1 }],
    hitboxes: [{ ...axe(2.1, 1.0, 0.7), hit: { damage: 120, hitstun: 28, blockstun: 16, knockback: 1.2, block_pushback: 0.8, cue: 'hit_heavy_blade' } }] },
  { id: 'gorrath_h2', kind: KIND.HEAVY, startup: 24, active: 5, recovery: 30, animation: '2H_Melee_Attack_Slice', ...unbroken(24, 5),
    motions: [{ start_frame: 8, end_frame: 24, forward_speed: 2.5, stop_at_distance: 1.1 }],
    hitboxes: [{ ...axe(2.2, 1.1, 0.7), hit: { damage: 130, hitstun: 30, blockstun: 16, knockback: 2.8, wall_splat: true, block_pushback: 1.0, cue: 'hit_heavy_blade' } }] },
  { id: 'gorrath_run_l', kind: KIND.LIGHT, startup: 10, active: 5, recovery: 20, animation: 'Unarmed_Melee_Attack_Punch_B',
    motions: [{ start_frame: 1, end_frame: 13, forward_speed: 11.0, stop_at_distance: 1.0 }],
    hitboxes: [{ ...axe(1.6, 1.2, 0.6), hit: { damage: 60, hitstun: 22, blockstun: 10, reaction: REACTION.KNOCKDOWN, knockback: 1.8, cue: 'hit_heavy' } }] },
  { id: 'gorrath_air_l1', kind: KIND.AIR_LIGHT, aerial: true, startup: 7, active: 3, recovery: 14, animation: 'Unarmed_Melee_Attack_Kick',
    hitboxes: [{ ...axe(1.5, 0.9, 0.6), hit: { damage: 40, hitstun: 20, blockstun: 10, knockback: 0.5, cue: 'hit_heavy' } }] },
  { id: 'gorrath_air_h', kind: KIND.AIR_HEAVY, aerial: true, startup: 14, active: 4, recovery: 12, landing_recovery: 18, gravity_percent: 180, animation: '2H_Melee_Attack_Chop',
    hitboxes: [{ offset: v3(0, 0.9, 0.6), offset_end: v3(0, 0.1, 1.6), capsule: true, radius: 0.65, hit: { damage: 95, hitstun: 22, blockstun: 12, reaction: REACTION.GROUND_BOUNCE, launch_height: 1.2, knockback: 0.5, juggle_cost: 2, cue: 'hit_heavy_blade' } }] },
  { id: 'gorrath_grab', kind: KIND.GRAB, startup: 7, active: 4, recovery: 30, animation: 'Unarmed_Melee_Attack_Punch_A', throw_move: 'gorrath_throw', hold_distance: 1.0,
    hitboxes: [{ offset: v3(0, 1.0, 0.5), offset_end: v3(0, 1.0, 1.3), capsule: true, radius: 0.5, hit: { damage: 0, throw: true, cue: 'grab' } }] },
  { id: 'gorrath_throw', kind: KIND.THROW, startup: 22, active: 2, recovery: 22, animation: 'Throw',
    hitboxes: [{ offset: v3(0, 1.0, 0.6), radius: 0.9, hit: { damage: 120, hitstun: 32, reaction: REACTION.KNOCKDOWN, knockback: 3.5, wall_splat: true, cue: 'hit_heavy' } }] },
  { id: 'gorrath_getup', kind: KIND.GETUP_ATTACK, startup: 16, active: 3, recovery: 24, invuln_start: 1, invuln_end: 10, animation: '2H_Melee_Attack_Slice',
    hitboxes: [{ ...axe(2.0, 0.8, 0.6), hit: { damage: 50, hitstun: 18, blockstun: 8, knockback: 1.2, cue: 'hit_heavy_blade' } }] },
  // --- Abilities -------------------------------------------------------------------------
  // 1: chain thrown 9 m straight. Hit on frame 14 leaves 25 frames of Gorrath's move, so
  // 39 f of hitstun puts him +14 with the target pulled point-blank.
  { id: 'chain_hook', kind: KIND.ABILITY, startup: 14, active: 4, recovery: 22, cooldown: 360, tracking: 3, animation: 'Throw', cue: 'chain_throw',
    hitboxes: [{ offset: v3(0, 1.1, 0.6), offset_end: v3(0, 1.1, 9.0), capsule: true, radius: 0.35, destroys_projectiles: false,
      hit: { damage: 40, hitstun: 39, blockstun: 14, guard_damage: 35, reaction: REACTION.PULL, pull_distance: 1.3, knockback: 0.0, block_pushback: 0.2, cue: 'hit_chain' } }] },
  // 2: overhead slam; a shockwave runs 6 m along the ground.
  { id: 'earthsplitter', kind: KIND.ABILITY, startup: 24, active: 3, recovery: 30, cooldown: 480, animation: '2H_Melee_Attack_Chop', cue: 'earthsplitter',
    effects: [{ id: 'earthsplitter_wave', spawn_frame: 24, anchor: ANCHOR.OWNER, offset: v3(0, 0, 0.9), speed: 30.0, travel: 5.2, radius: 0.9, height: 1.0, lifetime: 20,
      destroy_on_contact: true, destroyable: false, blocked_by_walls: true, projectile: false, cue: 'earthsplitter_wave',
      hit: { damage: 110, hitstun: 26, blockstun: 16, guard_damage: 50, reaction: REACTION.GROUND_BOUNCE, launch_height: 1.8, knockback: 0.4, cue: 'hit_heavy' } }] },
  // 3: armoured 8 m charge that carries the target into walls.
  { id: 'bull_rush', kind: KIND.ABILITY, startup: 10, active: 26, recovery: 26, cooldown: 420, animation: 'Block_Attack', cue: 'bull_rush',
    armor_start: 1, armor_end: 35, armor_hits: 2, armor_damage_percent: 100, tracking: 3,
    motions: [{ start_frame: 4, end_frame: 35, forward_speed: 15.0, homing: true }],
    hitboxes: [{ offset: v3(0, 1.1, 0.8), radius: 0.75, destroys_projectiles: false,
      hit: { damage: 80, hitstun: 30, blockstun: 14, knockback: 2.5, block_pushback: 1.2, carry_frames: 22, wall_splat: true, wall_splat_bonus: 40, cue: 'hit_heavy' } }] },
  // --- Super --------------------------------------------------------------------------------
  // Command grab: unblockable, beats attacks; only jumps and dodges escape it.
  { id: 'execution_chain', kind: KIND.SUPER, startup: 5, active: 3, recovery: 40, soul_cost: 100, flash_frames: 20, invuln_start: 1, invuln_end: 5,
    animation: 'Unarmed_Melee_Attack_Punch_A', cue: 'execution_chain', throw_move: 'execution_chain_slams', techable: false, hold_distance: 1.1,
    hitboxes: [{ offset: v3(0, 1.0, 0.5), offset_end: v3(0, 1.0, 2.0), capsule: true, radius: 0.55, hit: { damage: 0, throw: true, throw_beats_attacks: true, unblockable: true, parryable: false, cue: 'grab' } }] },
  { id: 'execution_chain_slams', kind: KIND.THROW, startup: 20, active: 45, recovery: 30, animation: '2H_Melee_Attack_Chop',
    hitboxes: [
      { start_frame: 20, end_frame: 20, group: 0, offset: v3(0, 1.0, 0.6), radius: 1.0, hit: { damage: 100, hitstun: 40, reaction: REACTION.STAGGER, knockback: 0.0, cue: 'hit_heavy_blade' } },
      { start_frame: 42, end_frame: 42, group: 1, offset: v3(0, 1.0, 0.6), radius: 1.0, hit: { damage: 100, hitstun: 40, reaction: REACTION.STAGGER, knockback: 0.0, cue: 'hit_heavy_blade' } },
      { start_frame: 64, end_frame: 64, group: 2, offset: v3(0, 1.0, 0.6), radius: 1.0, hit: { damage: 150, hitstun: 40, reaction: REACTION.LAUNCH, launch_height: 2.0, knockback: 3.0, wall_splat: true, cue: 'hit_heavy_blade' } },
    ] },
];

export const fighter = {
  id: 'gorrath', display_name: 'Gorrath', max_hp: 1150, radius: 0.55, height: 2.05, weight: 0.8,
  run_speed: 5.4, parry_window: 6,
  dodge_frames: 28, dodge_invuln_start: 3, dodge_invuln_end: 11, dodge_move_frames: 20,
  light: 'gorrath_l1', heavy: 'gorrath_h1', run_light: 'gorrath_run_l', air_light: 'gorrath_air_l1', air_heavy: 'gorrath_air_h',
  grab: 'gorrath_grab', getup_attack: 'gorrath_getup', abilities: sn('chain_hook', 'earthsplitter', 'bull_rush'), super_move: 'execution_chain',
  scene: 'res://presentation/fighters/gorrath/gorrath.tscn',
};

if (repo) writeFighter(repo, 'content/fighters/gorrath', 'gorrath.tres', fighter, moves);
