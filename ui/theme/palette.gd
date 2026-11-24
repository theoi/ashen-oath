class_name Palette
extends RefCounted
## Ember-and-ash UI colors, shared by the theme (tools/gen_theme.gd) and HUD code.

const BONE := Color(0.91, 0.86, 0.78)
const ASH_TEXT := Color(0.58, 0.54, 0.56)
const SHADOW := Color(0.0, 0.0, 0.0, 0.85)

const EMBER := Color(0.93, 0.5, 0.2)
const EMBER_BRIGHT := Color(1.0, 0.72, 0.42)
const EMBER_DIM := Color(0.62, 0.3, 0.12)
const EMBER_DEEP := Color(0.24, 0.09, 0.04, 0.95)

const SLAB := Color(0.085, 0.072, 0.078, 0.9)
const SLAB_LIT := Color(0.15, 0.095, 0.07, 0.95)
const PANEL := Color(0.05, 0.042, 0.048, 0.9)
const ASH_EDGE := Color(0.27, 0.23, 0.24)

const HEALTH := Color(0.72, 0.13, 0.11)
const HEALTH_LOSS := Color(0.95, 0.78, 0.5)
const SOUL := Color(0.52, 0.9, 0.78)
const SOUL_FULL := Color(0.8, 1.0, 0.92)
const GUARD := Color(0.66, 0.71, 0.8)
const GUARD_LOW := Color(0.9, 0.36, 0.22)
const LOCKED := Color(0.35, 0.32, 0.34)

## Team colors for HUD name plates (team 0 = the player's side).
const TEAMS: Array[Color] = [Color(0.93, 0.5, 0.2), Color(0.55, 0.7, 0.95), Color(0.6, 0.85, 0.5), Color(0.85, 0.5, 0.85)]
