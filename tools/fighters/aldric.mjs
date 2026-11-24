import { writeFighter, KIND, REACTION, ANCHOR, v3, sn } from './gen.mjs';

const repo = process.argv[2];
// Aldric Vane, skill kit (design-lost-ark §4). Frame data lives here so tuning from the
// reference study is a data change: edit, run `node tools/fighters/aldric.mjs .`.

export const WEIGHT = { AUTO: 0, BASIC: 1, LIGHT: 2, MEDIUM: 3, HEAVY: 4, MASSIVE: 5, TICK: 6 };
export const SKILL = { TAP: 0, HOLD: 1, CHARGE: 2, COMBO: 3, CHAIN: 4, DASH_STRIKE: 5, STANCE: 6 };
export const AIM = { AUTO: 0, DIRECTION: 1, GROUND_TARGET: 2, SELF: 3, DASH_TO: 4 };
export const TRAVEL = { NONE: 0, ARRIVE: 1, STOP_AT: 2 };
const S = (sec) => Math.round(sec * 60);

const CHEST = 1.1;
const slash = (reach = 1.7, y = CHEST, r = 0.55) => ({ offset: v3(0, y, 0.45), offset_end: v3(0, y, reach), capsule: true, radius: r });
const basicHit = (damage, extra = {}) => ({ damage, weight: WEIGHT.BASIC, hitstun: 14, knockback: 0.3, cue: 'hit_blade', ...extra });

export const moves = [
  // --- Basic: Oath Strikes (slash, backhand, shield thrust; loops while held) ---------------
  { id: 'aldric_b1', kind: KIND.LIGHT, aim: AIM.DIRECTION, startup: 4, active: 2, recovery: 12, animation: '1H_Melee_Attack_Slice_Diagonal', next_light: 'aldric_b2',
    motions: [{ start_frame: 1, end_frame: 5, forward_speed: 3.6, stop_at_distance: 0.9 }],
    hitboxes: [{ ...slash(1.75), hit: basicHit(25) }] },
  { id: 'aldric_b2', kind: KIND.LIGHT, aim: AIM.DIRECTION, startup: 4, active: 2, recovery: 12, animation: '1H_Melee_Attack_Slice_Horizontal', next_light: 'aldric_b3',
    motions: [{ start_frame: 1, end_frame: 5, forward_speed: 3.6, stop_at_distance: 0.9 }],
    hitboxes: [{ ...slash(1.75), hit: basicHit(25) }] },
  { id: 'aldric_b3', kind: KIND.LIGHT, aim: AIM.DIRECTION, startup: 6, active: 2, recovery: 14, animation: 'Block_Attack', next_light: 'aldric_b1',
    motions: [{ start_frame: 1, end_frame: 6, forward_speed: 3.0, stop_at_distance: 0.9 }],
    hitboxes: [{ offset: v3(0, 1.0, 0.5), offset_end: v3(0, 1.0, 1.5), capsule: true, radius: 0.6, hit: basicHit(40, { hitstun: 16, knockback: 1.0, cue: 'hit_shield' }) }] },
  { id: 'aldric_getup', kind: KIND.GETUP_ATTACK, aim: AIM.DIRECTION, startup: 10, active: 3, recovery: 18, invuln_start: 1, invuln_end: 10, animation: '1H_Melee_Attack_Slice_Horizontal',
    hitboxes: [{ ...slash(1.8, 0.8, 0.6), hit: { damage: 40, weight: WEIGHT.LIGHT, hitstun: 18, knockback: 1.0, cue: 'hit_blade' } }] },

  // --- Q: Oathfire Lunge (dash-strike to the aim, ⚡Counter) --------------------------------
  { id: 'oathfire_lunge', kind: KIND.ABILITY, skill_type: SKILL.DASH_STRIKE, aim: AIM.DASH_TO, max_range: 6.0,
    startup: 5, active: 8, recovery: 16, skill_cancel_from: 13, cooldown: S(5), flinch_immune_start: 1, flinch_immune_end: 12,
    animation: '1H_Melee_Attack_Stab', cue: 'oathfire_lunge',
    motions: [{ start_frame: 2, end_frame: 13, forward_speed: 30.0, stop_at_distance: 0.9, aim_travel: TRAVEL.STOP_AT }],
    hitboxes: [{ offset: v3(0, 1.05, 0.3), offset_end: v3(0, 1.05, 1.6), capsule: true, radius: 0.6,
      hit: { damage: 90, weight: WEIGHT.MEDIUM, counter: true, hitstun: 24, knockback: 1.5, wall_splat: true, carry_frames: 6, cue: 'hit_fire' } }] },

  // --- E: Brand Rise (combo: rising crescent, then a leaping slam) -------------------------
  { id: 'brand_rise', kind: KIND.ABILITY, skill_type: SKILL.COMBO, aim: AIM.DIRECTION, startup: 4, active: 4, recovery: 16, skill_cancel_from: 8,
    follow_up: 'brand_rise_slam', follow_up_window: 30, cooldown: S(6), animation: '1H_Melee_Attack_Slice_Diagonal', cue: 'brand_rise',
    hitboxes: [{ offset: v3(0, 0.6, 0.6), offset_end: v3(0, 2.0, 1.3), capsule: true, radius: 0.65,
      hit: { damage: 70, weight: WEIGHT.LIGHT, hitstun: 24, reaction: REACTION.LAUNCH, launch_height: 2.4, knockback: 0.2, juggle_cost: 1, cue: 'hit_fire' } }] },
  { id: 'brand_rise_slam', kind: KIND.ABILITY, skill_type: SKILL.COMBO, aim: AIM.DIRECTION, startup: 7, active: 4, recovery: 16, skill_cancel_from: 11,
    push_immune_start: 1, push_immune_end: 10, animation: '1H_Melee_Attack_Jump_Chop', cue: 'brand_slam',
    motions: [{ start_frame: 1, end_frame: 7, forward_speed: 25.0, stop_at_distance: 0.8 }],
    hitboxes: [{ offset: v3(0, 0.8, 0.8), radius: 2.5,
      hit: { damage: 90, weight: WEIGHT.HEAVY, hitstun: 26, reaction: REACTION.GROUND_BOUNCE, launch_height: 1.6, knockback: 0.4, juggle_cost: 1, otg: true, cue: 'hit_heavy_blade' } }] },

  // --- R: Flame Rend (fire wave that brands, ⚡Counter) → Rend Ignition (chain) -------------
  { id: 'flame_rend', kind: KIND.ABILITY, skill_type: SKILL.CHAIN, aim: AIM.DIRECTION, startup: 6, active: 1, recovery: 14, skill_cancel_from: 8,
    chain_move: 'rend_ignition', chain_frames: S(3), cooldown: S(8), animation: '1H_Melee_Attack_Slice_Horizontal', cue: 'flame_rend',
    effects: [{ id: 'flame_rend_wave', spawn_frame: 6, anchor: ANCHOR.OWNER, offset: v3(0, 0, 0.8), speed: 30.0, travel: 9.0, radius: 0.8, height: 1.2, lifetime: 24,
      destroy_on_contact: false, destroyable: false, blocked_by_walls: true, projectile: false, hits_per_target: 1, cue: 'flame_rend_wave',
      hit: { damage: 70, weight: WEIGHT.MEDIUM, counter: true, otg: true, mark: true, mark_frames: S(3), hitstun: 22, knockback: 0.8, cue: 'hit_fire' } }] },
  { id: 'rend_ignition', kind: KIND.ABILITY, skill_type: SKILL.CHAIN, aim: AIM.SELF, startup: 3, active: 4, recovery: 12, animation: 'Spellcast_Shoot', cue: 'rend_ignition',
    mark_hit: { damage: 60, weight: WEIGHT.MEDIUM, hitstun: 26, reaction: REACTION.LAUNCH, launch_height: 1.9, knockback: 0.2, juggle_cost: 1, otg: true, cue: 'hit_fire' } },

  // --- F: Bulwark (stance) → Retribution ----------------------------------------------------
  // Stance f3-34 absorbs the first frontal hit; untriggered, a shove at f35, then a recovery
  // that cannot be skill-cancelled.
  { id: 'bulwark', kind: KIND.ABILITY, skill_type: SKILL.STANCE, aim: AIM.SELF, startup: 3, active: 4, recovery: 16 + 35 - 3, skill_cancel_from: 0,
    stance_start: 3, stance_end: 34, stance_arc: 180.0, counter_move: 'retribution', cooldown: S(8), animation: 'Blocking', cue: 'bulwark_raise',
    hitboxes: [{ start_frame: 35, end_frame: 38, offset: v3(0, 1.0, 0.6), offset_end: v3(0, 1.0, 1.4), capsule: true, radius: 0.6,
      hit: { damage: 40, weight: WEIGHT.LIGHT, hitstun: 18, knockback: 1.2, cue: 'hit_shield' } }] },
  { id: 'retribution', kind: KIND.ABILITY, aim: AIM.DIRECTION, startup: 4, active: 4, recovery: 16, no_dash_cancel: true,
    invuln_start: 1, invuln_end: 10, push_immune_start: 11, push_immune_end: 24, animation: 'Block_Attack', cue: 'retribution',
    hitboxes: [{ offset: v3(0, 1.0, 0.5), offset_end: v3(0, 1.1, 1.8), capsule: true, radius: 0.75,
      hit: { damage: 110, weight: WEIGHT.HEAVY, hitstun: 30, reaction: REACTION.KNOCKDOWN, knockback: 2.4, wall_splat: true, cue: 'hit_fire' } }] },

  // --- Z: Cinder Wheel (hold, steerable spin) -------------------------------------------------
  { id: 'cinder_wheel', kind: KIND.ABILITY, skill_type: SKILL.HOLD, aim: AIM.SELF, startup: 5, active: 72, recovery: 14,
    hold_start: 5, hold_end: 76, hold_steer_percent: 50, skill_cancel_from: 15, flinch_immune_start: 1, flinch_immune_end: 76,
    counter_window_start: 1, counter_window_end: 16, cooldown: S(10), animation: '2H_Melee_Attack_Spinning', cue: 'cinder_wheel',
    hitboxes: [{ offset: v3(0, 1.0, 0), radius: 2.8, rehit_frames: 8,
      hit: { damage: 15, weight: WEIGHT.TICK, stagger: 15, hitstun: 14, knockback: -0.3, cue: 'hit_fire' } }] },

  // --- X: Verdict (charge, leap to the aim point) -------------------------------------------
  { id: 'verdict', kind: KIND.ABILITY, skill_type: SKILL.CHARGE, aim: AIM.GROUND_TARGET, max_range: 7.0,
    startup: 14, active: 4, recovery: 18, cooldown: S(12), push_immune_start: 1, push_immune_end: 14,
    counter_window_start: 1, counter_window_end: 2,
    chargeable: true, charge_frame: 2, charge_max: 50, charge_levels: [15, 35], charge_level_damage_percent: [100, 125],
    perfect_start: 35, perfect_end: 45, perfect_damage_percent: 158, perfect_weight: WEIGHT.MASSIVE, perfect_stagger: 80,
    early_release_move: 'verdict_smash', animation: '1H_Melee_Attack_Jump_Chop', cue: 'verdict_leap',
    motions: [{ start_frame: 3, end_frame: 14, aim_travel: TRAVEL.ARRIVE }],
    hitboxes: [{ offset: v3(0, 0.5, 0), radius: 3.5,
      hit: { damage: 120, weight: WEIGHT.HEAVY, hitstun: 30, reaction: REACTION.KNOCKDOWN, knockback: 1.6, otg: true, cue: 'verdict_impact' } }],
    effects: [{ id: 'verdict_eruption', spawn_frame: 15, anchor: ANCHOR.TARGET, max_range: 7.0, offset: v3(0, 0, 0), count: 3, spread_degrees: 240,
      speed: 12.0, travel: 1.8, radius: 0.9, height: 3.0, lifetime: 12, requires_perfect: true,
      destroy_on_contact: false, destroyable: false, blocked_by_walls: false, projectile: false, hits_per_target: 1, cue: 'verdict_eruption',
      hit: { damage: 20, weight: WEIGHT.LIGHT, hitstun: 20, knockback: 0.3, otg: true, cue: 'hit_fire' } }] },
  { id: 'verdict_smash', kind: KIND.ABILITY, aim: AIM.SELF, startup: 5, active: 3, recovery: 12, animation: '1H_Melee_Attack_Chop', cue: 'swing_heavy',
    hitboxes: [{ offset: v3(0, 0.6, 0.6), radius: 2.0, hit: { damage: 70, weight: WEIGHT.MEDIUM, hitstun: 24, knockback: 1.2, cue: 'hit_heavy_blade' } }] },

  // --- V: Awakening, Pyre of the Forsworn -----------------------------------------------------
  { id: 'pyre_of_the_forsworn', kind: KIND.SUPER, aim: AIM.GROUND_TARGET, max_range: 10.0, soul_cost: 100, flash_frames: 40, no_dash_cancel: true,
    startup: 41, active: 64, recovery: 30, invuln_start: 1, invuln_end: 41, push_immune_start: 42, push_immune_end: 135,
    animation: 'Spellcast_Raise', cue: 'pyre_plant',
    effects: [
      { id: 'pyre_pillar', spawn_frame: 41, anchor: ANCHOR.OWNER, offset: v3(0, 0, 0), radius: 4.0, height: 4.5, lifetime: 14,
        destroy_on_contact: false, destroyable: false, blocked_by_walls: false, projectile: false, cue: 'pyre_pillar',
        hit: { damage: 80, weight: WEIGHT.HEAVY, hitstun: 30, reaction: REACTION.LAUNCH, launch_height: 2.6, knockback: 0.4, juggle_cost: 0, cue: 'hit_fire' } },
      { id: 'pyre_wave', spawn_frame: 60, anchor: ANCHOR.OWNER, offset: v3(0, 0, 1.0), count: 3, spread_degrees: 50, speed: 30.0, travel: 12.0, radius: 1.2, height: 2.4, lifetime: 30,
        destroy_on_contact: false, destroyable: false, blocked_by_walls: true, projectile: false, hits_per_target: 1, cue: 'pyre_wave',
        hit: { damage: 60, weight: WEIGHT.MEDIUM, hitstun: 30, reaction: REACTION.STAGGER, knockback: 0.6, juggle_cost: 0, otg: true, cue: 'hit_fire' } },
      { id: 'pyre_sword', spawn_frame: 100, anchor: ANCHOR.TARGET, max_range: 10.0, offset: v3(0, 0, 0), radius: 4.0, height: 6.0, lifetime: 8,
        destroy_on_contact: false, destroyable: false, blocked_by_walls: false, projectile: false, cue: 'pyre_sword',
        hit: { damage: 210, weight: WEIGHT.MASSIVE, stagger: 80, hitstun: 40, reaction: REACTION.KNOCKDOWN, knockback: 1.5, juggle_cost: 0, otg: true, cue: 'hit_fire' } },
    ] },
];

export const fighter = {
  id: 'aldric', display_name: 'Aldric Vane', max_hp: 1500, radius: 0.45, height: 1.85, weight: 1.0,
  run_speed: 6.5, jumps: 0,
  dash: { charges: 2, recharge_frames: 300, frames: 18, travel_frames: 12, distance: 4.5, invuln_start: 1, invuln_end: 10, skill_cancel_frame: 8 },
  // Oathkeeper: a Bulwark Retribution or any ⚡Counter ignites the blade for the next 2 skills.
  parry_buff: { id: 'oathkeeper_ignite', duration: S(6), damage_bonus_percent: 25, uses: 2, cue: 'oathfire_ignite' },
  light: 'aldric_b1', getup_attack: 'aldric_getup',
  abilities: sn('oathfire_lunge', 'brand_rise', 'flame_rend', 'bulwark', 'cinder_wheel', 'verdict'),
  super_move: 'pyre_of_the_forsworn',
  scene: 'res://presentation/fighters/aldric/aldric.tscn',
};

if (repo) writeFighter(repo, 'content/fighters/aldric', 'aldric.tres', fighter, moves);
