extends GutTest
## Validates every data/encounters/*.tres: fields, conditions, outcomes, links.

var encounters: EncounterDB
var items: ItemDB
var modules: ModuleDB
var context: StoryContext


func before_all() -> void:
	encounters = EncounterDB.new()
	encounters.load_dir()
	items = ItemDB.new()
	items.load_dir()
	modules = ModuleDB.new()
	modules.load_dirs()
	var station := StationState.new(modules)
	context = StoryContext.new(StoryState.new(), Inventory.new(items, 10), station, Needs.new())


func test_encounters_load() -> void:
	assert_gt(encounters.ids().size(), 0)
	assert_eq(encounters.for_trigger(&"start").size(), 1, "exactly one intro")


func test_definitions_are_valid() -> void:
	for id in encounters.ids():
		var errors := encounters.get_encounter(id).validate()
		assert_eq(errors.size(), 0, "\n".join(errors))


func test_conditions_parse_and_run() -> void:
	for id in encounters.ids():
		for condition in encounters.get_encounter(id).all_conditions():
			var err := context.check_expression(condition)
			assert_eq(err, "", "%s: %s" % [id, err])


func test_outcomes_are_valid() -> void:
	for id in encounters.ids():
		for line in encounters.get_encounter(id).all_outcomes():
			var err := StoryOutcome.validate(line, items, modules, encounters)
			assert_eq(err, "", "%s: %s" % [id, err])


func test_scheduled_encounters_are_reachable() -> void:
	var targets := {}
	for id in encounters.ids():
		for line in encounters.get_encounter(id).all_outcomes():
			var o := StoryOutcome.parse(line)
			if o.get("verb") == &"schedule":
				targets[StringName(o.args[0])] = true
	for enc in encounters.for_trigger(&"scheduled"):
		assert_true(targets.has(enc.id), "%s is 'scheduled' but nothing schedules it" % enc.id)
