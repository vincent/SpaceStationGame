"""Power deck (canopy style, mockup 1000037493): a low faceted tube with an opaque
deck roof carrying battery pods and a caged reactor core, two solar wings off the
back. Attach M-P (A, -X end); the +X end is a closed intake. Makes power."""
from kit import core
from kit.module import C, box, mask

ID = "power_deck"
LAYOUT = """\
##########
#.##.##.C#
a........#
a........#
#.##.##..#
##########"""
SEED = 89

X0, X1 = -8.0, 8.0
Y1 = 4.3
Z1 = 3.0
NOSE = 1.0


def build(m):
    hull = m.canopy_tube(X0, X1, Y1, z1=Z1, kt=0.5, nose=(NOSE, NOSE), squeeze=(0.72, 0.92),
                         glass="deck", frame=False)

    def roof(mb):  # battery pods and the reactor cage on the deck (cut in room view)
        z = Z1
        for x in (-5.0, 4.6):
            mb.cyl(1.15, 3.2, (x, 0.6, z + 1.2), (0, 90, 0), C["white"], mask(0.2), seg=8)
            for dx in (-1.0, 0.0, 1.0):
                mb.cyl(1.2, 0.18, (x + dx, 0.6, z + 1.2), (0, 90, 0), C["navy"], mask(0.3), seg=8)
            box(mb, (x - 0.5, 0.0, z - 0.05), (x + 0.5, 1.2, z + 0.2), C["navy"], mask(0.3))
        plan = core.regular_polygon(8, 1.9)
        for i in range(8):     # cage: posts and two rings
            a, b = plan[i - 1], plan[i]
            core.beam(mb, (a[0], a[1], z), (a[0], a[1], z + 2.6), 0.16, C["strut"], mask(0.15))
            for h in (z + 0.3, z + 2.6):
                core.beam(mb, (a[0], a[1], h), (b[0], b[1], h), 0.16, C["strut"], mask(0.15))
        core.prism_ring(mb, (0, 0, z + 0.01), (0, 0, 1), 2.1, 0.01, 0.3, C["trim_gold"], mask(0.2))
        mb.cyl(1.0, 1.1, (0, 0, z + 0.85), (0, 0, 0), C["steel_lt"], mask(0.2), seg=8)
        mb.cyl(0.8, 0.25, (0, 0, z + 1.5), (0, 0, 0), C["cyan"], mask(0.0, 1.0), seg=8)
        mb.cyl(0.9, 0.5, (0, 0, z + 1.9), (0, 0, 0), C["steel_lt"], mask(0.2), seg=8)
        for x in (-0.9, 0.9):
            for y in (-0.9, 0.9):
                mb.cyl(0.1, 0.3, (x * 0.8, y * 0.8, z + 2.3), (0, 0, 0), C["trim_gold"], mask(0.2), seg=6)
    m.piece(roof, massing=False, name="_roof")

    def wings(mb):  # two solar wings on a mast off the back wall
        for x0 in (-6.5, 0.5):
            core.beam(mb, (x0 + 3.0, Y1, 1.6), (x0 + 3.0, Y1 + 1.2, 1.6), 0.25, C["steel_lt"], mask(0.2))
            box(mb, (x0, Y1 + 1.2, 1.5), (x0 + 6.0, Y1 + 6.2, 1.62), C["strut"], mask(0.2))
            box(mb, (x0 + 0.1, Y1 + 1.3, 1.62), (x0 + 5.9, Y1 + 6.1, 1.66), C["solar"], mask(0.1))
            for i in range(1, 6):
                box(mb, (x0 + 0.1, Y1 + 1.2 + i * 0.83, 1.66), (x0 + 5.9, Y1 + 1.24 + i * 0.83, 1.68),
                    C["trim_gold"], mask(0.1))
    m.piece(wings, name="_wings")

    def outside(mb):
        y = -(Y1 + 0.03)
        for x in (-4.5, -3.0, -1.5, 0.0):    # dark access panels
            box(mb, (x - 0.5, y - 0.04, 0.0), (x + 0.5, y + 0.04, 0.75), C["navy"], mask(0.2))
        for x0, x1 in ((-8.0, -7.2), (3.0, 6.0)):
            box(mb, (x0, y - 0.04, -0.2), (x1, y + 0.04, -0.12), C["cyan"], mask(0.0, 1.0))
        # closed intake on the +X nose
        box(mb, (X1 + NOSE - 0.05, -1.4, 0.0), (X1 + NOSE + 0.08, 1.4, 2.0), C["navy"], mask(0.3))
        box(mb, (X1 + NOSE + 0.02, -1.6, 2.0), (X1 + NOSE + 0.12, 1.6, 2.15), C["trim_gold"], mask(0.3))
    m.piece(outside, massing=False, name="_outside")
    m.port("A", [hull], face=NOSE)

    m.light("west", -4.0, 0.0)
    m.light("east", 4.0, 0.0)
    m.mount("wing", (0.0, -2.5, Z1 + 0.01))
    m.cut_box(X0, X1, -Y1 - 0.6, Y1 + 0.6, 7.0)

    def plant(mb):  # generator housings on the blocked cells
        for x in (-4.0, 2.0):
            for sy in (1, -1):
                box(mb, (x - 2.0, sy * 2.0, -0.2), (x + 2.0, sy * 4.0, 0.0), C["deck"], mask(0.1), mat=1)
                box(mb, (x - 1.7, sy * 2.3, 0.0), (x + 1.7, sy * 3.8, 1.5), C["steel_lt"], mask(0.3), mat=1)
                box(mb, (x - 1.2, sy * 2.28, 0.6), (x + 1.2, sy * 2.3, 1.2), C["cyan"], mask(0.0, 0.8), mat=1)
                mb.cyl(0.35, 1.6, (x, sy * 3.0, 0.8), (0, 90, 0), C["navy"], mask(0.2), mat=1, seg=8)
    m.prop("plant", plant)
