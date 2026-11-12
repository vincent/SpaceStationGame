"""Habitat Drum (Skylab / TransHab): a fat inflated drum, quilted fabric skin, a band
of small portholes. Attach M-P (A, -X end) . offers B (+X end, M-P).
Mounts: antenna, radiator (upgrades). Inside: bunks, galley, console, hygiene."""
import math

from kit import core
from kit.module import C, box, mask

ID = "hab_drum"
LAYOUT = """\
#######
#B.K..#
a.....b
a.....b
#B...C#
#######"""
SEED = 23

X0, X1 = -5.3, 5.3                # room x -5..5 + 0.3 end walls
Y0, Y1 = -4.3, 4.3                # room y -4..4 + 0.3 walls
Z0, Z1 = -0.6, 5.2
RADII = (0.45, 2.6, 2.6, 0.45)        # tight floor corners: the 2 m floor cells reach the walls
CZ = (Z0 + Z1) / 2


def quilt(mb, faces):
    """Fabric skin: diamond-ish checker of two fabric tones, a seam every ring."""
    for f in faces:
        c = f.calc_center_median()
        if abs(c.x) > X1 - 0.05:      # flat end caps: plain
            core.paint(mb, [f], C["fabric"], mask(0.15, 0, 1))
            continue
        k = round(c.x / 1.06) + round(math.atan2(c.z - CZ, c.y) / 0.42)
        core.paint(mb, [f], C["fabric" if k % 2 else "fabric_dk"], mask(0.15, 0, 1))


def build(m):
    def body(mb):
        faces = core.rounded_hull(mb, X0, X1, Y0, Y1, Z0, Z1, RADII, step=1.06, seg=5)
        quilt(mb, faces)
    hull = m.piece(body, thick=0.3)

    def bands(mb):
        for x in (X0 + 0.3, X1 - 0.3):
            m.band(mb, x - 0.3, x + 0.3, Y0, Y1, Z0, Z1, RADII, color="colony_dk", grow=0.14)
        m.band(mb, -0.35, 0.35, Y0, Y1, Z0, Z1, RADII, color="colony", grow=0.1)
    rings = m.piece(bands, massing=False)

    def portholes(mb):  # glass discs proud of the skin; G mask = they glow when powered
        for sy in (1, -1):
            for x in (-4.0, -2.7, -1.4, 1.4, 2.7, 4.0):
                mb.cyl(0.32, 0.12, (x, sy * (Y1 + 0.02), 2.3), (90, 0, 0), C["glass_lt"], mask(0.05, 1.0), seg=12)
                mb.cyl(0.42, 0.08, (x, sy * (Y1 - 0.01), 2.3), (90, 0, 0), C["steel_lt"], mask(0.4), seg=12)
    m.piece(portholes, massing=False)

    m.doorway("A", [hull, rings], face=0.3)
    m.doorway("B", [hull, rings], face=0.3)

    m.light("bunks", -2.5, 0, 2.6)
    m.light("galley", 2.5, 0, 2.6)
    m.mount("antenna", (-2.6, 0.9, Z1 + 0.01))
    m.mount("radiator", (2.6, -0.9, Z1 + 0.01))
    m.cut_box(X0 - 0.3, X1 + 0.3, Y0 - 0.6, Y1 + 0.6, 7.0)

    # outside: a cable bundle and handrails over the top, stencils on the ends
    m.greeble("gk_cables", (0, 0, Z1), "+Z", 0, (8.5, 1, 1))
    for y in (-1.2, 1.2):
        m.pipe((X0 + 1.0, y, Z1 - 0.06), (X1 - 1.0, y, Z1 - 0.06), "+Z", kit="gk_pipe_thin")
    m.greeble("gk_vent", (0.0, 1.9, Z1 - 0.15), "+Z", 90)
    for x, face in ((X0, "-X"), (X1, "+X")):
        m.greeble("gk_hazard", (x, 0, 2.95), face, 0, (0.9, 1, 1))
        m.greeble("gk_panel_violet", (x, 2.3, 1.4), face, 0, (0.8, 1.6, 1))
        m.greeble("gk_panel_grey", (x, -2.3, 1.4), face, 0, (0.8, 1.6, 1))
    m.greeble("gk_stencil_SR7", (-3.4, -Y1, 3.4), "-Y")
    m.greeble("gk_stencil_14", (3.4, Y1, 3.4), "+Y")
    m.greeble("gk_tank", (-4.2, -2.8, 0.2), "-Y", 0, (0.8, 0.8, 0.8))

    # inside: hygiene cubicle in the galley corner, a rug between the bunks
    def hygiene(mb):
        box(mb, (3.25, 2.3, 0), (4.85, 3.9, 2.2), C["white"], mask(0.2), mat=1)
        box(mb, (3.6, 2.28, 0.15), (4.5, 2.3, 2.0), C["glass_lt"], mask(0.0, 0.4), mat=2)
        box(mb, (3.3, 2.35, 2.2), (4.8, 3.85, 2.3), C["colony_dk"], mask(0.3), mat=1)
    m.prop("hygiene", hygiene)

    def rug(mb):
        box(mb, (-4.2, -1.4, 0.0), (-2.2, 1.4, 0.02), C["violet"], mask(0.1), mat=1)
        box(mb, (-4.0, -1.2, 0.02), (-2.4, 1.2, 0.03), C["pink"], mask(0.1), mat=1)
    m.prop("rug", rug)
