@tool
class_name DayCycle
## Interior lighting mood from the station clock: 0 = cool work light (day),
## 1 = warm night light. Ramps over 2 h at dawn (06-08) and dusk (20-22).

const DAWN_START := 6.0
const DAWN_END := 8.0
const DUSK_START := 20.0
const DUSK_END := 22.0


static func warmth(hour: float) -> float:
	var h := fposmod(hour, 24.0)
	if h < DAWN_START or h >= DUSK_END:
		return 1.0
	if h < DAWN_END:
		return 1.0 - smoothstep(DAWN_START, DAWN_END, h)
	if h >= DUSK_START:
		return smoothstep(DUSK_START, DUSK_END, h)
	return 0.0


## Interior light energy multiplier: night dims the rooms.
static func light_scale(hour: float) -> float:
	return lerpf(1.0, 0.55, warmth(hour))
