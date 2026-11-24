import { writeFighter } from './gen.mjs';
import { fighter as classic, moves } from './aldric_classic.mjs';

const repo = process.argv[2];
// The Oath-Shade: Aldric's classic kit and Oathkeeper trait, worn by his own curse. Its
// move files (content/fighters/oath_shade/moves) are shared with the Hollowed.
const shade = {
  ...classic,
  id: 'oath_shade', display_name: 'Oath-Shade',
  scene: 'res://presentation/fighters/oath_shade/oath_shade.tscn',
};
if (repo) writeFighter(repo, 'content/fighters/oath_shade', 'oath_shade.tres', shade, moves);
