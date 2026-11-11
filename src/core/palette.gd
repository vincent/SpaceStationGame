@tool
class_name Palette
## Synthwave palette from the design doc (yellow, dark blue, violet, neon,
## anthracite). Use these constants instead of hard-coding colors.

const NIGHT := Color("0b0a24")        # deep space background
const DEEP_BLUE := Color("1b1650")    # hull shadows, panels
const VIOLET := Color("6a2fbf")       # primary accent
const NEON_PINK := Color("ff2e97")    # warnings, rim light
const NEON_CYAN := Color("2de2e6")    # interactive, screens
const YELLOW := Color("ffd319")       # highlights, selection
const ORANGE := Color("ff8c2e")       # warm lights
const ANTHRACITE := Color("2a2b31")   # walls, metal
const STEEL := Color("4a4c58")        # floors
const TEXT := Color("f3ecff")
const TEXT_DIM := Color("a89cc8")

# Hull colours, one per faction / era (module root nodes pick theirs).
const HULL_RESCUE := Color("e0ac48")   # the capsule: rescue-service yellow
const HULL_OLD_STATION := Color("6f7690")  # the wreck's original builders
const HULL_COLONY := Color("9a8fc0")   # modules you add yourself
const HULL_TRADER := Color("a35a8a")   # visiting merchants
