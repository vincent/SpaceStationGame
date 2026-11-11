extends GutTest

var db: ItemDB
var inv: Inventory


func _item(id: StringName, max_stack: int) -> ItemData:
	var item := ItemData.new()
	item.id = id
	item.max_stack = max_stack
	return item


func before_each() -> void:
	db = ItemDB.new()
	db.register(_item(&"bolt", 10))
	db.register(_item(&"cell", 1))
	inv = Inventory.new(db, 4)


func test_add_stacks_then_fills_new_slots() -> void:
	assert_eq(inv.add(&"bolt", 25), 0)
	assert_eq(inv.get_slot(0).count, 10)
	assert_eq(inv.get_slot(1).count, 10)
	assert_eq(inv.get_slot(2).count, 5)
	assert_eq(inv.count_of(&"bolt"), 25)


func test_add_returns_overflow_when_full() -> void:
	assert_eq(inv.add(&"cell", 6), 2)
	assert_eq(inv.count_of(&"cell"), 4)


func test_remove_is_all_or_nothing() -> void:
	inv.add(&"bolt", 3)
	assert_false(inv.remove(&"bolt", 5))
	assert_eq(inv.count_of(&"bolt"), 3)
	assert_true(inv.remove(&"bolt", 3))
	assert_true(inv.is_empty_slot(0))


func test_move_swaps_different_items() -> void:
	inv.add(&"bolt", 1)
	inv.add(&"cell", 1)
	inv.move(0, 1)
	assert_eq(inv.get_slot(0).id, &"cell")
	assert_eq(inv.get_slot(1).id, &"bolt")


func test_move_merges_same_item_up_to_max_stack() -> void:
	inv.slots[0] = {"id": &"bolt", "count": 7}
	inv.slots[1] = {"id": &"bolt", "count": 6}
	inv.move(0, 1)
	assert_eq(inv.get_slot(1).count, 10)
	assert_eq(inv.get_slot(0).count, 3)


func test_move_into_empty_slot() -> void:
	inv.add(&"bolt", 2)
	inv.move(0, 3)
	assert_true(inv.is_empty_slot(0))
	assert_eq(inv.get_slot(3).count, 2)


func test_has_all() -> void:
	inv.add(&"bolt", 2)
	inv.add(&"cell", 1)
	assert_true(inv.has_all({&"bolt": 2, &"cell": 1}))
	assert_false(inv.has_all({&"bolt": 3}))


func test_changed_signal() -> void:
	watch_signals(inv)
	inv.add(&"bolt", 1)
	assert_signal_emitted(inv, "changed")


func test_save_round_trip_survives_json() -> void:
	inv.add(&"bolt", 12)
	inv.add(&"cell", 1)
	var json := JSON.stringify(inv.to_dict())
	var other := Inventory.new(db, 4)
	other.from_dict(JSON.parse_string(json))
	assert_eq(other.count_of(&"bolt"), 12)
	assert_eq(other.count_of(&"cell"), 1)
	assert_typeof(other.get_slot(0).id, TYPE_STRING_NAME)
