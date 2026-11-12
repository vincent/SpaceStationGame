class_name EncounterDef
extends Resource
## One story beat ("storylet"): when `trigger` fires and `condition` holds, it
## may be picked (priority first, then weighted random) and shown on its
## `channel`. Its `outcomes` apply when it starts; each choice adds its own.
## Authoring guide: docs/CONTENT_PIPELINE.md ("Encounters").

## Game events that wake encounters up. `subject` (readable in conditions)
## says what the event was about.
const TRIGGERS: Dictionary[StringName, String] = {
	&"start": "a new game begins",
	&"hour": "every game hour",
	&"day": "every new day",
	&"repaired": "a module was repaired (subject = module id)",
	&"powered": "a module was switched on (subject = module id)",
	&"upgraded": "an upgrade was installed (subject = upgrade id)",
	&"built": "a module was built (subject = module id)",
	&"visitor": "a visitor ship docked (subject = ship module id)",
	&"traded": "a trade went through",
	&"produced": "a resource was produced for the first time (subject = resource id, e.g. food)",
	&"interacted": "the player opened an object's menu (subject = scene name, e.g. salvage_pile)",
	&"scheduled": "only through the `schedule` outcome",
}
## dialog: modal-ish panel with choices; radio: the same panel styled as a
## transmission; toast: lines flash as toasts, no choices.
const CHANNELS: Array[StringName] = [&"dialog", &"radio", &"toast"]

@export var id: StringName
@export var trigger: StringName = &"hour"
## Godot Expression evaluated against StoryContext (empty = always true).
## e.g. `repaired("wreck_core") and not flag("met_signal") and day() >= 2`
@export_multiline var condition: String = ""
## Higher wins; ties are broken by weighted random.
@export var priority: int = 0
@export var weight: float = 1.0
## Chance (0..1) to fire each time the trigger matches (random flavour beats).
@export_range(0.0, 1.0) var chance: float = 1.0
## Fire at most once per game.
@export var once: bool = true
## Minimum game hours between two firings (repeatable beats).
@export var cooldown_hours: float = 0.0

@export var channel: StringName = &"dialog"
@export var title: String = ""
@export var lines: PackedStringArray = []
## Applied as soon as the encounter starts (see StoryOutcome for the verbs).
@export var outcomes: PackedStringArray = []
## Player choices: {"text": String, "outcomes": PackedStringArray,
## "condition": String (optional: greyed out when false)}.
## Empty = a single "Continue" button.
@export var choices: Array[Dictionary] = []


## Problems with this definition alone (expressions are checked by
## StoryContext.check_expression, outcomes by StoryOutcome.validate).
func validate() -> PackedStringArray:
	var errors: PackedStringArray = []
	if id == &"":
		errors.append("%s: id is required" % resource_path)
	if not TRIGGERS.has(trigger):
		errors.append("%s: unknown trigger %s (known: %s)" % [id, trigger, TRIGGERS.keys()])
	if not CHANNELS.has(channel):
		errors.append("%s: unknown channel %s" % [id, channel])
	if lines.is_empty():
		errors.append("%s: needs at least one line" % id)
	if channel == &"toast" and not choices.is_empty():
		errors.append("%s: toast encounters can't have choices" % id)
	for choice in choices:
		if String(choice.get("text", "")) == "":
			errors.append("%s: every choice needs a text" % id)
	return errors


## Outcome lines of the encounter itself and of every choice.
func all_outcomes() -> PackedStringArray:
	var out := outcomes.duplicate()
	for choice in choices:
		out.append_array(PackedStringArray(choice.get("outcomes", [])))
	return out


## Condition strings of the encounter and of its choices.
func all_conditions() -> PackedStringArray:
	var out: PackedStringArray = [condition]
	for choice in choices:
		out.append(String(choice.get("condition", "")))
	return out
