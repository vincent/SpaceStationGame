class_name CrewSchedule
extends RefCounted
## Crew life rules (pure, static). What a crew member does comes from the
## clock and their needs; `tick` advances their needs and meals on the data
## side, so skipping time works without any NPC walking anywhere.
##
##   sleeping  at night (22-6) or when exhausted
##   eating    during a meal window while hungry (a meal takes MEAL_FOOD
##             from the station stock)
##   working   on shift (SHIFT hours) when assigned to a module
##   idle      otherwise (wanders around)

const SHIFT := Vector2(8, 18)
## Meal windows, [from, to) in hours (the castaway's, see PlayerRoutine).
const MEAL_HOURS: Array[Vector2] = [Vector2(7, 8), Vector2(12, 13), Vector2(19, 20)]
## Food taken from the station stock per meal, and the need it restores.
const MEAL_FOOD := 0.4
const MEAL_RESTORES := 55.0
## A meal is eaten when the food need is below this during a meal window
## (or below Needs.CRITICAL at any time).
const HUNGRY := 70.0
## Extra morale loss per hour while starving (food need critical).
const STARVING_MORALE := 3.0
## Exhausted crew go to bed whatever the hour.
const EXHAUSTED := 15.0
## Sub-step for long time skips (minutes), so the hour is tracked.
const STEP_MINUTES := 15.0


static func activity(hour: float, needs: Needs, has_job: bool) -> StringName:
	var night := hour >= 22.0 or hour < 6.0
	if night or needs.get_value(Needs.ENERGY) < EXHAUSTED:
		return &"sleeping"
	if is_meal_time(hour) and needs.get_value(Needs.FOOD) < HUNGRY + 10.0:
		return &"eating"
	if has_job and hour >= SHIFT.x and hour < SHIFT.y:
		return &"working"
	return &"idle"


static func is_meal_time(hour: float) -> bool:
	for window in MEAL_HOURS:
		if hour >= window.x and hour < window.y:
			return true
	return false


## Advances every crew member of `station` by `minutes`, from `start_minutes`
## (GameClock.total_minutes before the advance). `rates` = activity -> need
## decay overrides (GameState.ACTIVITY_RATES). Returns the food eaten.
static func tick(station: StationState, stock: StationStock, start_minutes: float, minutes: float,
		rates: Dictionary) -> float:
	var eaten := 0.0
	if station.crew.size() == 0:
		return eaten
	var done := 0.0
	while done < minutes - 0.0001:
		var step := minf(STEP_MINUTES, minutes - done)
		var hour := fposmod((start_minutes + done) / 60.0, 24.0)
		for m in station.crew.members:
			m.activity = activity(hour, m.needs, m.has_job())
			m.needs.tick(step / 60.0, rates.get(m.activity, {}))
			if m.needs.is_critical(Needs.FOOD):
				m.needs.change(Needs.MORALE, -STARVING_MORALE * step / 60.0)
			var hungry := m.needs.get_value(Needs.FOOD) < (HUNGRY if m.activity == &"eating" else Needs.CRITICAL)
			if hungry and stock.amount(&"food") >= MEAL_FOOD:
				stock.remove(&"food", MEAL_FOOD)
				m.needs.change(Needs.FOOD, MEAL_RESTORES)
				eaten += MEAL_FOOD
		done += step
	return eaten
