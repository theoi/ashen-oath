import { writeResource } from './gen.mjs';
import { fighter as aldric, moves } from './aldric.mjs';
import path from 'node:path';

const repo = process.argv[2];
// The Oath-Shade: Aldric's whole kit and Oathkeeper trait, worn by his own curse.
const shade = {
  ...aldric,
  id: 'oath_shade', display_name: 'Oath-Shade',
  scene: 'res://presentation/fighters/oath_shade/oath_shade.tscn',
  moves: { $extArray: moves.map((m) => `res://content/fighters/aldric/moves/${m.id}.tres`), type: 'MoveData' },
};
if (repo) writeResource(path.join(repo, 'content/fighters/oath_shade/oath_shade.tres'), 'FighterData', shade);
