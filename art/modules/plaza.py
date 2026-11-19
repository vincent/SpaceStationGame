"""Plaza (canopy style, mockup 1000037504): a five-armed glass star round a glowing
pool, one arm the entrance corridor, the others corners for servers, a bar, plants
and benches. Attach M-P (A, -X arm tip), no other slot. Mount: spire (centre)."""
import math

from kit import core
from kit.module import C, box, mask

ID = "plaza"
LAYOUT = """\
########
###....#
a...##.#
a...##.#
###....#
########"""
SEED = 67
BUDGET = 15000

CX = 2.0                          # star centre = room centre (room x -2..6, y -4..4)
TIP = 8.3                         # arm tip flats (the -X one ends the entrance corridor at x = -6.3)
TIP_HALF = 2.6
INNER = 6.5                       # concave corners
Z1 = 3.8


def star():
    pts = []
    for k in range(5):
        a = math.pi + 2 * math.pi * k / 5          # arm 0 points -X
        d = (math.cos(a), math.sin(a))
        n = (-d[1], d[0])
        pts.append((CX + TIP * d[0] - TIP_HALF * n[0], TIP * d[1] - TIP_HALF * n[1]))
        pts.append((CX + TIP * d[0] + TIP_HALF * n[0], TIP * d[1] + TIP_HALF * n[1]))
        b = a + math.pi / 5
        pts.append((CX + INNER * math.cos(b), INNER * math.sin(b)))
    return pts


def arm_centre(k, r=5.6):
    a = math.pi + 2 * math.pi * k / 5
    return CX + r * math.cos(a), r * math.sin(a), a


def build(m):
    hull = m.canopy_polygon(star(), z1=Z1, kt=1.3, spokes=True)
    m.port("A", [hull], face=0.3, plate=2.0)

    m.light("pool", CX, 0.0)
    m.light("hall", -1.0, 0.0)
    m.mount("spire", (CX, 0.0, Z1 + 0.01))
    m.cut_box(CX - TIP, CX + TIP, -TIP, TIP, 7.0)

    def plaza(mb):
        # the pool on the blocked centre: gold rim, glowing cyan water
        box(mb, (0.0, -2.0, -0.2), (4.0, 2.0, 0.0), C["deck"], mask(0.1), mat=1)
        core.prism_ring(mb, (CX, 0, 0.0), (0, 0, 1), 1.95, 1.6, 0.3, C["trim_gold"], mask(0.2), mat=1)
        mb.cyl(1.65, 0.2, (CX, 0, 0.1), (0, 0, 0), C["cyan"], mask(0.0, 0.8), mat=1, seg=8)
        # arm 1 (north-west): server racks with glowing screens
        x, y, a = arm_centre(1)
        for i in range(3):
            for j in range(2):
                px, py = x - 1.0 + i * 1.0, y + j * 1.0
                box(mb, (px - 0.4, py - 0.4, 0.0), (px + 0.4, py + 0.4, 1.8), C["navy"], mask(0.3), mat=1)
                box(mb, (px - 0.3, py - 0.42, 1.1), (px + 0.3, py - 0.4, 1.6),
                    C["cyan" if (i + j) % 2 else "amber"], mask(0.0, 1.0), mat=1)
        # arm 2 (north-east): bar counter and stools
        x, y, a = arm_centre(2)
        box(mb, (x - 1.4, y - 0.4, 0.0), (x + 1.4, y + 0.4, 1.0), C["ivory"], mask(0.2), mat=1)
        box(mb, (x - 1.45, y - 0.45, 1.0), (x + 1.45, y + 0.45, 1.07), C["trim_gold"], mask(0.2), mat=1)
        for i in range(3):
            mb.cyl(0.22, 0.6, (x - 1.0 + i, y - 0.9, 0.3), (0, 0, 0), C["steel_lt"], mask(0.2), mat=1, seg=8)
        # arm 3 (south-east): planters
        x, y, a = arm_centre(3)
        for i in range(2):
            box(mb, (x - 1.4 + i * 1.6, y - 0.6, 0.0), (x - 0.2 + i * 1.6, y + 0.6, 0.5), C["ivory"], mask(0.2), mat=1)
            box(mb, (x - 1.3 + i * 1.6, y - 0.5, 0.5), (x - 0.3 + i * 1.6, y + 0.5, 1.1), C["leaf"], mask(0.1), mat=1)
        # arm 4 (south-west): benches and a screen wall
        x, y, a = arm_centre(4)
        for i in range(2):
            box(mb, (x - 1.2, y - 0.8 + i * 1.3, 0.0), (x + 1.2, y - 0.3 + i * 1.3, 0.45), C["steel_lt"], mask(0.2), mat=1)
        x, y, a = arm_centre(4, 7.4)
        box(mb, (x - 1.2, y - 0.1, 0.4), (x + 1.2, y + 0.1, 1.9), C["navy"], mask(0.2), mat=1)
        box(mb, (x - 1.0, y + 0.1, 0.6), (x + 1.0, y + 0.12, 1.7), C["glass_lt"], mask(0.0, 0.8), mat=1)
        for px, py in ((-1.0, 3.0), (5.0, 3.0), (5.0, -3.0), (-1.0, -3.0)):   # lamp pads
            box(mb, (px - 0.35, py - 0.35, 0.0), (px + 0.35, py + 0.35, 0.03), C["amber"], mask(0.0, 0.7), mat=1)
    m.prop("plaza", plaza)
