"""Workshop (canopy style, mockup 1000037497): the canopy tube lined with workbenches,
tool boards and button consoles, portholes along the side. Attach M-P (A, -X end) .
offers B (+X end, M-P). Mount: crane (roof)."""
from kit.module import C, box, mask

ID = "workshop"
LAYOUT = """\
##########
#.##.##.C#
a........b
a........b
#.##.##..#
##########"""
SEED = 71

X0, X1 = -8.0, 8.0
Y1 = 4.3
Z1 = 3.4
NOSE = 1.0
BENCHES = [(x, y) for x in (-4.0, 2.0) for y in (3.0, -3.0)]   # on the "#" cell pairs


def build(m):
    hull = m.canopy_tube(X0, X1, Y1, z1=Z1, nose=(NOSE, NOSE), squeeze=(0.72, 0.92),
                         ribs=(-8 / 3, 8 / 3))
    m.portholes((-6.0, -3.0, 0.0, 3.0, 6.0), Y1, sides=(-1,))

    def belly(mb):
        for sy in (1, -1):
            for x in (-7.0, 6.5):
                y = sy * (Y1 + 0.03)
                box(mb, (x - 0.5, y - 0.04, -0.2), (x + 0.5, y + 0.04, -0.1), C["amber"], mask(0.0, 1.0))
    m.piece(belly, massing=False, name="_belly")
    m.port("A", [hull], face=NOSE)
    m.port("B", [hull], face=NOSE)

    m.light("west", -4.0, 0.0)
    m.light("east", 4.0, 0.0)
    m.mount("crane", (0.0, 0.0, Z1 + 0.01))
    m.cut_box(X0, X1, -Y1 - 0.6, Y1 + 0.6, 7.0)

    def benches(mb):
        for x, y in BENCHES:
            sy = 1 if y > 0 else -1
            box(mb, (x - 2.0, sy * 2.0, -0.2), (x + 2.0, sy * 4.0, 0.0), C["deck"], mask(0.1), mat=1)
            box(mb, (x - 1.8, y - 0.6, 0.0), (x + 1.8, y + 0.6, 0.9), C["steel_lt"], mask(0.2), mat=1)
            box(mb, (x - 1.85, y - 0.65, 0.9), (x + 1.85, y + 0.65, 0.98), C["ivory"], mask(0.2), mat=1)
            box(mb, (x - 1.8, sy * 3.85, 0.98), (x + 1.8, sy * 3.95, 2.0), C["navy"], mask(0.2), mat=1)  # tool board
            box(mb, (x - 0.9, y - 0.3, 0.98), (x - 0.1, y + 0.3, 1.04), C["crate"], mask(0.2), mat=1)
            box(mb, (x + 0.5, y - 0.35, 0.98), (x + 1.5, y + 0.35, 1.08), C["cream"], mask(0.0, 0.5), mat=1)
            for i, col in enumerate(("red", "mint", "red")):    # button row
                mb.cyl(0.09, 0.06, (x - 1.4 + i * 0.25, y, 1.01), (0, 0, 0), C[col], mask(0.0, 0.8), mat=1, seg=8)
    m.prop("benches", benches)
