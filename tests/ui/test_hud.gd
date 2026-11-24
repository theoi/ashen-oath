extends TestCase
## HUD layout and readouts from a HudState: 1v2 plates, cooldowns, Soul thresholds.

var hud: Hud


func before_each() -> void:
	hud = add_child_autofree(Hud.new())


func test_one_vs_two_puts_the_pair_on_the_right_with_one_compact_plate() -> void:
	var state := _state(3)
	hud.apply(state)
	var left := hud.plate_for(0).get_parent()
	var right := hud.plate_for(1).get_parent()
	assert_ne(left, right, "teams on opposite sides")
	assert_eq(hud.plate_for(2).get_parent(), right, "both enemies on the right")
	assert_true(hud.plate_for(2).get_combined_minimum_size().x < hud.plate_for(1).get_combined_minimum_size().x,
			"the second enemy's plate is compact")


func test_bars_follow_health_soul_and_guard() -> void:
	var state := _state(2)
	state.fighters[1].health = 250.0
	state.fighters[1].soul = 64.0
	state.fighters[1].guard = 30.0
	hud.apply(state)
	assert_almost_eq(hud.plate_for(1).health_shown(), 0.25, 0.001)
	assert_almost_eq(hud.plate_for(1).soul_shown(), 0.64, 0.001)
	assert_almost_eq(hud.plate_for(1).guard_shown(), 0.3, 0.001)


func test_cooldowns_show_seconds_until_ready() -> void:
	var state := _state(2)
	state.fighters[0].cooldown_left = [0.0, 3.2, 0.4]
	hud.apply(state)
	var bar := hud.ability_bar()
	assert_true(bar.visible)
	assert_true(bar.slot_ready(0))
	assert_false(bar.slot_ready(1))
	assert_eq(bar._counts[1].text, "4", "whole seconds, rounded up")
	assert_eq(bar._counts[2].text, "0.4", "tenths under a second")


func test_super_lights_at_100_soul_and_burst_at_50_in_hitstun() -> void:
	var state := _state(2)
	var bar := hud.ability_bar()
	state.fighters[0].soul = 55.0
	hud.apply(state)
	assert_eq(bar.super_text(), "SUPER")
	assert_false(bar.super_ready(), "55 Soul is not enough for the super")
	state.fighters[0].burst_window = true
	hud.apply(state)
	assert_eq(bar.super_text(), "BURST", "in hitstun the button means Soul Burst")
	assert_true(bar.super_ready(), "50+ Soul in hitstun lights Burst")
	state.fighters[0].soul = 40.0
	hud.apply(state)
	assert_false(bar.super_ready())
	state.fighters[0].burst_window = false
	state.fighters[0].soul = 100.0
	hud.apply(state)
	assert_eq(bar.super_text(), "SUPER")
	assert_true(bar.super_ready())


func test_round_events_queue_announcements() -> void:
	hud.apply(_state(2))
	hud.on_event({"type": MatchEvents.ROUND_INTRO, "round": 2})
	hud.on_event({"type": MatchEvents.FIGHT})
	hud.on_event({"type": MatchEvents.ROUND_WON, "team": 1})
	assert_eq(hud.announced, PackedStringArray(["Round 2", "Fight", "Morrigan wins the round"]))
	assert_eq(hud.announcement_text(), "Round 2", "one at a time")


func _state(count: int) -> HudState:
	var state := HudState.new()
	var names: PackedStringArray = ["Aldric Vane", "Morrigan", "Gorrath"]
	for slot in count:
		var fighter := HudState.Fighter.new()
		fighter.slot = slot
		fighter.name = names[slot]
		fighter.team = 0 if slot == 0 else 1
		fighter.is_player = slot == 0
		fighter.cooldown_total = [5.0, 4.0, 6.0]
		fighter.ability_names = ["Oathfire Lunge", "Brand Rise", "Bulwark Charge"]
		state.fighters.append(fighter)
	return state
