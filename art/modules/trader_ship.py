"""Trader ship (canopy style, visitor): a narrow merchant hauler, navy walls under a
glass roof, gold stripe, two ivory cargo pods slung on its flanks. Docks by its hatch
A (+X end). Parts (always there): engine (twin bells aft), mast (beacon, pennant)."""
from kit import core
from kit.module import C, box, mask

ID = "trader_ship"
LAYOUT = """\
#####
#T..a
#####"""
SEED = 53
BUDGET = 6000

HX, HY = 3.3, 1.3                 # hold x -3..3, y -1..1 + 0.3 walls
Z1 = 3.0
REAR = 1.4                        # chamfered stern beyond -X
POD_Y = HY + 1.0


def build(m):
    hull = m.canopy_tube(-HX, HX, HY, z1=Z1, kt=0.8, kb=0.4, nose=(REAR, 0.0), squeeze=(0.6, 0.75),
                         wall="navy", strut=0.16)
    m.doorway("A", hull)
    for sy in (1, -1):            # cargo pods: closed, opaque
        m.canopy_tube(-2.6, 2.2, 0.75, z1=1.7, kt=0.4, kb=0.3, nose=(0.6, 0.5), squeeze=(0.6, 0.7),
                      glass="navy", frame=False, wall="ivory", at=(0.0, sy * POD_Y, 0.15))
    m.porthole_at([((x, sy * HY, 0.45), (0, sy, 0)) for x in (-1.2, 1.2) for sy in (1, -1)], r=0.24)

    def pylons(mb):  # struts holding the pods, nav lights at the bow
        for sy in (1, -1):
            for x in (-1.6, 1.2):
                core.beam(mb, (x, sy * (HY - 0.1), 0.5), (x, sy * (POD_Y - 0.5), 0.6), 0.18, C["trim_gold"], mask(0.3))
            box(mb, (HX - 0.15, sy * (HY - 0.2) - 0.1, 1.6), (HX + 0.08, sy * (HY - 0.2) + 0.1, 1.8),
                C["mint" if sy > 0 else "pink"], mask(0.0, 1.0))
    m.piece(pylons, massing=False, name="_pylons")

    def engine(mb):
        x = -HX - REAR
        box(mb, (x - 0.3, -0.9, 0.0), (x + 0.4, 0.9, 1.6), C["steel"], mask(0.3))
        for y in (-0.5, 0.5):
            mb.cyl(0.35, 0.9, (x - 0.65, y, 0.8), (0, 90, 0), C["steel_lt"], mask(0.3), r2=0.55, seg=8)
            mb.cyl(0.3, 0.05, (x - 1.08, y, 0.8), (0, 90, 0), C["amber"], mask(0.0, 1.0), seg=8)
    m.part("engine", engine)

    def mast(mb):
        mb.cyl(0.06, 2.0, (-2.0, 0.0, Z1 + 1.0), (0, 0, 0), C["strut"], mask(0.2), seg=6)
        mb.cyl(0.15, 0.2, (-2.0, 0.0, Z1 + 2.05), (0, 0, 0), C["amber"], mask(0.0, 1.0), seg=8)
        box(mb, (-1.95, -0.02, Z1 + 1.3), (-1.0, 0.02, Z1 + 1.85), C["trim_gold"], mask(0.2))
    m.part("mast", mast)

    m.light("hold", 0.0, 0.0)
    m.cut_box(-HX, HX, -HY - 0.3, HY + 0.3, 6.0)

    def hold(mb):  # crates and a rug
        box(mb, (-0.8, -0.6, 0.0), (1.4, 0.6, 0.03), C["violet"], mask(0.1), mat=1)
        for x, y, s in ((2.4, 0.65, 0.3), (2.4, -0.65, 0.25), (0.6, 0.7, 0.22)):
            box(mb, (x - s, y - s, 0.0), (x + s, y + s, 2 * s), C["crate"], mask(0.3), mat=1)
    m.prop("hold", hold)
