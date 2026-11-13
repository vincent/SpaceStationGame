class_name CrewMember
extends RefCounted
## One crew member as data: who they are, their needs, where they sleep
## (`home_uid`) and work (`job_uid`, -1 = no job). Owned by StationState;
## the CrewNPC scene only mirrors it. `activity` is set by CrewSchedule.

## Body colors, picked by `look`.
const LOOKS: Array[Color] = [
	Palette.NEON_CYAN, Palette.MINT, Palette.ORANGE, Palette.NEON_PINK, Palette.VIOLET, Palette.HULL_COLONY,
]
const NAMES: PackedStringArray = [
	"Ines", "Tomas", "Yara", "Bao", "Kofi", "Mira", "Juno", "Ravi", "Selma", "Oren", "Lucia", "Dax",
]

var id := 0
var display_name := ""
var look := 0
var needs := Needs.new()
var job_uid := -1
var home_uid := -1
var activity: StringName = &"idle"


func color() -> Color:
	return LOOKS[posmod(look, LOOKS.size())]


func has_job() -> bool:
	return job_uid > 0


func to_dict() -> Dictionary:
	return {
		"id": id, "name": display_name, "look": look, "needs": needs.to_dict(),
		"job": job_uid, "home": home_uid, "activity": String(activity),
	}


static func from_dict(data: Dictionary) -> CrewMember:
	var m := CrewMember.new()
	m.id = int(data.get("id", 0))
	m.display_name = String(data.get("name", "Crew"))
	m.look = int(data.get("look", 0))
	m.needs.from_dict(data.get("needs", {}))
	m.job_uid = int(data.get("job", -1))
	m.home_uid = int(data.get("home", -1))
	m.activity = StringName(data.get("activity", "idle"))
	return m
