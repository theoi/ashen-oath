import { writeFighter, KIND, REACTION, COND, INTO, ANCHOR, TP, v3, sn } from './gen.mjs';

const repo = process.argv[2];
// Long staff reach in front at chest height.
const staff = (reach = 2.1, y = 1.1, r = 0.45) => ({ offset: v3(0, y, 0.5), offset_end: v3(0, y, reach), capsule: true, radius: r });
const lance = (id, damage, extra = {}) => ({
  id, spawn_frame: 16, anchor: ANCHOR.OWNER, offset: v3(0, 1.2, 0.8), speed: 18.0, travel: 20.0, radius: 0.35, lifetime: 80,
  destroy_on_contact: true, destroyable: true, blocked_by_walls: true, projectile: true, cue: 'soul_lance',
  hit: { damage, hitstun: 20, blockstun: 12, knockback: 0.6, cue: 'hit_soul' }, ...extra,
});

export const moves = [
  { id: 'morrigan_l1', kind: KIND.LIGHT, startup: 7, active: 3, recovery: 13, animation: '2H_Melee_Attack_Slice', next_light: 'morrigan_l2', next_heavy: 'morrigan_h1',
    hitboxes: [{ ...staff(2.1), hit: { damage: 35, hitstun: 16, blockstun: 12, knockback: 0.4, cue: 'hit_staff' } }] },
  { id: 'morrigan_l2', kind: KIND.LIGHT, startup: 8, active: 3, recovery: 18, animation: '2H_Melee_Attack_Stab',
    hitboxes: [{ ...staff(2.3), hit: { damage: 45, hitstun: 20, blockstun: 10, knockback: 1.8, block_pushback: 1.2, cue: 'hit_staff' } }] },
  { id: 'morrigan_h1', kind: KIND.HEAVY, startup: 18, active: 4, recovery: 26, animation: '2H_Melee_Attack_Stab',
    chargeable: true, charge_frame: 10, charge_max: 40, charge_damage_percent: 50, full_charge_guard_break: true,
    hitboxes: [{ ...staff(2.7, 1.1, 0.5), hit: { damage: 90, hitstun: 26, blockstun: 14, knockback: 2.2, block_pushback: 1.0, wall_splat: true, cue: 'hit_staff' } }] },
  { id: 'morrigan_run_l', kind: KIND.LIGHT, startup: 9, active: 4, recovery: 18, animation: '2H_Melee_Attack_Stab',
    motions: [{ start_frame: 1, end_frame: 10, forward_speed: 11.0, stop_at_distance: 1.4 }],
    hitboxes: [{ ...staff(2.2), hit: { damage: 45, hitstun: 20, blockstun: 10, reaction: REACTION.KNOCKDOWN, knockback: 1.6, cue: 'hit_staff' } }] },
  { id: 'morrigan_air_l1', kind: KIND.AIR_LIGHT, aerial: true, startup: 6, active: 3, recovery: 12, animation: '2H_Melee_Attack_Slice', next_light: 'morrigan_air_l2',
    hitboxes: [{ ...staff(1.9, 0.9, 0.5), hit: { damage: 30, hitstun: 18, blockstun: 10, knockback: 0.3, cue: 'hit_staff' } }] },
  { id: 'morrigan_air_l2', kind: KIND.AIR_LIGHT, aerial: true, startup: 6, active: 3, recovery: 12, animation: '2H_Melee_Attack_Stab',
    hitboxes: [{ ...staff(2.0, 0.9, 0.5), hit: { damage: 30, hitstun: 20, blockstun: 10, knockback: 0.5, cue: 'hit_staff' } }] },
  { id: 'morrigan_air_h', kind: KIND.AIR_HEAVY, aerial: true, startup: 13, active: 4, recovery: 10, landing_recovery: 16, gravity_percent: 150, animation: '2H_Melee_Attack_Chop',
    hitboxes: [{ offset: v3(0, 0.9, 0.6), offset_end: v3(0, 0.1, 1.7), capsule: true, radius: 0.5, hit: { damage: 75, hitstun: 22, blockstun: 12, reaction: REACTION.GROUND_BOUNCE, launch_height: 1.3, knockback: 0.5, juggle_cost: 2, cue: 'hit_staff' } }] },
  { id: 'morrigan_grab', kind: KIND.GRAB, startup: 6, active: 3, recovery: 30, animation: 'Unarmed_Melee_Attack_Punch_A', throw_move: 'morrigan_throw',
    hitboxes: [{ offset: v3(0, 1.0, 0.5), offset_end: v3(0, 1.0, 1.15), capsule: true, radius: 0.45, hit: { damage: 0, throw: true, cue: 'grab' } }] },
  // Grips the victim's soul, then blasts it away.
  { id: 'morrigan_throw', kind: KIND.THROW, startup: 20, active: 2, recovery: 20, animation: 'Spellcast_Shoot',
    hitboxes: [{ offset: v3(0, 1.0, 0.6), radius: 0.8, hit: { damage: 85, hitstun: 30, reaction: REACTION.KNOCKDOWN, knockback: 3.2, wall_splat: true, cue: 'hit_soul' } }] },
  { id: 'morrigan_getup', kind: KIND.GETUP_ATTACK, startup: 14, active: 3, recovery: 22, invuln_start: 1, invuln_end: 10, animation: '2H_Melee_Attack_Slice',
    hitboxes: [{ ...staff(2.0, 0.8, 0.5), hit: { damage: 40, hitstun: 18, blockstun: 8, knockback: 1.0, cue: 'hit_staff' } }] },
  // --- Abilities -------------------------------------------------------------------------
  // 1: soul bolt. Effect 1 is the stored-soul shard the Lantern trait fires alongside it
  // (spawn_frame past the end of the move, so the sim never spawns it on its own).
  { id: 'soul_lance', kind: KIND.ABILITY, startup: 16, active: 1, recovery: 20, cooldown: 150, animation: 'Spellcast_Shoot', cue: 'soul_lance_cast',
    effects: [lance('soul_lance_bolt', 60), lance('soul_lance_shard', 30, { spawn_frame: 999, radius: 0.3, speed: 20.0, travel: 16.0, cue: 'soul_shard' })] },
  // 2: rune under the target's position when cast (it does not follow), erupts after 30 f.
  { id: 'grave_grasp', kind: KIND.ABILITY, startup: 14, active: 1, recovery: 22, cooldown: 420, animation: 'Spellcast_Raise', cue: 'grave_grasp_cast',
    effects: [{ id: 'grave_grasp_hands', spawn_frame: 14, anchor: ANCHOR.TARGET, max_range: 12.0, offset: v3(0, 0, 0), radius: 1.3, height: 2.2,
      delay: 30, lifetime: 10, destroy_on_contact: false, destroyable: false, blocked_by_walls: false, projectile: false, cue: 'grave_grasp',
      hit: { damage: 90, hitstun: 28, blockstun: 14, reaction: REACTION.LAUNCH, launch_height: 2.4, knockback: 0.1, cue: 'hit_soul' } }] },
  // 3: blink 5 m along the stick, invincible, usable in the air.
  { id: 'wraithstep', kind: KIND.ABILITY, startup: 4, active: 1, recovery: 10, cooldown: 300, air_ok: true, gravity_percent: 0,
    invuln_start: 1, invuln_end: 12, animation: 'Dodge_Forward', cue: 'wraithstep',
    teleport: { frame: 3, mode: TP.STICK, distance: 5.0 } },
  // --- Super --------------------------------------------------------------------------------
  { id: 'requiem_of_the_drowned', kind: KIND.SUPER, startup: 30, active: 2, recovery: 40, soul_cost: 100, flash_frames: 20,
    invuln_start: 1, invuln_end: 30, animation: 'Spellcast_Summon', cue: 'requiem_rise',
    effects: [{ id: 'requiem_hands', spawn_frame: 30, anchor: ANCHOR.OWNER, offset: v3(0, 0, 0), radius: 8.0, height: 3.0, lifetime: 10,
      destroy_on_contact: false, destroyable: false, blocked_by_walls: false, projectile: false, cue: 'requiem_hands',
      hit: { damage: 280, hitstun: 34, blockstun: 18, reaction: REACTION.LAUNCH, launch_height: 3.0, knockback: 1.0, juggle_cost: 0, cue: 'hit_soul' } }] },
];

export const fighter = {
  id: 'morrigan', display_name: 'Morrigan', max_hp: 900, radius: 0.42, height: 1.9, weight: 1.1,
  run_speed: 5.6, parry_window: 6,
  light: 'morrigan_l1', heavy: 'morrigan_h1', run_light: 'morrigan_run_l', air_light: 'morrigan_air_l1', air_heavy: 'morrigan_air_h',
  grab: 'morrigan_grab', getup_attack: 'morrigan_getup', abilities: sn('soul_lance', 'grave_grasp', 'wraithstep'), super_move: 'requiem_of_the_drowned',
  trait_script: 'res://content/fighters/morrigan/lantern_of_souls.gd',
  scene: 'res://presentation/fighters/morrigan/morrigan.tscn',
};

if (repo) writeFighter(repo, 'content/fighters/morrigan', 'morrigan.tres', fighter, moves);
