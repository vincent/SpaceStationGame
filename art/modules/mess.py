"""Mess hall (canopy style, mockup 1000037499): a wedge-shaped glass-roofed canteen
(a right triangle with its tips cut off), counters along the long glass side, tables
and stools. Attach M-P (A, -X) . offers B (+X), M-P. Mount: vent."""
from kit.module import C, box, mask

ID = "mess"
LAYOUT = """\
######
#...K#
a.#..#
a....b
#..#.b
######"""
SEED = 61

W = 4.3                           # room x/y -4..4 + 0.3 walls (left and bottom legs)
T = 6.3                           # the cut tips: +X flat (door B) and +Y flat
HYP = 8.5                         # long glass side: x + y = HYP
PLAN = [(-W, -W), (T, -W), (T, HYP - T), (HYP - T, T), (-W, T)]
Z1 = 3.6


def build(m):
    hull = m.canopy_polygon(PLAN, z1=Z1, kt=1.3)
    m.port("A", [hull], face=0.3, plate=2.0)
    m.port("B", [hull], face=T - 4.0, plate=2.0)
    spots = [((x, -W, 0.55), (0, -1, 0)) for x in (-2.5, 0.5, 3.5)]
    spots += [((-W, y, 0.55), (-1, 0, 0)) for y in (3.0, -3.0)]
    m.porthole_at(spots)

    m.light("west", -2.0, 0.0)
    m.light("east", 2.0, 1.0)
    m.mount("vent", (1.0, 1.0, Z1 + 0.01))
    m.cut_box(-W, T, -W, T, 7.0)

    def canteen(mb):
        def table(x, y, top):   # on a blocked cell: deck plate, table, four stools
            box(mb, (x - 1.0, y - 1.0, -0.2), (x + 1.0, y + 1.0, 0.0), C["deck"], mask(0.1), mat=1)
            box(mb, (x - 0.08, y - 0.08, 0.0), (x + 0.08, y + 0.08, 0.75), C["navy"], mask(0.2), mat=1)
            box(mb, (x - 0.7, y - 0.45, 0.75), (x + 0.7, y + 0.45, 0.82), C[top], mask(0.2), mat=1)
            for dx, dy, col in ((-0.55, 0.75, "red"), (0.55, 0.75, "mint"), (-0.55, -0.75, "trim_gold"),
                                (0.55, -0.75, "steel_lt")):
                mb.cyl(0.2, 0.45, (x + dx, y + dy, 0.22), (0, 0, 0), C[col], mask(0.2), mat=1, seg=8)
        table(-1.0, 1.0, "red")       # '#' at col 2 row 2
        table(1.0, -3.0, "cyan")      # '#' at col 3 row 4
        # counters along the hypotenuse, outside the room square
        for x, y in ((5.0, 0.0), (3.4, 4.6), (5.3, -2.6)):
            box(mb, (x - 0.6, y - 0.6, 0.0), (x + 0.6, y + 0.6, 0.9), C["ivory"], mask(0.2), mat=1)
            box(mb, (x - 0.65, y - 0.65, 0.9), (x + 0.65, y + 0.65, 0.97), C["trim_gold"], mask(0.2), mat=1)
        mb.cyl(0.5, 1.3, (4.6, 2.6, 0.65), (0, 0, 0), C["crate"], mask(0.2), mat=1, seg=8)   # urn
    m.prop("canteen", canteen)
