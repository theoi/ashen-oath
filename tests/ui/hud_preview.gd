extends Node
## Dev view of the in-fight HUD over the Ashen Chapel with a mid-fight 1v2 state (cooldowns
## running, damage taken, Soul at Burst and Super). For screenshots of HUD states the
## simulation cannot reach yet:
##   SCENE=res://tests/ui/hud_preview.tscn tools/capture_screenshot.sh /tmp/hud.png 60
## With -- --story: a story wave with a boss mid-channel, six wave enemies and skill charges.

const ARENA := "res://presentation/arenas/ashen_chapel/ashen_chapel.tscn"


func _ready() -> void:
	var arena: Node3D = load(ARENA).instantiate()
	add_child(arena)
	var camera := Camera3D.new()
	camera.fov = 60.0
	add_child(camera)
	camera.position = Vector3(-6.0, 3.0, 2.5)
	camera.look_at(Vector3(2.0, 1.0, 0.0))
	camera.make_current()
	var layer := CanvasLayer.new()
	add_child(layer)
	var hud := Hud.new()
	layer.add_child(hud)

	if "--story" in OS.get_cmdline_user_args():
		hud.apply(_story_state())
		hud.on_event({"type": MatchEvents.STAGGER_BREAK, "slot": 1})
		return
	var state := HudState.new()
	state.round_number = 2
	state.round_wins = [1, 0]
	state.seconds_left = 47.0
	var rows: Array[Array] = [
		["Aldric Vane", 0, 960.0, 1500.0, 100.0, 72.0],
		["Morrigan", 1, 310.0, 900.0, 100.0, 40.0],
		["Gorrath", 1, 900.0, 1150.0, 24.0, 18.0],
	]
	for slot in rows.size():
		var row := rows[slot]
		var fighter := HudState.Fighter.new()
		fighter.slot = slot
		fighter.name = row[0]
		fighter.team = row[1]
		fighter.health = row[2]
		fighter.max_health = row[3]
		fighter.soul = row[4]
		fighter.guard = row[5]
		fighter.guard_broken = slot == 2
		fighter.is_player = slot == 0
		if fighter.is_player:
			_pilot_skills(fighter)
		state.fighters.append(fighter)
	hud.apply(state)
	hud.on_event({"type": MatchEvents.PARRY, "slot": 0})
	hud.on_event({"type": MatchEvents.GUARD_BREAK, "slot": 2})
	hud.announce("Counter", "Aldric breaks Gorrath's guard", 30.0)


## Final wave: Gorrath channelling a special (gauge 70%, stagger 40%), six Hollowed (one
## down, one free slot), Aldric's Oathfire Lunge on its second charge.
func _story_state() -> HudState:
	var state := HudState.new()
	state.seconds_left = -1.0
	state.wave = 3
	state.wave_count = 3
	for slot in 8:
		var fighter := HudState.Fighter.new()
		fighter.slot = slot
		fighter.team = 0 if slot == 0 else 1
		fighter.wave_member = slot > 1
		fighter.max_health = 300.0
		fighter.health = [300.0, 300.0, 300.0, 120.0, 0.0, 210.0, 60.0, 300.0][slot]
		fighter.knocked_out = slot == 4
		fighter.active = slot != 6
		fighter.name = "Hollowed"
		state.fighters.append(fighter)
	var player := state.fighters[0]
	player.name = "Aldric Vane"
	player.is_player = true
	player.max_health = 1500.0
	player.health = 1110.0
	player.soul = 64.0
	player.guard = 80.0
	_pilot_skills(player)
	player.skills[0].max_charges = 2
	player.skills[0].charges = 1
	player.skills[0].cooldown_left = 2.4
	player.skills[2].follow_left = 0.0
	player.skills[5].charging = false
	var boss := state.fighters[1]
	boss.name = "Gorrath, the Bone Tyrant"
	boss.max_health = 4200.0
	boss.health = 2650.0
	boss.stagger_max = 600.0
	boss.stagger = 240.0
	boss.channel_max = 200.0
	boss.channel = 140.0
	state.fighters[7].channel_max = 100.0
	state.fighters[7].channel = 55.0
	return state


## Aldric's pilot kit (design-lost-ark §4) mid-fight: a chain follow-up waiting on R, Verdict
## charging inside its perfect zone, one dash charge recharging, full Soul.
func _pilot_skills(fighter: HudState.Fighter) -> void:
	var rows: Array[Array] = [
		["Oathfire Lunge", HudState.Skill.Type.DASH_STRIKE, true, 0.0, 5.0],
		["Brand Rise", HudState.Skill.Type.COMBO, false, 3.6, 6.0],
		["Flame Rend", HudState.Skill.Type.CHAIN, true, 8.0, 8.0],
		["Bulwark", HudState.Skill.Type.STANCE, false, 0.0, 8.0],
		["Cinder Wheel", HudState.Skill.Type.HOLD, false, 6.2, 10.0],
		["Verdict", HudState.Skill.Type.CHARGE, false, 0.0, 12.0],
	]
	for i in rows.size():
		var row := rows[i]
		var skill := HudState.Skill.new()
		skill.name = row[0]
		skill.type = row[1]
		skill.counter = row[2]
		skill.cooldown_left = row[3]
		skill.cooldown_total = row[4]
		skill.action = DefaultBindings.ability_action(i)
		fighter.skills.append(skill)
	fighter.skills[2].follow_name = "Rend Ignition"
	fighter.skills[2].follow_left = 1.8
	fighter.skills[2].follow_total = 3.0
	var verdict := fighter.skills[5]
	verdict.charging = true
	verdict.charge = 0.78
	verdict.charge_levels = PackedFloat32Array([0.3, 0.7])
	verdict.perfect_from = 0.7
	verdict.perfect_to = 0.9
	fighter.awakening_name = "Pyre of the Forsworn"
	fighter.awakening_action = DefaultBindings.SUPER
	fighter.dash_max = 2
	fighter.dash_charges = 1
	fighter.dash_recharge = 0.55
	fighter.dash_action = DefaultBindings.DODGE
	fighter.burst_on_dash = true
