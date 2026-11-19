"""Dome hub (canopy style, the junction of mockups 1000037494-96): the octagon hub
under a faceted glass dome, a round console in the middle. Attach M-P (A, -X) .
offers B (+X), C (+Y / north), all M-P. Mount: lantern (dome top)."""
import math

from kit import core
from kit.module import C, box, mask

ID = "hub_dome"
LAYOUT = """\
##c##
#...#
a.C.b
#...#
#####"""
SEED = 47

APOTHEM = 4.6
FACE = APOTHEM - 3.0
PLAN = core.regular_polygon(8, APOTHEM)
DOME = [(0.9, 3.2), (2.0, 4.0), (3.1, 4.4)]


def build(m):
    hull = m.canopy_polygon(PLAN, roof=DOME)
    for letter in "ABC":
        m.port(letter, [hull], face=FACE, plate=2.0)
    spots = []
    for a in (-90, -45, 135, 45):     # portholes on the flats without a port
        r = math.radians(a)
        out = (math.cos(r), math.sin(r), 0)
        for s in ((-0.8, 0.8) if a == -90 else (0.0,)):
            spots.append(((APOTHEM * out[0] - math.sin(r) * s, APOTHEM * out[1] + math.cos(r) * s, 0.55), out))
    m.porthole_at(spots)

    m.light("main", 0.0, 0.0)
    m.mount("lantern", (0.0, 0.0, DOME[-1][1] + 0.01))
    m.cut_box(-APOTHEM, APOTHEM, -APOTHEM, APOTHEM, 7.0)

    def decor(mb):  # gold ring round the console, stools in the diagonal corners, lamp pads
        core.prism_ring(mb, (0, 0, 0.0), (0, 0, 1), 1.3, 1.0, 0.03, C["trim_gold"], mask(0.2), mat=1)
        for k in range(4):
            a = math.radians(45 + 90 * k)
            x, y = 3.6 * math.cos(a), 3.6 * math.sin(a)
            mb.cyl(0.35, 0.5, (x, y, 0.25), (0, 0, 0), C["steel_lt"], mask(0.2), mat=1, seg=8)
            mb.cyl(0.38, 0.06, (x, y, 0.53), (0, 0, 0), C["ivory"], mask(0.2), mat=1, seg=8)
        for x, y in ((-1.4, -1.4), (1.4, -1.4), (-1.4, 1.4), (1.4, 1.4)):
            box(mb, (x - 0.35, y - 0.35, 0.0), (x + 0.35, y + 0.35, 0.03), C["amber"], mask(0.0, 0.7), mat=1)
    m.prop("decor", decor)
