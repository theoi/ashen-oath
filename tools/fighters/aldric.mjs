import { writeFighter, KIND, REACTION, COND, INTO, ANCHOR, v3, color, sn } from './gen.mjs';

const repo = process.argv[2];
const CHEST = 1.1;
// Sword arc in front: capsule from the hip-side to blade reach.
const slash = (reach = 1.6, y = CHEST, r = 0.5) => ({ offset: v3(0, y, 0.45), offset_end: v3(0, y, reach), capsule: true, radius: r });

const L = (o) => ({ kind: KIND.LIGHT, ...o });

export const moves = [
  L({ id: 'aldric_l1', startup: 6, active: 3, recovery: 12, animation: '1H_Melee_Attack_Slice_Diagonal', next_light: 'aldric_l2', next_heavy: 'aldric_lh',
    hitboxes: [{ ...slash(1.65), hit: { damage: 35, hitstun: 16, blockstun: 12, knockback: 0.35, cue: 'hit_blade' } }] }),
  L({ id: 'aldric_l2', startup: 6, active: 3, recovery: 13, animation: '1H_Melee_Attack_Slice_Horizontal', next_light: 'aldric_l3', next_heavy: 'aldric_llh',
    hitboxes: [{ ...slash(1.7), hit: { damage: 35, hitstun: 17, blockstun: 12, knockback: 0.35, cue: 'hit_blade' } }] }),
  L({ id: 'aldric_l3', startup: 13, active: 3, recovery: 18, animation: '1H_Melee_Attack_Chop',
    motions: [{ start_frame: 4, end_frame: 12, forward_speed: 3.0, stop_at_distance: 1.0 }],
    hitboxes: [{ ...slash(1.8, 1.0, 0.55), hit: { damage: 50, hitstun: 20, blockstun: 10, knockback: 1.5, block_pushback: 0.8, cue: 'hit_heavy_blade' } }] }),
  // L L H: rising launcher.
  { id: 'aldric_llh', kind: KIND.HEAVY, startup: 14, active: 4, recovery: 22, animation: '2H_Melee_Attack_Slice',
    hitboxes: [{ ...slash(1.6, 1.2, 0.55), hit: { damage: 60, hitstun: 24, blockstun: 12, reaction: REACTION.LAUNCH, launch_height: 2.1, knockback: 0.3, juggle_cost: 2, cue: 'hit_heavy_blade' } }] },
  // L H: low knockdown sweep.
  { id: 'aldric_lh', kind: KIND.HEAVY, startup: 16, active: 4, recovery: 24, animation: '1H_Melee_Attack_Slice_Horizontal',
    hitboxes: [{ ...slash(1.9, 0.45, 0.5), hit: { damage: 70, hitstun: 20, blockstun: 12, reaction: REACTION.KNOCKDOWN, knockback: 1.2, cue: 'hit_heavy_blade' } }] },
  { id: 'aldric_h1', kind: KIND.HEAVY, startup: 18, active: 4, recovery: 24, animation: '1H_Melee_Attack_Chop', next_heavy: 'aldric_h2',
    chargeable: true, charge_frame: 10, charge_max: 40, charge_damage_percent: 50, full_charge_guard_break: true,
    motions: [{ start_frame: 12, end_frame: 18, forward_speed: 2.5, stop_at_distance: 1.0 }],
    hitboxes: [{ ...slash(1.9, 1.0, 0.6), hit: { damage: 100, hitstun: 26, blockstun: 14, knockback: 1.0, block_pushback: 0.6, cue: 'hit_heavy_blade' } }] },
  { id: 'aldric_h2', kind: KIND.HEAVY, startup: 20, active: 4, recovery: 28, animation: '2H_Melee_Attack_Chop',
    motions: [{ start_frame: 8, end_frame: 20, forward_speed: 3.0, stop_at_distance: 1.0 }],
    hitboxes: [{ ...slash(2.0, 1.0, 0.6), hit: { damage: 110, hitstun: 28, blockstun: 14, knockback: 2.2, wall_splat: true, block_pushback: 0.9, cue: 'hit_heavy_blade' } }] },
  { id: 'aldric_run_l', kind: KIND.LIGHT, startup: 8, active: 4, recovery: 18, animation: '1H_Melee_Attack_Stab',
    motions: [{ start_frame: 1, end_frame: 11, forward_speed: 13.5, stop_at_distance: 0.9 }],
    hitboxes: [{ ...slash(1.8, 1.05, 0.5), hit: { damage: 50, hitstun: 20, blockstun: 10, reaction: REACTION.KNOCKDOWN, knockback: 1.6, cue: 'hit_blade' } }] },
  { id: 'aldric_air_l1', kind: KIND.AIR_LIGHT, aerial: true, startup: 5, active: 3, recovery: 12, animation: '1H_Melee_Attack_Slice_Horizontal', next_light: 'aldric_air_l2',
    hitboxes: [{ ...slash(1.5, 0.9, 0.55), hit: { damage: 30, hitstun: 18, blockstun: 10, knockback: 0.2, cue: 'hit_blade' } }] },
  { id: 'aldric_air_l2', kind: KIND.AIR_LIGHT, aerial: true, startup: 5, active: 3, recovery: 12, animation: '1H_Melee_Attack_Slice_Diagonal',
    hitboxes: [{ ...slash(1.5, 0.9, 0.55), hit: { damage: 30, hitstun: 20, blockstun: 10, knockback: 0.4, cue: 'hit_blade' } }] },
  { id: 'aldric_air_h', kind: KIND.AIR_HEAVY, aerial: true, startup: 12, active: 4, recovery: 10, landing_recovery: 16, gravity_percent: 160, animation: '1H_Melee_Attack_Jump_Chop',
    hitboxes: [{ offset: v3(0, 0.9, 0.5), offset_end: v3(0, 0.1, 1.4), capsule: true, radius: 0.55, hit: { damage: 80, hitstun: 22, blockstun: 12, reaction: REACTION.GROUND_BOUNCE, launch_height: 1.4, knockback: 0.5, juggle_cost: 2, cue: 'hit_heavy_blade' } }] },
  { id: 'aldric_grab', kind: KIND.GRAB, startup: 6, active: 3, recovery: 30, animation: 'Unarmed_Melee_Attack_Punch_A', throw_move: 'aldric_throw', hold_distance: 0.9,
    hitboxes: [{ offset: v3(0, 1.0, 0.5), offset_end: v3(0, 1.0, 1.15), capsule: true, radius: 0.45, hit: { damage: 0, throw: true, cue: 'grab' } }] },
  // Shield-bash throw: pommel the held victim, then shove them away.
  { id: 'aldric_throw', kind: KIND.THROW, startup: 18, active: 2, recovery: 20, animation: 'Block_Attack',
    hitboxes: [{ offset: v3(0, 1.0, 0.6), radius: 0.8, hit: { damage: 90, hitstun: 30, reaction: REACTION.KNOCKDOWN, knockback: 2.6, wall_splat: true, cue: 'hit_heavy' } }] },
  { id: 'aldric_getup', kind: KIND.GETUP_ATTACK, startup: 14, active: 3, recovery: 22, invuln_start: 1, invuln_end: 10, animation: '1H_Melee_Attack_Slice_Horizontal',
    hitboxes: [{ ...slash(1.7, 0.8, 0.55), hit: { damage: 40, hitstun: 18, blockstun: 8, knockback: 1.0, cue: 'hit_blade' } }] },
  // --- Abilities -------------------------------------------------------------------------
  // 1: dashing thrust, 6 m, armour on 4-12, wall-splats.
  { id: 'oathfire_lunge', kind: KIND.ABILITY, startup: 12, active: 7, recovery: 24, cooldown: 300, animation: '1H_Melee_Attack_Stab', cue: 'oathfire_lunge',
    armor_start: 4, armor_end: 12, armor_hits: 1, armor_damage_percent: 100, tracking: 4,
    motions: [{ start_frame: 4, end_frame: 18, forward_speed: 24.0, stop_at_distance: 0.9, homing: true }],
    hitboxes: [{ offset: v3(0, 1.05, 0.4), offset_end: v3(0, 1.05, 1.7), capsule: true, radius: 0.55,
      hit: { damage: 90, hitstun: 26, blockstun: 18, knockback: 3.0, block_pushback: 1.0, wall_splat: true, carry_frames: 6, cue: 'hit_fire' } }] },
  // 2: rising flame slash; launches; jump-cancel on hit.
  { id: 'brand_rise', kind: KIND.ABILITY, startup: 8, active: 4, recovery: 22, cooldown: 240, animation: '2H_Melee_Attack_Slice', cue: 'brand_rise',
    cancels: [{ start_frame: 9, end_frame: 30, condition: COND.ON_HIT, into: INTO.JUMP | INTO.SUPER }],
    hitboxes: [{ offset: v3(0, 0.6, 0.6), offset_end: v3(0, 2.0, 1.2), capsule: true, radius: 0.6,
      hit: { damage: 70, hitstun: 26, blockstun: 14, reaction: REACTION.LAUNCH, launch_height: 2.6, knockback: 0.2, juggle_cost: 1, cue: 'hit_fire' } }] },
  // 3: shield bash 3 m; 30 f stagger; destroys projectiles hitting the shield.
  { id: 'bulwark_charge', kind: KIND.ABILITY, startup: 14, active: 6, recovery: 22, cooldown: 360, animation: 'Block_Attack', cue: 'bulwark_charge',
    projectile_invuln_start: 1, projectile_invuln_end: 19,
    motions: [{ start_frame: 6, end_frame: 19, forward_speed: 12.8, stop_at_distance: 0.8 }],
    hitboxes: [{ offset: v3(0, 1.0, 0.75), radius: 0.7, destroys_projectiles: true,
      hit: { damage: 50, hitstun: 30, blockstun: 16, guard_damage: 40, knockback: 1.2, block_pushback: 1.0, cue: 'hit_shield' } }] },
  // --- Super --------------------------------------------------------------------------------
  // Plants the sword: a flame pillar (3 m, launches) then a fire wave 10 m forward.
  { id: 'pyre_of_the_forsworn', kind: KIND.SUPER, startup: 18, active: 2, recovery: 44, soul_cost: 100, flash_frames: 20,
    invuln_start: 1, invuln_end: 18, animation: '1H_Melee_Attack_Jump_Chop', cue: 'pyre_plant',
    effects: [
      { id: 'pyre_pillar', spawn_frame: 18, anchor: ANCHOR.OWNER, offset: v3(0, 0, 0.6), radius: 3.0, height: 4.0, lifetime: 16,
        destroy_on_contact: false, destroyable: false, blocked_by_walls: false, projectile: false, cue: 'pyre_pillar',
        hit: { damage: 120, hitstun: 30, blockstun: 16, reaction: REACTION.LAUNCH, launch_height: 3.0, knockback: 0.4, juggle_cost: 0, cue: 'hit_fire' } },
      { id: 'pyre_wave', spawn_frame: 34, anchor: ANCHOR.OWNER, offset: v3(0, 0, 1.2), speed: 20.0, travel: 10.0, radius: 1.3, height: 2.6, lifetime: 40,
        destroy_on_contact: false, destroyable: false, blocked_by_walls: true, projectile: false, cue: 'pyre_wave',
        hit: { damage: 180, hitstun: 34, blockstun: 18, reaction: REACTION.LAUNCH, launch_height: 2.2, knockback: 2.5, juggle_cost: 0, wall_splat: true, cue: 'hit_fire' } },
    ] },
];

export const fighter = {
  id: 'aldric', display_name: 'Aldric Vane', max_hp: 1000, radius: 0.45, height: 1.85, weight: 1.0,
  run_speed: 6.5, parry_window: 8,
  parry_buff: { id: 'oathkeeper_ignite', duration: 180, damage_bonus_percent: 30, uses: 1, cue: 'oathfire_ignite' },
  light: 'aldric_l1', heavy: 'aldric_h1', run_light: 'aldric_run_l', air_light: 'aldric_air_l1', air_heavy: 'aldric_air_h',
  grab: 'aldric_grab', getup_attack: 'aldric_getup', abilities: sn('oathfire_lunge', 'brand_rise', 'bulwark_charge'), super_move: 'pyre_of_the_forsworn',
  scene: 'res://presentation/fighters/aldric/aldric.tscn',
};

if (repo) writeFighter(repo, 'content/fighters/aldric', 'aldric.tres', fighter, moves);
