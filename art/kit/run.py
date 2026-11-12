"""Build one module: blender -b --factory-startup --python art/kit/run.py -- --module=<id>
[--render] [--no-export]. Prefer tools/art.sh <id> [--render] [--no-export].

Loads art/modules/<id>.py (ID, LAYOUT, optional BUDGET / SEED / SIZES, build(m)),
builds it, validates it (non-zero exit on any KIT ERROR), saves
art/modules/build/<id>.blend, exports assets/models/modules/<id>.glb + the kit
palette and art/modules/export/<id>.json, and optionally renders previews to
art/modules/renders/.
"""
import importlib.util
import os
import sys

ART = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ART)

from kit.module import Module  # noqa: E402

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
opts = dict(a[2:].split("=", 1) if "=" in a else (a[2:], "") for a in args)
mid = opts.get("module")
if not mid:
    print("KIT ERROR: --module=<id> missing")
    sys.exit(2)
path = os.path.join(ART, "modules", mid + ".py")
spec_loader = importlib.util.spec_from_file_location("module_spec_" + mid, path)
spec = importlib.util.module_from_spec(spec_loader)
spec_loader.loader.exec_module(spec)

m = Module(spec.ID, spec.LAYOUT, budget=getattr(spec, "BUDGET", 15000),
           seed=getattr(spec, "SEED", 1), sizes=getattr(spec, "SIZES", None))
spec.build(m)
m.finish()
print("KIT STATS", m.sidecar())
m.save_blend()
if "no-export" not in opts:
    m.export()
if "render" in opts:
    m.render()
if m.errors:
    print("KIT FAILED: %d error(s)" % len(m.errors))
    sys.exit(1)
print("KIT OK", mid)
