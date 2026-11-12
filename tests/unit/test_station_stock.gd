extends GutTest
## StationStock: fractional amounts, all-or-nothing removal, save round trip.

var stock: StationStock


func before_each() -> void:
	stock = StationStock.new()


func test_add_and_remove() -> void:
	stock.add(&"food", 3.0)
	assert_eq(stock.amount(&"food"), 3.0)
	assert_true(stock.remove(&"food", 2.0))
	assert_eq(stock.count(&"food"), 1)
	assert_false(stock.remove(&"food", 2.0), "not enough")
	assert_eq(stock.amount(&"food"), 1.0, "unchanged after a failed remove")


func test_fractional_amounts_accumulate() -> void:
	for i in 20:
		stock.add(&"food", 0.05)
	assert_eq(stock.count(&"food"), 1, "20 x 0.05 counts as one whole unit despite float drift")
	stock.add(&"water", 0.6)
	assert_eq(stock.count(&"water"), 0, "shown floored")


func test_has_all() -> void:
	stock.add(&"scrap_metal", 5.0)
	stock.add(&"water", 1.5)
	assert_true(stock.has_all({&"scrap_metal": 5, &"water": 1}))
	assert_false(stock.has_all({&"scrap_metal": 6}))
	assert_false(stock.has_all({&"food": 1}), "unknown resource = 0")
	assert_true(stock.has_all({}))


func test_signals() -> void:
	watch_signals(stock)
	stock.add(&"food", 0.5)
	assert_signal_emitted(stock, "changed")
	assert_signal_emit_count(stock, "count_changed", 1, "a new resource announces itself")
	stock.add(&"food", 0.2)
	assert_signal_emit_count(stock, "count_changed", 1, "no whole unit crossed")
	stock.add(&"food", 0.3)
	assert_signal_emit_count(stock, "count_changed", 2)


func test_save_round_trip() -> void:
	stock.add(&"food", 2.25)
	stock.add(&"scrap_metal", 12.0)
	var copy := StationStock.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(stock.to_dict())))
	assert_almost_eq(copy.amount(&"food"), 2.25, 0.0001)
	assert_eq(copy.count(&"scrap_metal"), 12)
	assert_eq(copy.ids(), [&"food", &"scrap_metal"] as Array[StringName])
