"""Storage module (canopy style, the tubes of mockups 1000037494-96): the canopy tube
stacked with crates under glowing amber lids, a pass-through to the next module.
Attach M-P (A, -X end) . offers B (+X end, M-P). Mount: crane (roof). Decorative
storage for now (no storage mechanic yet)."""
from kit.module import C, box, mask

ID = "storage"
LAYOUT = """\
##########
#.##.##..#
a........b
a........b
#..##.##.#
##########"""
SEED = 79

X0, X1 = -8.0, 8.0
Y1 = 4.3
Z1 = 3.4
NOSE = 1.0
STACKS = [(-4.0, 3.0), (2.0, 3.0), (-2.0, -3.0), (4.0, -3.0)]


def build(m):
    hull = m.canopy_tube(X0, X1, Y1, z1=Z1, nose=(NOSE, NOSE), squeeze=(0.72, 0.92),
                         ribs=(-8 / 3, 8 / 3))

    def outside(mb):
        for sy in (1, -1):
            y = sy * (Y1 + 0.03)
            for x in (-6.0, -1.0, 4.5):
                box(mb, (x - 0.45, y - 0.04, 0.05), (x + 0.45, y + 0.04, 0.8), C["navy"], mask(0.2))
            box(mb, (0.6, y - 0.04, 0.6), (2.6, y + 0.04, 0.7), C["cyan"], mask(0.0, 1.0))
            box(mb, (-7.5, y - 0.04, -0.2), (-6.5, y + 0.04, -0.1), C["amber"], mask(0.0, 1.0))
    m.piece(outside, massing=False, name="_outside")
    m.port("A", [hull], face=NOSE)
    m.port("B", [hull], face=NOSE)

    m.light("west", -4.0, 0.0)
    m.light("east", 4.0, 0.0)
    m.mount("crane", (0.0, 0.0, Z1 + 0.01))
    m.cut_box(X0, X1, -Y1 - 0.6, Y1 + 0.6, 7.0)

    rng = m.rng

    def crates(mb):  # blue-grey crates with glowing lids on the blocked cell pairs
        for x, y in STACKS:
            sy = 1 if y > 0 else -1
            box(mb, (x - 2.0, sy * 2.0, -0.2), (x + 2.0, sy * 4.0, 0.0), C["deck"], mask(0.1), mat=1)
            for dx in (-0.95, 0.95):
                h = rng.choice((1.1, 1.5, 1.9))
                box(mb, (x + dx - 0.8, y - 0.8, 0.0), (x + dx + 0.8, y + 0.8, h), C["steel_lt"], mask(0.3), mat=1)
                box(mb, (x + dx - 0.6, y - 0.6, h), (x + dx + 0.6, y + 0.6, h + 0.04), C["amber"],
                    mask(0.0, 0.8), mat=1)
        # a strip of loose crates by the far wall
        for x in (6.0, 7.0):
            box(mb, (x - 0.4, 3.0, 0.0), (x + 0.4, 3.8, 0.8), C["steel_lt"], mask(0.3), mat=1)
            box(mb, (x - 0.3, 3.1, 0.8), (x + 0.3, 3.7, 0.83), C["amber"], mask(0.0, 0.8), mat=1)
    m.prop("crates", crates)
