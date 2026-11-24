# content/fighters/

One folder per fighter: `<id>.tres` (FighterData) and `moves/` (one MoveData per move).
Hollowed grunts reuse a reduced set of Aldric's moves; the Oath-Shade (story act 5) runs
Aldric's whole kit and trait with a shadow look (`presentation/fighters/oath_shade/`).

The `.tres` files are generated from the specs in `tools/fighters/<id>.mjs` (readable move
lists with frame data, hitboxes, effects and cues):

```sh
node tools/fighters/aldric.mjs .
node tools/fighters/hollowed.mjs .
node tools/fighters/morrigan.mjs .
node tools/fighters/gorrath.mjs .
node tools/fighters/oath_shade.mjs .
```

Edit the spec and regenerate, so the spec and the data stay in step. Frame data follows
design §3 and is tuning, not law. Each fighter's kit is covered by
`tests/content/fighters/test_<id>.gd` (strings, armour, launches and cancels, trait,
super).

| Fighter | Light string | Heavies | Abilities (1 / 2 / 3) | Super |
|---|---|---|---|---|
| Aldric | L L L, L L H launcher, L H sweep | H (chargeable, guard break at full), H H wall splat | Oathfire Lunge (6 m, armour f4-12, wall splat), Brand Rise (launch, jump cancel on hit), Bulwark Charge (stagger, 40 guard dmg, eats projectiles) | Pyre of the Forsworn (flame pillar, then a 10 m fire wave) |
| Hollowed | L L L, L H | H | none | none |
| Morrigan | L L (long staff), run L knockdown | H (chargeable, wall splat) | Soul Lance (bolt, fires stored souls as shards), Grave Grasp (rune under the target's position on cast, erupts 30 f later and launches), Wraithstep (5 m invincible blink along the stick, air OK) | Requiem of the Drowned (8 m ring of hands, launches) |
| Gorrath | L L L, L L H launcher, L H sweep | H H (chargeable, wall splat), all armoured | Chain Hook (9 m chain, pulls point-blank at +14), Earthsplitter (shockwave, ground bounce), Bull Rush (2-hit armour charge that carries into walls) | Execution Chain (command grab: unblockable, beats attacks, untechable, three slams) |

Aldric's trait Oathkeeper is data: `parry_window = 8` and `parry_buff` (+30% on the next
hit within 3 s). Gorrath's Unbroken is data too: every heavy has one hit of 50% armour
from frame 6 through its active frames. Morrigan's Lantern of Souls is a trait script
(`morrigan/lantern_of_souls.gd`): unblocked ability hits store a soul in `vars[0]` (max 3),
and her next Soul Lance fires them as shards (the move's effect 1, which the sim never
spawns on its own) and empties the lantern.
