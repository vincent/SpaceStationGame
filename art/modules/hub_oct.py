"""Octagon hub (canopy style, mockup 1000037492): a glass-roofed octagonal junction
with a hatch on four flats and a beacon console in the middle. Attach M-P (A, -X) .
offers B (+X), C (+Y / north), D (-Y / south), all M-P. Mount: beacon (roof top)."""
import math

from kit import core
from kit.module import C, box, mask

ID = "hub_oct"
LAYOUT = """\
##c##
#...#
a.C.b
#...#
##d##"""
SEED = 43

APOTHEM = 4.6                     # room x/y -3..3; diagonal flats clear its corners
FACE = APOTHEM - 3.0              # hull flat beyond the room boundary at each door
Z1 = 3.6
PLAN = core.regular_polygon(8, APOTHEM)


def build(m):
    hull = m.canopy_polygon(PLAN, z1=Z1, kt=1.3)
    for letter in "ABCD":
        m.port(letter, [hull], face=FACE, plate=2.0)
    # portholes on the four diagonal flats, two each
    spots = []
    for k in range(4):
        a = math.radians(45 + 90 * k)
        out = (math.cos(a), math.sin(a), 0)
        for s in (-0.8, 0.8):
            side = (-math.sin(a) * s, math.cos(a) * s)
            spots.append(((APOTHEM * out[0] + side[0], APOTHEM * out[1] + side[1], 0.55), out))
    m.porthole_at(spots)

    m.light("main", 0.0, 0.0)
    m.mount("beacon", (0.0, 0.0, Z1 + 0.01))
    m.cut_box(-APOTHEM, APOTHEM, -APOTHEM, APOTHEM, 7.0)

    def decor(mb):  # beacon cone on the console, benches in the diagonal corners
        mb.cyl(0.55, 0.12, (0, 0, 1.15), (0, 0, 0), C["trim_gold"], mask(0.2), mat=1, seg=8)
        mb.cyl(0.4, 0.9, (0, 0, 1.65), (0, 0, 0), C["cream"], mask(0.0, 0.6), mat=1, r2=0.05, seg=8)
        for k in range(4):
            a = 45 + 90 * k
            c = (3.55 * math.cos(math.radians(a)), 3.55 * math.sin(math.radians(a)), 0.3)
            mb.box((c[0] - 0.9, c[1] - 0.3, 0.0), (c[0] + 0.9, c[1] + 0.3, 0.55), C["ivory"], mask(0.2), mat=1,
                   rot=(0, 0, a + 90))
        for x, y in ((-1.4, -1.4), (1.4, -1.4), (-1.4, 1.4), (1.4, 1.4)):   # lamp pads
            box(mb, (x - 0.35, y - 0.35, 0.0), (x + 0.35, y + 0.35, 0.03), C["amber"], mask(0.0, 0.7), mat=1)
    m.prop("decor", decor)
