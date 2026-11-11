class_name Storyteller
extends RefCounted
## Chooses which encounter (if any) answers a game event. Pure selection:
## GameState applies the result (outcomes, UI). Rules, in order:
##   1. listens to the trigger (or is the scheduled id for "scheduled")
##   2. `once` encounters that already fired are skipped
##   3. still in cooldown -> skipped
##   4. `condition` holds (StoryContext)
##   5. `chance` roll passes
##   6. highest priority wins; ties -> weighted random

var db: EncounterDB
var story: StoryState
var context: StoryContext
var rng := RandomNumberGenerator.new()


func _init(p_db: EncounterDB, p_story: StoryState, p_context: StoryContext) -> void:
	db = p_db
	story = p_story
	context = p_context
	rng.randomize()


## Every encounter that may answer `trigger` right now.
func candidates(trigger: StringName, subject: StringName, now: float) -> Array[EncounterDef]:
	var out: Array[EncounterDef] = []
	for enc in db.for_trigger(trigger):
		if is_available(enc, subject, now) and rng.randf() < enc.chance:
			out.append(enc)
	return out


## Passes rules 2-4 (no chance roll): used for scheduled and forced beats too.
func is_available(enc: EncounterDef, subject: StringName, now: float) -> bool:
	if enc.once and story.times_seen(enc.id) > 0:
		return false
	if enc.cooldown_hours > 0.0 and now - story.last_seen(enc.id) < enc.cooldown_hours * 60.0:
		return false
	return context.evaluate(enc.condition, subject)


## The encounter answering `trigger`, or null.
func pick(trigger: StringName, subject: StringName, now: float) -> EncounterDef:
	var found := candidates(trigger, subject, now)
	if found.is_empty():
		return null
	var best := found.map(func(e: EncounterDef) -> int: return e.priority).max() as int
	var top: Array[EncounterDef] = []
	top.assign(found.filter(func(e: EncounterDef) -> bool: return e.priority == best))
	var total := 0.0
	for e in top:
		total += maxf(e.weight, 0.0)
	var roll := rng.randf() * total
	for e in top:
		roll -= maxf(e.weight, 0.0)
		if roll <= 0.0:
			return e
	return top.back()
