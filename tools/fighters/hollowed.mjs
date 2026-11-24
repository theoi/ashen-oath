import { writeResource, sn } from './gen.mjs';
import path from 'node:path';

const repo = process.argv[2];
const A = (id) => `res://content/fighters/oath_shade/moves/${id}.tres`;
// Hollowed grunts: skeletons running a reduced classic Aldric moveset (no abilities, no
// super), shared with the Oath-Shade.
const hollowed = {
  id: 'hollowed', display_name: 'Hollowed', max_hp: 750, radius: 0.42, height: 1.8, weight: 1.05,
  run_speed: 5.6, parry_window: 6,
  light: 'aldric_l1', heavy: 'aldric_h1', run_light: 'aldric_run_l', air_light: 'aldric_air_l1', air_heavy: '',
  grab: 'aldric_grab', getup_attack: 'aldric_getup', abilities: sn(), super_move: '',
  scene: 'res://presentation/fighters/hollowed/hollowed.tscn',
  moves: { $extArray: ['aldric_l1', 'aldric_l2', 'aldric_l3', 'aldric_lh', 'aldric_h1', 'aldric_run_l', 'aldric_air_l1', 'aldric_grab', 'aldric_throw', 'aldric_getup'].map(A), type: 'MoveData' },
};
writeResource(path.join(repo, 'content/fighters/hollowed/hollowed.tres'), 'FighterData', hollowed);
