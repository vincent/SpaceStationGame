class_name StationCrew
extends RefCounted
## The station's crew as data (pure logic, owned by StationState): who lives
## in which module's bunks (`B` cells) and who works where (`ModuleDef.jobs`;
## staffing boosts Production). CrewSchedule ticks their needs; CrewNPC
## scenes mirror them. Actions return "" or the reason they failed, the
## caller shows it (no toasts here). GameState listens to `joined`.

## A crew member joined, left, or changed job / home.
signal changed
signal joined(member: CrewMember)

## Fully staffed modules produce this much more (scales with staffed / jobs).
const STAFF_BONUS := 0.5

var members: Array[CrewMember] = []

## The owning station (weak: the station owns this object).
var _station: WeakRef
var _next_id := 1


func _init(station: StationState) -> void:
	_station = weakref(station)


func clear() -> void:
	members.clear()
	_next_id = 1
	changed.emit()


func size() -> int:
	return members.size()


func get_member(crew_id: int) -> CrewMember:
	for m in members:
		if m.id == crew_id:
			return m
	return null


# --- Bunks -------------------------------------------------------------------

## Crew bunks of a module: its `B` cells once repaired. The capsule's bunk
## is the castaway's.
func beds(uid: int) -> int:
	var st := _st()
	var def := st.get_def(uid)
	if def == null or def.kind == &"capsule" or st.get_record(uid).state == StationState.State.DERELICT:
		return 0
	return def.crew_beds()


## Crew the station can house.
func capacity() -> int:
	var total := 0
	for uid in _st().uids():
		total += beds(uid)
	return total


func free_beds() -> int:
	return capacity() - members.size()


func residents(uid: int) -> Array[CrewMember]:
	return _where(func(m: CrewMember) -> bool: return m.home_uid == uid)


# --- Jobs --------------------------------------------------------------------

## Job places of a module (0 while derelict).
func jobs(uid: int) -> int:
	var st := _st()
	var def := st.get_def(uid)
	if def == null or st.get_record(uid).state == StationState.State.DERELICT:
		return 0
	return def.jobs


func workers(uid: int) -> Array[CrewMember]:
	return _where(func(m: CrewMember) -> bool: return m.job_uid == uid)


## Production multiplier from staff: 1 unstaffed, 1 + STAFF_BONUS when full.
func staffing(uid: int) -> float:
	var n := jobs(uid)
	if n <= 0:
		return 1.0
	return 1.0 + STAFF_BONUS * float(mini(workers(uid).size(), n)) / float(n)


## Crew without a job, in join order.
func idle() -> Array[CrewMember]:
	return _where(func(m: CrewMember) -> bool: return not m.has_job())


# --- Actions -----------------------------------------------------------------

## A new crew member in the first module with a free bunk (null when they're
## all taken). Empty name: a random unused one. `look` < 0: from the id.
func add(display_name: String = "", look: int = -1) -> CrewMember:
	var home := _free_home()
	if home == 0:
		return null
	var m := CrewMember.new()
	m.id = _next_id
	_next_id += 1
	m.display_name = display_name if display_name != "" else _random_name()
	m.look = look if look >= 0 else m.id - 1
	m.home_uid = home
	members.append(m)
	changed.emit()
	joined.emit(m)
	return m


func remove(crew_id: int) -> void:
	var m := get_member(crew_id)
	if m:
		members.erase(m)
		changed.emit()


## "" when the crew member can work at `uid`, else why not.
func assign_error(crew_id: int, uid: int) -> String:
	var m := get_member(crew_id)
	if m == null:
		return "No such crew member"
	if not _st().has_module(uid) or _st().get_record(uid).state == StationState.State.DERELICT:
		return "Repair it first"
	if jobs(uid) <= 0:
		return "No work there"
	if m.job_uid != uid and workers(uid).size() >= jobs(uid):
		return "Fully staffed"
	return ""


func assign(crew_id: int, uid: int) -> String:
	var err := assign_error(crew_id, uid)
	if err == "" and get_member(crew_id).job_uid != uid:
		get_member(crew_id).job_uid = uid
		changed.emit()
	return err


func unassign(crew_id: int) -> bool:
	var m := get_member(crew_id)
	if m == null or not m.has_job():
		return false
	m.job_uid = -1
	changed.emit()
	return true


## Puts the first crew member without a job to work at `uid`.
func staff(uid: int) -> String:
	if members.is_empty():
		return "No crew yet"
	var free := idle()
	if free.is_empty():
		return "Nobody is free"
	return assign(free[0].id, uid)


## Takes the last crew member assigned to `uid` off the job.
func unstaff(uid: int) -> bool:
	var working := workers(uid)
	return not working.is_empty() and unassign(working.back().id)


## Drops jobs / homes on modules that are gone (or no longer qualify) and
## houses the homeless where there's room.
func fix() -> void:
	var dirty := false
	for m in members:
		if m.has_job() and jobs(m.job_uid) <= 0:
			m.job_uid = -1
			dirty = true
		if m.home_uid > 0 and beds(m.home_uid) <= 0:
			m.home_uid = -1
			dirty = true
	for m in members:
		if m.home_uid <= 0:
			m.home_uid = _free_home()
			dirty = dirty or m.home_uid > 0
	if dirty:
		changed.emit()


# --- Save / load -------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"next_id": _next_id, "members": members.map(func(m: CrewMember) -> Dictionary: return m.to_dict())}


func from_dict(data: Dictionary) -> void:
	members.clear()
	for d: Dictionary in data.get("members", []):
		members.append(CrewMember.from_dict(d))
	_next_id = int(data.get("next_id", 1))
	for m in members:
		_next_id = maxi(_next_id, m.id + 1)
	fix()
	changed.emit()


func _where(pred: Callable) -> Array[CrewMember]:
	var out: Array[CrewMember] = []
	out.assign(members.filter(pred))
	return out


func _st() -> StationState:
	return _station.get_ref()


func _free_home() -> int:
	for uid in _st().uids():
		if residents(uid).size() < beds(uid):
			return uid
	return 0


func _random_name() -> String:
	var taken := members.map(func(m: CrewMember) -> String: return m.display_name)
	var free := Array(CrewMember.NAMES).filter(func(n: String) -> bool: return not taken.has(n))
	return free.pick_random() if not free.is_empty() else "Crew %d" % _next_id
