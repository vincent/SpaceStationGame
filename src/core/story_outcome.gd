class_name StoryOutcome
extends RefCounted
## Encounter outcome lines: "<verb> <args...>", applied by
## GameState.apply_outcome(). One verb per line, arguments separated by spaces
## (`toast` takes the rest of the line).
##
##   give <item> <n>            add items
##   take <item> <n>            remove items (as many as there are)
##   need <need> <delta>        change a need (food, energy, morale)
##   flag <name> / unflag <name>
##   count <name> <delta>       story counter
##   schedule <encounter> <h>   fire that encounter in <h> game hours
##                              (its condition is checked then)
##   toast <text...>            a toast message
##   visitor                    a trader ship heads for a free powered dock
##   wear <module> <delta>      change a module's wear (0..1)
##   recruit                    a new crew member (random name) takes a free
##                              bunk (toast if none: check free_beds() first)

## verb -> argument kinds ("item", "need", "name", "encounter", "module",
## "int", "float", "text").
const VERBS: Dictionary[StringName, Array] = {
	&"give": ["item", "int"],
	&"take": ["item", "int"],
	&"need": ["need", "float"],
	&"flag": ["name"],
	&"unflag": ["name"],
	&"count": ["name", "int"],
	&"schedule": ["encounter", "float"],
	&"toast": ["text"],
	&"visitor": [],
	&"wear": ["module", "float"],
	&"recruit": [],
}


## {"verb": StringName, "args": PackedStringArray}, or {} if malformed.
static func parse(line: String) -> Dictionary:
	var words := line.strip_edges().split(" ", false)
	if words.is_empty() or not VERBS.has(StringName(words[0])):
		return {}
	var verb := StringName(words[0])
	var kinds: Array = VERBS[verb]
	var args: PackedStringArray = words.slice(1)
	if kinds == ["text"]:
		args = [" ".join(args)]
	if args.size() != kinds.size():
		return {}
	return {"verb": verb, "args": args}


## "" when the line is valid against the databases, else why not.
static func validate(line: String, items: ItemDB, modules: ModuleDB, encounters: EncounterDB) -> String:
	var o := parse(line)
	if o.is_empty():
		return "bad outcome '%s' (verbs: %s)" % [line, VERBS.keys()]
	var kinds: Array = VERBS[o.verb]
	for i in kinds.size():
		var a: String = o.args[i]
		var ok := true
		match kinds[i]:
			"item":
				ok = items.get_item(StringName(a)) != null
			"need":
				ok = Needs.DEFAULT_DECAY.has(StringName(a))
			"encounter":
				ok = encounters.get_encounter(StringName(a)) != null
			"module":
				ok = modules.get_module(StringName(a)) != null
			"int":
				ok = a.is_valid_int()
			"float":
				ok = a.is_valid_float()
			"text":
				ok = a != ""
		if not ok:
			return "'%s': bad %s '%s'" % [line, kinds[i], a]
	return ""
