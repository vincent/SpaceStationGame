"""Commons (canopy style, mockup 1000037490): the canopy tube with a faceted ivory dome
over its middle bay and a lit lantern on top, lounge benches along both walls.
Attach M-P (A, -X end) . offers B (+X end, M-P). Mount: lantern (dome top)."""
import math

from kit import core
from kit.module import C, box, mask

ID = "commons"
LAYOUT = """\
##########
#.##..##.#
a........b
a........b
#.##..##.#
##########"""
SEED = 83

X0, X1 = -8.0, 8.0
Y1 = 4.3
Z1 = 3.4
NOSE = 1.0
DOME = core.regular_polygon(8, 3.6)          # sits on the canopy shoulders, above head height
DOME_STEPS = [(0.0, 2.7), (0.0, 3.7), (0.8, 4.6), (1.8, 5.3), (2.8, 5.6)]


def build(m):
    hull = m.canopy_tube(X0, X1, Y1, z1=Z1, nose=(NOSE, NOSE), squeeze=(0.72, 0.92),
                         ribs=(-8 / 3, 8 / 3))

    def dome(mb):  # opaque panels in two tones, gold base ring
        faces = core.polygon_hull(mb, DOME, DOME_STEPS)
        for f in faces:
            c = f.calc_center_median()
            k = round(math.degrees(math.atan2(c.y, c.x)) / 45)
            core.paint(mb, [f], C["ivory" if k % 2 else "white"], mask(0.15))
        band = core.polygon_band(mb, DOME, 3.5, 3.75, grow=0.08)
        core.paint(mb, band, C["trim_gold"], mask(0.3))
    m.piece(dome, thick=0.3, massing=False, name="_dome")

    def lantern(mb):
        top = DOME_STEPS[-1][1]
        mb.cyl(0.9, 0.45, (0, 0, top + 0.12), (0, 0, 0), C["navy"], mask(0.3), seg=8)
        mb.cyl(0.7, 0.6, (0, 0, top + 0.6), (0, 0, 0), C["amber"], mask(0.0, 1.0), seg=8)
        mb.cyl(0.75, 0.6, (0, 0, top + 1.15), (0, 0, 0), C["white"], mask(0.2), r2=0.1, seg=8)
        for a in range(0, 360, 90):   # warm windows round the dome foot
            r = math.radians(a + 22.5)
            out = (math.cos(r), math.sin(r))
            p = (3.58 * out[0], 3.58 * out[1])
            box(mb, (p[0] - 0.3, p[1] - 0.3, 3.85), (p[0] + 0.3, p[1] + 0.3, 4.3), C["amber"], mask(0.0, 1.0))
    m.piece(lantern, massing=False, name="_lantern")

    def outside(mb):
        for sy in (1, -1):
            y = sy * (Y1 + 0.03)
            box(mb, (-7.0, y - 0.04, 0.1), (-2.5, y + 0.04, 0.2), C["navy"], mask(0.2))
            box(mb, (2.5, y - 0.04, 0.1), (7.0, y + 0.04, 0.2), C["navy"], mask(0.2))
            for x in (-5.0, 5.0):
                box(mb, (x - 0.5, y - 0.04, 0.35), (x + 0.5, y + 0.04, 0.85), C["navy"], mask(0.2))
            box(mb, (4.5, y - 0.04, -0.2), (5.5, y + 0.04, -0.1), C["amber"], mask(0.0, 1.0))
    m.piece(outside, massing=False, name="_outside")
    m.port("A", [hull], face=NOSE)
    m.port("B", [hull], face=NOSE)

    m.light("west", -4.0, 0.0)
    m.light("east", 4.0, 0.0)
    m.mount("lantern", (0.0, 0.0, DOME_STEPS[-1][1] + 1.36))
    m.cut_box(X0, X1, -Y1 - 0.6, Y1 + 0.6, 8.0)

    def lounge(mb):  # benches with navy cushions on the blocked cell pairs, a low table
        for x in (-4.0, 4.0):
            for sy in (1, -1):
                box(mb, (x - 2.0, sy * 2.0, -0.2), (x + 2.0, sy * 4.0, 0.0), C["deck"], mask(0.1), mat=1)
                box(mb, (x - 1.8, sy * 2.6, 0.0), (x + 1.8, sy * 3.8, 0.45), C["ivory"], mask(0.2), mat=1)
                box(mb, (x - 1.7, sy * 2.7, 0.45), (x + 1.7, sy * 3.7, 0.6), C["navy"], mask(0.1), mat=1)
                box(mb, (x - 1.8, sy * 3.65, 0.45), (x + 1.8, sy * 3.9, 1.1), C["ivory"], mask(0.2), mat=1)
                box(mb, (x - 0.5, sy * 2.15, 0.0), (x + 0.5, sy * 2.45, 0.4), C["trim_gold"], mask(0.2), mat=1)
    m.prop("lounge", lounge)
