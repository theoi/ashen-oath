# presentation/fighters/

How fighters look: KayKit models restyled "stylized grim", posed from sim state every
render frame. Nothing here writes sim state.

- `fighter_clips.gd` (`FighterClips`): the shared KayKit animation library. All KayKit
  Adventurers and Skeletons models use one 41-bone rig, so only `Skeleton_Warrior.glb`
  (95 clips) is imported with animations; the other models import without them
  (`animation/import=false` in their `.import`), which keeps the web build ~5 MB smaller.
  `IMPACT` holds each attack clip's measured impact time; `IN_PLACE` clips have their hip
  travel removed (the sim moves the fighter).
- `fighter_model.gd` (`FighterModel`): root of a fighter's scene (`FighterData.scene`).
  Loads the model, hides spare weapons, applies `shaders/fighter_grim.gdshader` (cold
  recolour, per-cell tints and glows, rim light, hit flash, shade look) and the molten-crack
  weapon shader, builds a two-slot AnimationTree (clip A, clip B, crossfade) driven by
  explicit seeks. Subclass per fighter for extras (`_build_extras`, `update_extras`) and
  move-specific poses (`adjust_pose`).
- `fighter_poser.gd` (`FighterPoser`): sim state -> `FighterPose` (clip, time, root
  pitch/roll/yaw/lift, shake, trail). Attacks fit the clip's wind-up into the move's startup
  so the impact lands on the first active frame. It fills the reactions KayKit has no clips
  for: launch/air tumble (body pitch follows vertical speed), knockdown fall (Death_A held),
  guard-break wobble, wall splat, grabbed, tech flips and get-up rolls.
- `fighter_view.gd` (`FighterView`): one per slot. Interpolates position and facing between
  ticks, crossfades poses, freezes and shakes in hitstop, flashes on hit/block/armour/parry,
  feeds the `WeaponTrail`.

Per fighter: `aldric/` (Knight, ember seams, joint embers, molten sword that ignites with
Oathkeeper), `hollowed/` (Skeleton Warrior with a skeleton blade and glowing eyes).

The fight itself (arena + views + camera + effects) is `presentation/fight/`.
