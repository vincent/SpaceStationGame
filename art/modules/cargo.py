"""Cargo hold (canopy style, mockup 1000037502): a dead-end canopy tube with steel
shelving and crates, a vent grille on the closed end. Attach M-P (A, -X end), no other
slot. Mount: crane (roof). Storage is decorative for now (no storage mechanic yet)."""
from kit.module import C, box, mask

ID = "cargo"
LAYOUT = """\
##########
###.##.###
a........#
a........#
###.##.###
##########"""
SEED = 41

X0, X1 = -8.0, 8.0
Y1 = 4.3
Z1 = 3.4
NOSE = 1.0
RACKS = [(x, y) for x in (-6.0, 0.0, 6.0) for y in (3.1, -3.1)]   # on the "#" cells (blocked)


def build(m):
    hull = m.canopy_tube(X0, X1, Y1, z1=Z1, nose=(NOSE, NOSE), squeeze=(0.72, 0.92),
                         ribs=(-8 / 3, 8 / 3))

    def outside(mb):
        for sy in (1, -1):
            y = sy * (Y1 + 0.03)
            for x in (-5.5, -3.5, -1.5):   # dark hatch panels
                box(mb, (x - 0.4, y - 0.04, 0.05), (x + 0.4, y + 0.04, 0.75), C["navy"], mask(0.2))
            for x in (2.0, 6.5):           # warm strips at the wall foot
                box(mb, (x - 0.5, y - 0.04, -0.2), (x + 0.5, y + 0.04, -0.1), C["amber"], mask(0.0, 1.0))
            # vent grille: navy slats near the closed end
            for i in range(5):
                z = -0.05 + i * 0.2
                box(mb, (4.6, y - 0.05, z), (6.4, y + 0.05, z + 0.1), C["navy"], mask(0.3))
        # closed end: a navy service hatch on the nose cap
        box(mb, (X1 + NOSE - 0.05, -0.7, 0.2), (X1 + NOSE + 0.05, 0.7, 1.6), C["navy"], mask(0.3))
        box(mb, (X1 + NOSE, -0.5, 1.7), (X1 + NOSE + 0.08, 0.5, 1.8), C["amber"], mask(0.0, 1.0))
    m.piece(outside, massing=False, name="_outside")

    m.port("A", [hull], face=NOSE)

    m.light("west", -4.0, 0.0)
    m.light("east", 4.0, 0.0)
    m.mount("crane", (0.0, 0.0, Z1 + 0.01))
    m.cut_box(X0, X1, -Y1 - 0.6, Y1 + 0.6, 7.0)

    rng = m.rng

    def racks(mb):  # two-shelf steel racks against the walls, crates on them
        for x, y in RACKS:
            sy = 1 if y > 0 else -1
            box(mb, (x - 2.0, sy * 2.0, -0.2), (x + 2.0, sy * 4.0, 0.0), C["deck"], mask(0.1),
                mat=1)   # deck plate: blocked cells get no floor tile
            y0, y1 = (y - 0.75, y + 0.85) if y > 0 else (y - 0.85, y + 0.75)
            for dx in (-1.6, 1.6):
                for yy in (y0, y1):
                    box(mb, (x + dx - 0.05, yy - 0.05, 0.0), (x + dx + 0.05, yy + 0.05, 2.0),
                        C["navy"], mask(0.2), mat=1)
            for z in (0.15, 1.05):
                box(mb, (x - 1.65, y0, z), (x + 1.65, y1, z + 0.08), C["deck"], mask(0.2), mat=1)
                cx = x - 1.4
                while cx < x + 1.2:
                    w = rng.uniform(0.6, 0.95)
                    h = rng.uniform(0.4, 0.7)
                    col = C["crate" if rng.random() < 0.3 else "trim_gold"]
                    box(mb, (cx, y0 + 0.15, z + 0.08), (cx + w, y1 - 0.15, z + 0.08 + h), col, mask(0.3), mat=1)
                    box(mb, (cx + 0.1, y0 + 0.25, z + 0.08 + h), (cx + w - 0.1, y1 - 0.25, z + 0.1 + h),
                        C["cream"], mask(0.1), mat=1)
                    cx += w + 0.12
    m.prop("racks", racks)
