"""Briefing room (canopy style, mockup 1000037500): a square glass-roofed hall under a
pyramid of struts, seat rows round a central column, a console in the corner.
Attach M-P (A, -X) . offers B (-Y / south), C (+Y / north), all M-P. Mount: mast (apex)."""
from kit import core
from kit.module import C, box, mask

ID = "briefing"
LAYOUT = """\
##cc##
#....#
a.##.#
a.##.#
#...C#
##bb##"""
SEED = 53

HALF = 4.3                        # room x/y -4..4 + 0.3 walls
PLAN = core.regular_polygon(4, HALF)
Z1 = 5.2


def build(m):
    hull = m.canopy_polygon(PLAN, z1=Z1, kt=2.2, spokes=True)
    for letter in "ABC":
        m.port(letter, [hull], face=0.3, plate=2.0)
    spots = [((x, -HALF, 0.55), (0, -1, 0)) for x in (-3.0, 3.0)]
    spots += [((HALF, y, 0.55), (1, 0, 0)) for y in (-2.5, 0.0, 2.5)]
    m.porthole_at(spots)

    m.light("west", -2.0, 0.0)
    m.light("east", 2.0, 0.0)
    m.mount("mast", (0.0, 0.0, Z1 + 0.01))
    m.cut_box(-HALF, HALF, -HALF, HALF, 7.0)

    def seats(mb):  # central column, four seat rows facing out, deck plate under the block
        box(mb, (-2.0, -2.0, -0.2), (2.0, 2.0, 0.0), C["deck"], mask(0.1), mat=1)
        mb.cyl(0.35, 2.6, (0, 0, 1.3), (0, 0, 0), C["ivory"], mask(0.2), mat=1, seg=8)
        mb.cyl(0.5, 0.25, (0, 0, 2.7), (0, 0, 0), C["trim_gold"], mask(0.2), mat=1, seg=8)
        for sx, sy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            for k in (-1, 1):
                if sx:
                    x = sx * 1.4
                    box(mb, (x - 0.3, k * 0.9 - 0.7, 0.0), (x + 0.3, k * 0.9 + 0.7, 0.45), C["ivory"], mask(0.2), mat=1)
                    box(mb, (x + sx * 0.2 - 0.08, k * 0.9 - 0.7, 0.45), (x + sx * 0.2 + 0.08, k * 0.9 + 0.7, 1.0),
                        C["ivory"], mask(0.2), mat=1)
                else:
                    y = sy * 1.4
                    box(mb, (k * 0.9 - 0.7, y - 0.3, 0.0), (k * 0.9 + 0.7, y + 0.3, 0.45), C["ivory"], mask(0.2), mat=1)
                    box(mb, (k * 0.9 - 0.7, y + sy * 0.2 - 0.08, 0.45), (k * 0.9 + 0.7, y + sy * 0.2 + 0.08, 1.0),
                        C["ivory"], mask(0.2), mat=1)
        for x, y in ((-3.0, 3.0), (3.0, 3.0), (-3.0, -3.0)):   # lamp pads in the free corners
            box(mb, (x - 0.35, y - 0.35, 0.0), (x + 0.35, y + 0.35, 0.03), C["amber"], mask(0.0, 0.7), mat=1)
    m.prop("seats", seats)
