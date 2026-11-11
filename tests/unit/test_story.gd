extends GutTest
## Pure story classes: StoryState, StoryOutcome, StoryContext, Storyteller.

var story: StoryState
var context: StoryContext


func before_each() -> void:
	story = StoryState.new()
	var items := ItemDB.new()
	items.load_dir()
	var modules := ModuleDB.new()
	modules.load_dirs()
	var station := StationState.new(modules)
	station.add_module(&"wreck_core", 0, &"", StationState.State.DERELICT, 1.0, false)
	var inventory := Inventory.new(items, 10)
	inventory.add(&"scrap_metal", 3)
	context = StoryContext.new(story, inventory, station, Needs.new())


func test_flags_and_counters() -> void:
	assert_false(story.flag(&"a"))
	story.set_flag(&"a")
	assert_true(story.flag(&"a"))
	story.add(&"n", 2)
	story.add(&"n", -1)
	assert_eq(story.count(&"n"), 1)
	story.set_flag(&"a", false)
	assert_false(story.flag(&"a"))


func test_schedule_pops_in_order() -> void:
	story.schedule(&"late", 300.0)
	story.schedule(&"early", 100.0)
	assert_eq(story.pop_due(50.0).size(), 0)
	assert_eq(story.pop_due(200.0), [&"early"] as Array[StringName])
	assert_eq(story.pop_due(400.0), [&"late"] as Array[StringName])


func test_state_round_trips() -> void:
	story.set_flag(&"met")
	story.add(&"trades", 3)
	story.mark_seen(&"intro", 480.0)
	story.schedule(&"rescue", 900.0)
	var copy := StoryState.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(story.to_dict())))
	assert_true(copy.flag(&"met"))
	assert_eq(copy.count(&"trades"), 3)
	assert_eq(copy.times_seen(&"intro"), 1)
	assert_eq(copy.last_seen(&"intro"), 480.0)
	assert_eq(copy.pop_due(1000.0), [&"rescue"] as Array[StringName])


func test_outcome_parse() -> void:
	assert_eq(StoryOutcome.parse("give scrap_metal 3"), {"verb": &"give", "args": PackedStringArray(["scrap_metal", "3"])})
	assert_eq(StoryOutcome.parse("toast Hello there, SR-7").args, PackedStringArray(["Hello there, SR-7"]))
	assert_eq(StoryOutcome.parse("visitor").verb, &"visitor")
	assert_eq(StoryOutcome.parse("give scrap_metal"), {}, "missing argument")
	assert_eq(StoryOutcome.parse("explode station"), {}, "unknown verb")


func test_conditions() -> void:
	story.set_flag(&"met")
	assert_true(context.evaluate(""))
	assert_true(context.evaluate('flag("met") and not flag("other")'))
	assert_true(context.evaluate('has_item("scrap_metal", 3) and item("scrap_metal") == 3'))
	assert_false(context.evaluate('repaired("wreck_core")'), "wreck starts derelict")
	assert_true(context.evaluate('has_module("wreck_core") and not powered("wreck_core")'))
	assert_true(context.evaluate('subject == "wreck_core"', &"wreck_core"))
	assert_eq(context.check_expression('flag("x") or seen("intro") > 0'), "")
	assert_ne(context.check_expression('flag("x"'), "", "parse error reported")
	assert_ne(context.check_expression('nope()'), "", "unknown function reported")


func test_storyteller_rules() -> void:
	var db := EncounterDB.new()
	var once := _enc(&"once", 0)
	var repeat := _enc(&"repeat", 0)
	repeat.once = false
	repeat.cooldown_hours = 2.0
	var important := _enc(&"important", 5)
	important.condition = 'flag("go")'
	for e in [once, repeat, important]:
		db.register(e)
	var teller := Storyteller.new(db, story, context)
	assert_eq(teller.candidates(&"hour", &"", 0.0).size(), 2, "condition filters 'important'")
	story.set_flag(&"go")
	assert_eq(teller.pick(&"hour", &"", 0.0), important, "highest priority wins")
	story.mark_seen(&"important", 0.0)
	story.mark_seen(&"once", 0.0)
	story.mark_seen(&"repeat", 0.0)
	assert_eq(teller.candidates(&"hour", &"", 60.0).size(), 0, "once + cooldown")
	assert_eq(teller.candidates(&"hour", &"", 121.0), [repeat] as Array[EncounterDef], "cooldown over")


func _enc(id: StringName, priority: int) -> EncounterDef:
	var e := EncounterDef.new()
	e.id = id
	e.trigger = &"hour"
	e.priority = priority
	e.lines = PackedStringArray(["..."])
	return e
