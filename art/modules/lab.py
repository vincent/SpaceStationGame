"""Lab (canopy style, mockup 1000037498): the canopy tube round a glowing holo table,
analysers and screens along the walls, cyan light strips. Attach M-P (A, -X end) .
offers B (+X end, M-P). Mount: dish (roof)."""
from kit.module import C, box, mask

ID = "lab"
LAYOUT = """\
##########
###....###
a...##...b
a...##...b
###.C..###
##########"""
SEED = 73

X0, X1 = -8.0, 8.0
Y1 = 4.3
Z1 = 3.4
NOSE = 1.0


def build(m):
    hull = m.canopy_tube(X0, X1, Y1, z1=Z1, nose=(NOSE, NOSE), squeeze=(0.72, 0.92),
                         ribs=(-8 / 3, 8 / 3))

    def outside(mb):
        for sy in (1, -1):
            y = sy * (Y1 + 0.03)
            for x in (-5.5, 1.5, 5.5):
                box(mb, (x - 0.4, y - 0.04, 0.05), (x + 0.4, y + 0.04, 0.75), C["navy"], mask(0.2))
            box(mb, (-3.5, y - 0.04, 0.35), (0.5, y + 0.04, 0.45), C["cyan"], mask(0.0, 1.0))
            for x in (-7.0, 6.5):
                box(mb, (x - 0.5, y - 0.04, -0.2), (x + 0.5, y + 0.04, -0.1), C["cyan"], mask(0.0, 1.0))
    m.piece(outside, massing=False, name="_outside")
    m.port("A", [hull], face=NOSE)
    m.port("B", [hull], face=NOSE)

    m.light("west", -4.0, 0.0)
    m.light("east", 4.0, 0.0)
    m.mount("dish", (4.0, 1.5, Z1 + 0.01))
    m.cut_box(X0, X1, -Y1 - 0.6, Y1 + 0.6, 7.0)

    def lab(mb):
        # holo table on the centre block: gold base, cyan glowing cone
        box(mb, (-2.0, -2.0, -0.2), (2.0, 2.0, 0.0), C["deck"], mask(0.1), mat=1)
        mb.cyl(1.2, 0.35, (0, 0, 0.17), (0, 0, 0), C["trim_gold"], mask(0.2), mat=1, seg=8)
        mb.cyl(0.95, 1.1, (0, 0, 0.9), (0, 0, 0), C["cyan"], mask(0.0, 0.9), mat=1, r2=0.3, seg=8)
        box(mb, (-0.5, -0.4, 1.5), (0.5, 0.4, 1.53), C["white"], mask(0.0, 0.6), mat=1)
        # analysers on the wall blocks, screens above them
        for x in (-6.0, 6.0):        # the "#" cell pairs at both ends
            for sy in (1, -1):
                box(mb, (x - 2.0, sy * 2.0, -0.2), (x + 2.0, sy * 4.0, 0.0), C["deck"], mask(0.1), mat=1)
                box(mb, (x - 1.7, sy * 2.5, 0.0), (x + 1.7, sy * 3.9, 1.0), C["steel_lt"], mask(0.2), mat=1)
                box(mb, (x - 1.0, sy * 3.85, 1.2), (x + 1.0, sy * 3.95, 2.1), C["cyan"], mask(0.0, 0.8), mat=1)
                mb.cyl(0.2, 0.3, (x - 1.0, sy * 3.0, 1.15), (0, 0, 0), C["glass_lt"], mask(0.0, 0.5), mat=1, seg=8)
                mb.cyl(0.6, 0.06, (x + 0.8, sy * 3.1, 1.5), (0, 0, 0), C["glass_lt"], mask(0.1), mat=1, seg=8)
                box(mb, (x + 0.76, sy * 3.1 - 0.04, 1.0), (x + 0.84, sy * 3.1 + 0.04, 1.5), C["navy"], mask(0.2), mat=1)
    m.prop("lab", lab)
