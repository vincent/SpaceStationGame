extends GutTest
## Validates the real item data files, so a broken .tres fails CI.

var db: ItemDB


func before_all() -> void:
	db = ItemDB.new()
	db.load_dir()


func test_loads_items() -> void:
	assert_gt(db.ids().size(), 0)


func test_every_item_is_valid() -> void:
	for id in db.ids():
		var item := db.get_item(id)
		assert_ne(item.display_name, "", "%s has a name" % id)
		assert_gt(item.max_stack, 0, "%s max_stack" % id)
		if item.usable:
			assert_false(item.use_effects.is_empty(), "%s is usable but has no effect" % id)
		for need in item.use_effects:
			assert_has(Needs.DEFAULT_DECAY, need, "%s affects unknown need %s" % [id, need])


func test_starting_items_exist() -> void:
	for id in GameState.STARTING_ITEMS:
		assert_true(db.has(id), "starting item %s exists" % id)
