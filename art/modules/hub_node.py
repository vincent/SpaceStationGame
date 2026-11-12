"""Hub Node (ISS Unity/Harmony): a short stubby node with a hatch on every side.
Attach M-P (A, -X end) . offers B (+X end), C and D (side radial ports), all M-P.
Top face: mount_top (upgrade). Storage racks line the walls between the hatches."""
from kit.module import C, box, mask

ID = "hub_node"
LAYOUT = """\
##c##
a...b
a...b
##d##"""
SEED = 11

X0, X1 = -3.3, 3.3                # room x -3..3 + 0.3 end walls
Y0, Y1 = -2.3, 2.3                # room y -2..2 + 0.3 walls
Z0, Z1 = -0.6, 3.3
RADII = (0.45, 1.7, 1.7, 0.45)       # tight floor corners: the 2 m floor cells reach the walls
PORT = 0.35                       # radial ports stand out of the side walls


def build(m):
    def body(mb):
        m.rounded(mb, X0, X1, Y0, Y1, Z0, Z1, RADII, livery=("white", "colony"), split=1.1)
    hull = m.piece(body, thick=0.3)

    def bands(mb):
        for x in (X0 + 0.25, X1 - 0.25):
            m.band(mb, x - 0.2, x + 0.2, Y0, Y1, Z0, Z1, RADII, color="colony_dk")
    rings = m.piece(bands, massing=False)

    ports = []
    for sy in (1, -1):  # flat radial ports for the side hatches (closed boxes)
        def port(mb, sy=sy):
            box(mb, (-1.25, sy * 1.95, Z0 + 0.15), (1.25, sy * (2.0 + PORT), 2.95), C["white"], mask(0.2, 0, 1))
            box(mb, (-1.35, sy * 2.2, 2.95), (1.35, sy * (2.05 + PORT), 3.1), C["colony_dk"], mask(0.3))
        ports.append(m.piece(port))

    m.doorway("A", [hull, rings], face=0.3)
    m.doorway("B", [hull, rings], face=0.3)
    m.doorway("C", [hull, ports[0]], face=PORT)
    m.doorway("D", [hull, ports[1]], face=PORT)

    m.light("main", 0, 0, 2.4)
    m.mount("top", (0, 0, Z1 + 0.01))
    m.cut_box(X0 - 0.2, X1 + 0.2, Y0 - 0.6, Y1 + 0.6, 5.0)

    # outside: handrails and cable bundles along the top, vents and panels on the ends
    for y in (-0.75, 0.75):
        m.pipe((X0 + 0.6, y, Z1), (X1 - 0.6, y, Z1), "+Z", kit="gk_pipe_thin")
    m.greeble("gk_cables", (0, 0, Z1), "+Z", 0, (4.0, 1, 1))
    m.greeble("gk_vent", (-1.9, 0, Z1), "+Z", 90)
    m.greeble("gk_panel_violet", (1.9, 0, Z1), "+Z", 0, (0.9, 0.9, 1))
    for x, face in ((X0, "-X"), (X1, "+X")):
        m.greeble("gk_panel_grey", (x, 1.55, 1.2), face, 0, (0.7, 1.2, 1))
        m.greeble("gk_panel_grey", (x, -1.55, 1.2), face, 0, (0.7, 1.2, 1))
        m.greeble("gk_hazard", (x, 0, 2.95), face, 0, (0.9, 1, 1))
    for sy, face in ((1, "+Y"), (-1, "-Y")):
        m.greeble("gk_stencil_" + ("C3" if sy > 0 else "B2"), (1.8, sy * Y1, 1.3), face)
        m.greeble("gk_bolts", (-1.9, sy * Y1, 1.0), face, 0, (1.2, 1, 1))

    # inside: storage racks against the side walls, either side of the hatches
    def racks(mb):
        for sy in (1, -1):
            for x0, x1 in ((-2.9, -1.3), (1.3, 2.9)):
                yi = sy * 1.95
                yo = sy * 1.55
                box(mb, (x0, yo, 0), (x1, yi, 1.6), C["steel"], mask(0.3), mat=1)
                for z in (0.5, 1.05):
                    box(mb, (x0 + 0.08, yo - sy * 0.02, z), (x1 - 0.08, yi, z + 0.05), C["steel_lt"], mask(0.4), mat=1)
                for i, x in enumerate((x0 + 0.45, x1 - 0.45)):
                    col = C["crate"] if (i + (sy > 0)) % 2 else C["darkblue"]
                    box(mb, (x - 0.3, yo + sy * 0.02, 0.6), (x + 0.3, yi - sy * 0.05, 1.1), col, mask(0.3), mat=1)
    m.prop("racks", racks)
