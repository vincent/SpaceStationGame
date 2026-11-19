"""Dormitory (canopy style, mockup 1000037491): the greenhouse tube fitted with bunk
beds along both walls and a row of amber portholes. Attach M-P (A, -X end) . offers
B (+X end, M-P). Mount: antenna (roof). Six crew bunks (B cells)."""
from kit.module import C, box, mask

ID = "dorm"
LAYOUT = """\
##########
#.B.B.B.C#
a........b
a........b
#.B.B.B..#
##########"""
SEED = 37

X0, X1 = -8.0, 8.0
Y1 = 4.3
Z1 = 3.4
NOSE = 1.0
BUNKS = (-4.0, 0.0, 4.0)          # x of the B cells, rows y = +-3


def build(m):
    hull = m.canopy_tube(X0, X1, Y1, z1=Z1, nose=(NOSE, NOSE), squeeze=(0.72, 0.92),
                         ribs=(-8 / 3, 8 / 3))
    m.portholes((-6.0, -3.0, 0.0, 3.0, 6.0), Y1)

    def belly(mb):  # warm light strips under the wall
        for sy in (1, -1):
            for x in (-7.0, 6.5):
                y = sy * (Y1 + 0.03)
                box(mb, (x - 0.5, y - 0.04, -0.2), (x + 0.5, y + 0.04, -0.1), C["amber"], mask(0.0, 1.0))
    m.piece(belly, massing=False, name="_belly")

    m.port("A", [hull], face=NOSE)
    m.port("B", [hull], face=NOSE)

    m.light("west", -4.0, 0.0)
    m.light("east", 4.0, 0.0)
    m.mount("antenna", (5.0, 2.0, Z1 + 0.01))
    m.cut_box(X0, X1, -Y1 - 0.6, Y1 + 0.6, 7.0)

    def bunks(mb):  # upper bunk over each bed: navy posts, slatted frame, mattress
        for x in BUNKS:
            for y in (3.0, -3.0):
                for dx in (-0.85, 0.85):
                    for dy in (-0.85, 0.85):
                        box(mb, (x + dx - 0.05, y + dy - 0.05, 0.0), (x + dx + 0.05, y + dy + 0.05, 2.0),
                            C["navy"], mask(0.2), mat=1)
                box(mb, (x - 0.9, y - 0.9, 1.35), (x + 0.9, y + 0.9, 1.45), C["ivory"], mask(0.2), mat=1)
                box(mb, (x - 0.8, y - 0.8, 1.45), (x + 0.8, y + 0.8, 1.6), C["deck"], mask(0.1), mat=1)
                box(mb, (x - 0.75, y + (0.35 if y > 0 else -0.75), 1.6),
                    (x + 0.75, y + (0.75 if y > 0 else -0.35), 1.66), C["cream"], mask(0.1), mat=1)
        # lockers along the far wall ends
        for x in (-6.9, 6.9):
            box(mb, (x - 0.45, 3.3, 0.0), (x + 0.45, 3.95, 1.9), C["ivory"], mask(0.2), mat=1)
            box(mb, (x - 0.4, 3.28, 1.5), (x + 0.4, 3.3, 1.7), C["navy"], mask(0.2), mat=1)
    m.prop("bunks", bunks)
