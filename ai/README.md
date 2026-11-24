# ai/

The CPU opponent (design §6). It is an `InputSource`: each tick it reads the sim the way a
player reads the screen and returns one `SimInput` frame, exactly like a pad. It never
writes the sim and never reads another fighter's buttons, buffer or stick.

| File | What |
|---|---|
| `ai_input_source.gd` | `AiInputSource`: the three layers (strategy, tactics, reaction) |
| `ai_move_book.gd` | `AiMoveBook`: per-fighter move analysis from `MoveData` (first hit frame, reach, on-block advantage, tags such as projectile, launch, gap closer, armor, throw) |
| `ai_difficulty.gd` | `AiDifficulty` Resource: Easy/Normal/Hard/Nightmare knobs; presets in `content/ai/difficulty/` |
| `ai_profile.gd` | `AiProfile` Resource: per-fighter range and intent weights; profiles in `content/ai/profiles/` |
| `ai_attack_tokens.gd` | `AiAttackTokens`: 1v2 fairness, shared by CPU teammates |
| `ai_rng.gd` | `AiRng`: the CPU's own deterministic RNG |
| `ai_bout.gd` | `AiBout`: runs one match headless and reports winner, rounds, stuck states, stats, replay |

## Using it

```gdscript
# Versus / story: MatchSetup.input_sources() already does this from MatchConfig
# (difficulty, ai_cap, ai_profiles).
var sources := AiInputSource.for_match(sim_config, PackedInt32Array([1, 2]), AiDifficulty.Level.HARD)
# Story fight 1 stays Easy whatever was chosen:
var capped := AiInputSource.for_match(sim_config, PackedInt32Array([1]), chosen_level, AiDifficulty.Level.EASY)
# The Oath-Shade plays Aldric's moves with an aggressive profile:
var shade := AiInputSource.for_match(sim_config, PackedInt32Array([1]), chosen_level, -1, {1: AiProfile.by_id(&"oath_shade")})
```

## How it decides

- **Strategy** (every `strategy_period` frames): utility scores choose an intent from
  *approach, pressure, zone, bait, defend, retreat* (plus *circle* when it has no attack
  token, and *punish* when it runs in on a long recovery). Inputs: distance against the
  profile's preferred range, the opponent's quick reach, health lead, the opponent's Soul,
  ranged abilities off cooldown, guard and recovery states, walls and the round clock.
- **Tactics** (every frame): picks moves from `AiMoveBook` by reach, first hit frame and
  on-block safety, so a new fighter needs no AI code. Strings follow `next_light` /
  `next_heavy`, cancels follow the sim's cancel rules, juggles predict the victim's height
  under juggle gravity. Punishes take the opponent's remaining recovery (visible move frame)
  and choose a move that hits in time, or run in when the gap closes in time.
- **Reaction**: each visible attack start, projectile, eruption and grab is noticed after the
  difficulty's reaction delay and answered with its chance: block, parry (timed to the
  fighter's parry window), dodge (timed to the dodge i-frames), jump or jab against grabs,
  run out of eruptions. Grab techs, air techs, tech rolls, get-up options and Soul Burst
  are rolled the same way. Lights (startup 6) are faster than any reaction delay, so they
  are only blocked by anticipation (`anticipate_guard_percent`).

Determinism: decisions use `AiRng` seeded from the match seed, the slot and the level, and
the sim state; no wall clock, no global RNG. The same config and difficulties replay the same
match, and the `Replay` of a CPU match verifies tick for tick.

## Tuning

Edit the `.tres` files (Godot inspector or text):
- `content/ai/difficulty/{easy,normal,hard,nightmare}.tres`: reaction delay, defend / parry
  / dodge chances, punish chance, combo level (0 single hits, 1 strings, 2 + ability
  cancels, 3 + juggles), super and burst use, attack gap, hesitation, aim noise, attack
  tokens (1, Nightmare 2).
- `content/ai/profiles/<fighter id>.tres`: preferred range, intent weights, jump-in / grab /
  charge habits, per-ability-slot bias. `FighterData.ai_profile` overrides the lookup.
  Profiles exist for the test fighter, Aldric, Morrigan (zones at 8-14 m), Gorrath
  (approach and bait, grabs), Hollowed grunts and the Oath-Shade (aggressive).

After tuning, run the ordering tests (`tools/run_tests.sh --filter=ai/`) and a soak.

## AI-vs-AI harness (soak test)

```sh
tools/ai_soak.sh --matches=40 --levels=nightmare,easy --arena=ashen_chapel
tools/ai_soak.sh --matches=50 --levels=normal,hard --arena=drowned_crypt --verify --fail-on-stuck
tools/ai_soak.sh --fighters=aldric,hollowed,hollowed --levels=normal,easy,easy --cap=easy
```

| Option | Meaning (default) |
|---|---|
| `--matches=N` | matches to run (20); match *i* uses seed `seed + i` |
| `--seed=S` | base seed (1) |
| `--fighters=a,b[,c,d]` | fighter ids (`content/fighters/<id>/<id>.tres`, `content/fighters/<id>.tres`, `content/test_fighter/<id>.tres`) or `res://` paths (test_fighter,test_fighter) |
| `--levels=l0,l1,...` | per slot: easy, normal, hard, nightmare, 0-3, or `none` (stands still) |
| `--teams=0,1,1` | team per slot (slot 0 team 0, others team 1) |
| `--arena=id` | `content/arenas/<id>.tres` or a path (training_arena) |
| `--rounds=N`, `--round-seconds=S` | rounds to win and round length (rules: 2 and 99) |
| `--profiles=1:oath_shade` | profile override per slot |
| `--start-soul=1:50` | starting Soul per slot |
| `--cap=easy` | cap every CPU's level (story fight 1) |
| `--no-swap` | keep sides (1v1 swaps spawn sides every other match) |
| `--stuck-seconds=20` | report a round with no HP change for this long |
| `--stuck-action-seconds=10` | report a fighter stuck in one non-neutral action this long |
| `--verify` | re-run each match from its replay and compare checksums every tick |
| `--json=path` | write a JSON report (summary + per-match details) |
| `--replays=dir` | save replays of matches with stuck states or mismatches (`--save-all` for every match) |
| `--quiet` | summary only |
| `--fail-on-stuck` | exit 1 on stuck states or unfinished matches (errors and replay mismatches always exit 1) |

The report gives win counts per team, draws, unfinished matches, round count and average
length, timeouts, per-slot hits / blocks / parries / dodges / abilities / supers / bursts /
grabs / techs, the CPU's own decision counters (threats seen, reactions by kind, punishes),
each stuck state with its seed and tick, engine errors, and the cost per tick. Saved
replays load with `load(path) as Replay`; `verify()` re-runs them.

## Tests

`tests/ai/`: determinism (same config → same frames; replay verifies every checksum),
difficulty ordering (each level beats the one below in 6+ of 8 seeded matches), a short soak
on the slice arenas and in 1v2, attack tokens (never two attackers with one token), and the
tactics/reaction layers (punishing a whiffed heavy, not getting hit by a slow heavy).
They take about 10 s. Long soaks belong in the harness, not CI.
