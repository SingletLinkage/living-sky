#!/usr/bin/env python3
"""Make conky windows click-through: give them an empty X11 *input* shape.

Mouse events then pass to whatever is underneath (desktop icons, right-click
menu, ...), while the window keeps drawing normally.
Usage: clickthrough.py [title-prefix]   (default: 'living-sky')
Exits 1 if no matching window was found yet (the runner retries).
"""
import ctypes, ctypes.util, sys
from Xlib import display
from Xlib.error import DisplayError

prefix = sys.argv[1] if len(sys.argv) > 1 else 'living-sky'
if not ctypes.util.find_library('X11') or not ctypes.util.find_library('Xext'):
    sys.exit('clickthrough: libX11 / libXext not found')
xlib = ctypes.cdll.LoadLibrary(ctypes.util.find_library('X11'))
xext = ctypes.cdll.LoadLibrary(ctypes.util.find_library('Xext'))
xlib.XOpenDisplay.restype = ctypes.c_void_p
xlib.XOpenDisplay.argtypes = [ctypes.c_char_p]
xlib.XFlush.argtypes = [ctypes.c_void_p]
xlib.XSync.argtypes = [ctypes.c_void_p, ctypes.c_int]
xlib.XCloseDisplay.argtypes = [ctypes.c_void_p]
xext.XShapeCombineRectangles.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_int,
                                         ctypes.c_int, ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int]
ShapeInput, ShapeSet, Unsorted = 2, 0, 0

try:
    d = display.Display()
except DisplayError as err:
    sys.exit('clickthrough: no X display (%s)' % err)
found = []
def walk(w):
    try:
        name = w.get_wm_name()
        if isinstance(name, str) and name.startswith(prefix):
            found.append(w.id)
        for c in w.query_tree().children:
            walk(c)
    except Exception:
        pass
walk(d.screen().root)

d.close()
dpy = xlib.XOpenDisplay(None)
if not dpy:
    sys.exit('clickthrough: XOpenDisplay failed')
for wid in found:
    xext.XShapeCombineRectangles(dpy, wid, ShapeInput, 0, 0, None, 0, ShapeSet, Unsorted)
xlib.XSync(dpy, 0)
xlib.XCloseDisplay(dpy)
print('click-through applied to', [hex(w) for w in found])
sys.exit(0 if found else 1)
