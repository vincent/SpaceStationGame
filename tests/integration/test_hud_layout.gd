extends GutTest
## The HUD in both orientations: layout, touch sizes, the module sheet's
## snap states, back navigation and the success feedback.

const MAIN := preload("res://src/world/main.tscn")

var main: Node3D
var hud: HUD
var _saved_size: Vector2i


func before_all() -> void:
	_saved_size = get_tree().root.size


func before_each() -> void:
	GameClock.paused = true
	GameState.new_game()
	GameState.set_story_enabled(false)
	main = MAIN.instantiate()
	main.skip_intro = true
	add_child_autofree(main)
	hud = get_tree().get_first_node_in_group(&"hud") as HUD
	var player := main.get_node("Player") as Player
	(main.get_node("Player/Routine") as PlayerRoutine).enabled = false
	await wait_until(func() -> bool: return player.navigation_ready, 5.0)
	await wait_process_frames(3)


func after_each() -> void:
	await _resize(_saved_size)


func after_all() -> void:
	GameClock.paused = false
	GameState.set_story_enabled(true)
	GameState.new_game()


func _resize(size: Vector2i) -> void:
	get_tree().root.size = size
	await wait_process_frames(4)


## Portrait like a phone held upright. Headless windows may refuse to
## resize: the HUD is then switched by hand (same code path after the resize).
func _go_portrait() -> void:
	await _resize(Vector2i(720, 1280))
	if not hud.portrait:
		hud.apply_layout(true)
		await wait_process_frames(3)


func _visible_buttons(root: Node) -> Array[Button]:
	var out: Array[Button] = []
	for b in root.find_children("*", "Button", true, false):
		if (b as Button).is_visible_in_tree():
			out.append(b)
	return out


func test_landscape_sheet_is_docked_left() -> void:
	assert_false(hud.portrait)
	assert_true(hud.sheet.visible)
	assert_almost_eq(hud.sheet.size.x, float(UITheme.SHEET_WIDTH), 1.0, "docked at SHEET_WIDTH")
	assert_almost_eq(hud.sheet.position.x, 0.0, 0.5)
	assert_true(hud.object_panel.visible, "room view: object cards in the sheet")
	assert_true(hud.sheet.is_ancestor_of(hud.object_panel))
	assert_true(hud.sheet.is_ancestor_of(hud.module_panel))


func test_touch_targets_are_comfortable() -> void:
	for b in _visible_buttons(hud.get_node("Root")):
		var r := b.get_global_rect()
		assert_gte(r.size.y, float(UITheme.GHOST_SIZE) - 0.5, "%s is tall enough (%s)" % [b.name, r.size])
		assert_gte(r.size.x, float(UITheme.GHOST_SIZE) - 0.5, "%s is wide enough (%s)" % [b.name, r.size])


func test_portrait_layout() -> void:
	await _go_portrait()
	assert_true(hud.portrait)
	var screen := hud.get_viewport().get_visible_rect().size
	assert_eq(hud.status_bar.get_parent(), hud.top_bar, "chips on their own row")
	assert_almost_eq(hud.top_bar.size.x, hud._layer_root.size.x, 1.0, "top bar spans the width")
	assert_almost_eq(hud.sheet.size.x, hud._layer_root.size.x, 1.0, "full-width sheet")
	assert_almost_eq(hud.sheet.get_global_rect().end.y, screen.y - HUD.MARGIN, 2.0, "sheet at the bottom")
	var dock := hud._nav_row.get_global_rect()
	assert_lte(dock.end.y, hud.sheet.get_global_rect().position.y, "the dock floats above the sheet")
	for c: Control in [hud.top_bar, hud.sheet, hud._nav_row]:
		var r := c.get_global_rect()
		assert_true(Rect2(Vector2.ZERO, screen).grow(1.0).encloses(r), "%s inside the screen (%s)" % [c.name, r])
	var free := hud.free_rect()
	assert_gt(free.position.y, 0.0, "the top bar is not free space")
	assert_almost_eq(free.end.y, hud.sheet.get_global_rect().position.y, 2.0, "nor is the sheet")


func test_portrait_sheet_snaps() -> void:
	await _go_portrait()
	var sheet := hud.sheet
	sheet.set_snap(ModuleSheet.Snap.PEEK, true)
	await wait_process_frames(3)
	var peek := sheet.size.y
	assert_false(hud.object_panel.visible, "peek: module only")
	sheet.set_snap(ModuleSheet.Snap.FULL, true)
	await wait_process_frames(3)
	assert_true(hud.object_panel.visible)
	assert_gt(sheet.size.y, peek, "full is taller")
	assert_true(hud.handle_back(), "back folds the full sheet")
	assert_eq(sheet.snap, ModuleSheet.Snap.HALF)
	sheet.module_panel.fold_requested.emit()  # header tap: HALF <-> PEEK
	assert_eq(sheet.snap, ModuleSheet.Snap.PEEK)


func test_back_closes_the_topmost_thing() -> void:
	hud.production_popover.toggle(StatusBar.POWER, hud.status_bar.chips[StatusBar.POWER])
	hud.inventory_panel.toggle()
	assert_true(hud.handle_back())
	assert_false(hud.production_popover.visible, "popover first")
	assert_true(hud.inventory_panel.visible)
	assert_true(hud.handle_back())
	assert_false(hud.inventory_panel.visible)
	assert_true(main.is_room_view())
	watch_signals(EventBus)
	assert_true(hud.handle_back(), "room view -> station view")
	assert_signal_emitted(EventBus, "station_view_requested")


func test_reward_flies_to_its_chip() -> void:
	var pile: Interactable = null
	for node in main.find_children("*", "Area3D", true, false):
		if node is Interactable and (node as Interactable).display_name.to_lower().contains("salvage"):
			pile = node
	assert_not_null(pile)
	GameState.give({&"scrap_metal": 3}, pile)
	await wait_process_frames(2)
	assert_eq(hud.feedback.active_labels(), 1, "one +3 label in flight")
	await wait_seconds(FeedbackLayer.POP_SECONDS + FeedbackLayer.FLY_SECONDS + 0.6)
	assert_eq(hud.feedback.active_labels(), 0, "it landed")


func test_success_notice_and_clock_skip() -> void:
	hud.show_toast("Wreck core repaired.", &"success")
	assert_true(hud._toast_icon.visible, "success toasts get a check")
	hud.show_toast("Hello")
	assert_false(hud._toast_icon.visible)
	GameState.spend_time(240.0)
	await wait_process_frames(2)
	var badge := hud.top_bar.find_child("SkipBadge", true, false) as Label
	assert_eq(badge.text, "+4 h")
	assert_true(badge.visible)
