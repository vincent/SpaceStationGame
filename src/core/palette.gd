@tool
class_name Palette
## Synthwave palette from the design doc (yellow, dark blue, violet, neon,
## anthracite). Use these constants instead of hard-coding colors.

const NIGHT := Color("0b0a24")        # deep space background
# scene lighting (mockup look: neutral, soft, every face readable)
const SPACE := Color("181a30")        # background behind the starfield
# space backdrop (Backdrop + starfield/nebula shaders)
const SPACE_TOP := Color("101029")    # gradient, top-left
const SPACE_MID := Color("141935")    # gradient, middle
const SPACE_BOTTOM := Color("1c1533") # gradient, bottom-right (violet hint)
const NEBULA_DEEP := Color("1b2a6b")  # nebula body
const NEBULA_VIOLET := Color("5a3a8a")
const NEBULA_TEAL := Color("2f7f8f")
const NEBULA_CORE := Color("9ea8e6")  # densest cores
const AMBIENT := Color("b1b3c4")      # shadow sides stay light grey-blue
const RIM := Color("dfe4ff")          # faint pale rim on silhouettes
const DEEP_BLUE := Color("1b1650")    # hull shadows, panels
const VIOLET := Color("6a2fbf")       # primary accent
const NEON_PINK := Color("ff2e97")    # warnings, rim light
const NEON_CYAN := Color("2de2e6")    # interactive, screens
const YELLOW := Color("ffd319")       # highlights, selection
const ORANGE := Color("ff8c2e")       # warm lights
const ANTHRACITE := Color("2a2b31")   # walls, metal
const STEEL := Color("4a4c58")        # metal details
const FLOOR := Color("8b91ad")        # deck tiles (= kit swatch "deck")
const TEXT := Color("f3ecff")
const TEXT_DIM := Color("a89cc8")
const MINT := Color("5ef2a0")         # gains, production up (losses use NEON_PINK)

# Hull colours, one per faction / era (module root nodes pick theirs).
const HULL_RESCUE := Color("e0ac48")   # the capsule: rescue-service yellow
const HULL_OLD_STATION := Color("6f7690")  # the wreck's original builders
const HULL_COLONY := Color("9a8fc0")   # modules you add yourself
const HULL_TRADER := Color("a35a8a")   # visiting merchants
