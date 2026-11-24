# content/fighters/

One folder per fighter: `<id>.tres` (FighterData) and `moves/` (one MoveData per move).
Hollowed grunts reuse a reduced set of Aldric's moves.

The `.tres` files are generated from the specs in `tools/fighters/<id>.mjs` (readable move
lists with frame data, hitboxes, effects and cues):

```sh
node tools/fighters/aldric.mjs .
node tools/fighters/hollowed.mjs .
```

Edit the spec and regenerate, so the spec and the data stay in step. Frame data follows
design §3 and is tuning, not law. Each fighter's kit is covered by
`tests/content/fighters/test_<id>.gd` (strings, armour, launches and cancels, trait,
super).

| Fighter | Light string | Heavies | Abilities (1 / 2 / 3) | Super |
|---|---|---|---|---|
| Aldric | L L L, L L H launcher, L H sweep | H (chargeable, guard break at full), H H wall splat | Oathfire Lunge (6 m, armour f4-12, wall splat), Brand Rise (launch, jump cancel on hit), Bulwark Charge (stagger, 40 guard dmg, eats projectiles) | Pyre of the Forsworn (flame pillar, then a 10 m fire wave) |
| Hollowed | L L L, L H | H | none | none |

Aldric's trait Oathkeeper is data: `parry_window = 8` and `parry_buff` (+30% on the next
hit within 3 s).
