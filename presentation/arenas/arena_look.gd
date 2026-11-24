class_name ArenaLook
extends Resource
## Mood of one arena variant: sky, fog, lights, the prop palette recolor and ambient VFX
## amounts. Arena scenes read it once in _ready(); variants share a layout and differ only
## in their ArenaLook (plus the layout flags each arena script exposes).

@export_group("Background and fog")
@export var background_color := Color(0.02, 0.02, 0.03)
@export var ambient_color := Color(0.3, 0.33, 0.45)
@export var ambient_energy := 0.35
@export var fog_color := Color(0.06, 0.06, 0.08)
@export var fog_density := 0.02
## Extra fog that pools below fog_height (Godot height fog).
@export var fog_height := 1.0
@export var fog_height_density := 0.0
@export var exposure := 1.0
@export var saturation := 0.9
@export var glow_intensity := 0.8
@export var glow_bloom := 0.05

@export_group("Key and rim light")
@export var key_color := Color(0.55, 0.62, 0.85)
@export var key_energy := 0.6
## Euler degrees of the key (moon) light.
@export var key_rotation := Vector3(-50.0, -60.0, 0.0)
@export var key_shadows := true
@export var rim_color := Color(0.45, 0.6, 0.9)
@export var rim_energy := 0.5
@export var rim_rotation := Vector3(-20.0, 120.0, 0.0)

@export_group("Prop palette")
## Multiplies the recolored KayKit atlas.
@export var prop_tint := Color(0.82, 0.86, 0.95)
@export_range(0.0, 1.0) var prop_desaturate := 0.6
@export var prop_brightness := 0.85
@export var prop_contrast := 1.15
@export var grime_color := Color(0.05, 0.045, 0.05)
@export_range(0.0, 1.0) var grime_amount := 0.45
@export var prop_rim := 0.35

@export_group("Fire and candles")
@export var fire_color := Color(1.0, 0.45, 0.12)
@export var fire_light_energy := 1.6
@export var flame_energy := 2.2

@export_group("Light shafts")
@export var shaft_color := Color(0.55, 0.65, 0.9)
@export var shaft_intensity := 0.12

@export_group("Particles")
## Falling ash flakes over the whole arena.
@export var ash_amount := 160
@export var ash_color := Color(0.62, 0.62, 0.66, 0.8)
## Rising embers per ember source.
@export var ember_amount := 24
@export var ember_color := Color(1.0, 0.5, 0.15)
## Rising soul motes per source (crypt).
@export var mote_amount := 0
@export var soul_color := Color(0.35, 1.0, 0.6)
@export var soul_light_energy := 1.2

@export_group("Water")
@export var water_enabled := false
## Surface height above the fight floor (y = 0).
@export var water_level := 0.14
@export var water_color := Color(0.01, 0.02, 0.025)
@export var water_sheen := Color(0.25, 0.6, 0.5)
