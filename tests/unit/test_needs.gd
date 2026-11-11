extends GutTest

var needs: Needs


func before_each() -> void:
	needs = Needs.new()


func test_starts_full() -> void:
	for need in needs.names():
		assert_eq(needs.get_value(need), Needs.MAX, String(need))


func test_values_are_clamped() -> void:
	needs.change(Needs.FOOD, 50)
	assert_eq(needs.get_value(Needs.FOOD), Needs.MAX)
	needs.change(Needs.FOOD, -500)
	assert_eq(needs.get_value(Needs.FOOD), 0.0)


func test_tick_applies_default_decay() -> void:
	needs.tick(2.0)
	assert_almost_eq(needs.get_value(Needs.FOOD), Needs.MAX - 2.0 * Needs.DEFAULT_DECAY[Needs.FOOD], 0.001)
	assert_almost_eq(needs.get_value(Needs.ENERGY), Needs.MAX - 2.0 * Needs.DEFAULT_DECAY[Needs.ENERGY], 0.001)


func test_negative_override_restores() -> void:
	needs.set_value(Needs.ENERGY, 10)
	needs.tick(4.0, {Needs.ENERGY: -10.0})
	assert_almost_eq(needs.get_value(Needs.ENERGY), 50.0, 0.001)


func test_critical_signal_fires_once_when_crossing() -> void:
	watch_signals(needs)
	needs.set_value(Needs.FOOD, 20)
	needs.set_value(Needs.FOOD, 10)
	needs.set_value(Needs.FOOD, 5)
	assert_signal_emit_count(needs, "became_critical", 1)
	assert_true(needs.is_critical(Needs.FOOD))


func test_changed_not_emitted_when_value_unchanged() -> void:
	watch_signals(needs)
	needs.set_value(Needs.FOOD, Needs.MAX)
	assert_signal_not_emitted(needs, "changed")


func test_save_round_trip() -> void:
	needs.set_value(Needs.MORALE, 42)
	var other := Needs.new()
	other.from_dict(needs.to_dict())
	assert_eq(other.get_value(Needs.MORALE), 42.0)
