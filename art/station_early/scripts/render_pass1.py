"""Headless pass-1 driver: rebuild, save .blend, render closed + cut.

blender -b --factory-startup --python art/station_early/scripts/render_pass1.py
"""
import os

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
exec(open(os.path.join(HERE, "build_blockout.py")).read())

s = bpy.context.scene
room = bpy.data.objects["hull_roomA"]
cut = room.modifiers["CUT_PREVIEW"]
col = bpy.data.collections["CUT_PREVIEW"]

bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT, "station_early.blend"))

for name, on in (("render_closed.png", False), ("render_cut.png", True)):
    cut.show_render = cut.show_viewport = on
    s.render.filepath = os.path.join(ROOT, "renders", name)
    bpy.ops.render.render(write_still=True)
    print("RENDERED", name)

cut.show_render = cut.show_viewport = True
bpy.ops.wm.save_mainfile()
print("DONE")
