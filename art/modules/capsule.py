"""Rescue capsule (canopy shapes, its own livery): the castaway's pod, a squat faceted
tube with red walls under an opaque offwhite roof, an offwhite stripe, amber
portholes and a chamfered engine nose. Docks to the wreck by its port A (-X end, the
double doorway). Parts: antenna, thruster, solar_wings (capsule_* upgrades)."""
from kit import core
from kit.module import C, box, mask

ID = "capsule"
LAYOUT = """\
#####
aP.B#
a..K#
#####"""
SEED = 3
BUDGET = 6000

HX, HY = 3.3, 2.3                 # room x -3..3, y -2..2 + 0.3 walls
Z1 = 3.2
NOSE = 1.4                        # chamfered engine nose beyond +X
LIVERY = dict(wall="red", stripe="offwhite", glass="offwhite", frame=False)


def build(m):
    hull = m.canopy_tube(-HX, HX, HY, z1=Z1, kt=1.1, nose=(0.0, NOSE), squeeze=(0.62, 0.78),
                         ribs=(0.0,), **LIVERY)
    m.port("A", [hull], face=0.3, plate=2.0)
    m.porthole_at([((x, sy * HY, 0.55), (0, sy, 0)) for x in (-1.0, 1.0) for sy in (1, -1)], r=0.3)

    def trim(mb):  # roof window band, RCS blocks, ribs, hull name
        for sy in (1, -1):
            y = sy * (HY - 0.62)
            box(mb, (-2.6, y - 0.32, Z1 - 0.69), (2.2, y + 0.32, Z1 - 0.62), C["glass_lt"], mask(0.0, 0.25))
            for x in (-HX + 0.4, HX - 0.3):
                box(mb, (x - 0.25, sy * (HY - 0.05), 1.3), (x + 0.25, sy * (HY + 0.25), 1.75), C["offwhite"], mask(0.3))
                box(mb, (x - 0.08, sy * (HY + 0.25), 1.43), (x + 0.08, sy * (HY + 0.35), 1.62), C["anthracite"], mask(0.3))
        for x in (-HX + 0.15, 0.0):          # rib bands on the outer side walls
            for sy in (1, -1):
                box(mb, (x - 0.12, sy * (HY - 0.05), -0.15), (x + 0.12, sy * (HY + 0.07), 1.15), C["offwhite"],
                    mask(0.3))
    m.piece(trim, massing=False, name="_trim")
    # hull name (font meshes are not watertight: not part of the hull)
    m.frame(lambda mb: mb.text("SR-7", 0.55, (-2.2, -HY - 0.08, 0.55), (90, 0, 0), C["offwhite"], mask(0.2)))

    def antenna(mb):
        mb.cyl(0.06, 1.6, (1.2, -0.7, Z1 + 0.8), (0, 0, 0), C["offwhite"], mask(0.2), seg=6)
        mb.cyl(0.45, 0.15, (1.2, -0.7, Z1 + 1.6), (30, 0, -30), C["offwhite"], mask(0.2), r2=0.1, seg=10)
        mb.cyl(0.08, 0.08, (1.2, -0.7, Z1 + 1.65), (0, 0, 0), C["amber"], mask(0.0, 1.0), seg=6)
    m.part("antenna", antenna)

    def thruster(mb):  # engine bell on the nose
        x = HX + NOSE
        mb.cyl(0.45, 0.4, (x + 0.15, 0, 0.9), (0, 90, 0), C["anthracite"], mask(0.3), seg=8)
        mb.cyl(0.5, 1.0, (x + 0.8, 0, 0.9), (0, 90, 0), C["steel"], mask(0.3), r2=0.8, seg=10)
        core.prism_ring(mb, (x + 1.25, 0, 0.9), (1, 0, 0), 0.9, 0.75, 0.1, C["red"], mask(0.3))
    m.part("thruster", thruster)

    def wings(mb):  # small solar wings off both side walls
        for sy in (1, -1):
            y0, y1 = sorted((sy * (HY + 0.1), sy * (HY + 3.6)))
            core.beam(mb, (0.0, y0, 1.7), (0.0, y1, 1.7), 0.12, C["offwhite"], mask(0.3))
            box(mb, (-1.4, sy * (HY + 0.6) if sy > 0 else y0, 1.66),
                (1.4, y1 if sy > 0 else sy * (HY + 0.6), 1.72), C["solar"], mask(0.05, 0.0, 1.0))
            for x in (-1.4, 1.4):
                box(mb, (x - 0.05, min(y0, y1), 1.64), (x + 0.05, max(y0, y1), 1.74), C["offwhite"], mask(0.3))
    m.part("solar_wings", wings)

    m.light("cabin", 0.0, 0.0)
    m.cut_box(-HX, HX + NOSE, -HY - 0.6, HY + 0.6, 6.0)

    def cabin(mb):  # wall screen, ration shelf, first-aid box
        box(mb, (-1.3, HY - 0.36, 1.0), (0.3, HY - 0.3, 1.8), C["anthracite"], mask(0.2), mat=1)
        box(mb, (-1.2, HY - 0.37, 1.1), (0.2, HY - 0.36, 1.7), C["cyan"], mask(0.0, 0.8), mat=1)
        box(mb, (-0.4, -HY + 0.3, 0.9), (0.9, -HY + 0.6, 0.98), C["offwhite"], mask(0.2), mat=1)
        for x in (-0.25, 0.15, 0.55):
            box(mb, (x - 0.12, -HY + 0.35, 0.98), (x + 0.12, -HY + 0.55, 1.25), C["amber"], mask(0.1), mat=1)
        box(mb, (-2.4, -HY + 0.3, 1.2), (-1.9, -HY + 0.45, 1.6), C["offwhite"], mask(0.2), mat=1)
        box(mb, (-2.2, -HY + 0.45, 1.33), (-2.1, -HY + 0.46, 1.47), C["red"], mask(0.2), mat=1)
    m.prop("cabin", cabin)
