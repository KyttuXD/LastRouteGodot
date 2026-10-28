"""Dive-lab props for the lab region's pod room (Last Route lore: Book 0 and Book 4), authored in metres like
blocky_props_regions.py. exec'd by build_blocky_props.py, so Part, TARGET_SIZE and _reg are in scope.

Every shape is our own design (the thuing bbmodels were reference only). No text, no names, no logos: the headsets'
grey tape covers where a logo was, and the console's list is unreadable bars. Front is +z, back (z = 0) on the wall.
"""


def _pod(film=False, lit=False):
    """A white shell-shaped dive pod lying head-to-wall, lid hinged open at the head end."""
    w, h, d = 1.0, 1.35, 2.2
    c = Part(w, h, d)
    c.add(0.15, 0.0, 0.25, w - 0.15, 0.12, d - 0.25, "grey")                    # plinth
    # the shell: a stepped tub, narrower at the ends so it reads rounded
    c.add(0.05, 0.12, 0.2, w - 0.05, 0.55, d - 0.2, "white")
    c.add(0.1, 0.12, 0.08, w - 0.1, 0.5, 0.2, "white")
    c.add(0.1, 0.12, d - 0.2, w - 0.1, 0.5, d - 0.08, "white")
    c.add(0.16, 0.42, 0.24, w - 0.16, 0.56, d - 0.24, "linen")                  # padded bed inside the rim
    c.add(0.3, 0.56, 0.28, w - 0.3, 0.64, 0.5, "linen")                         # head cushion
    c.add(0.05, 0.55, 0.2, 0.12, 0.6, d - 0.2, "porcelain")                     # rim
    c.add(w - 0.12, 0.55, 0.2, w - 0.05, 0.6, d - 0.2, "porcelain")
    # the lid, swung up and back at the head end like an opened shell
    lid_kind = "mirror" if film else "white"
    c.add(0.08, 0.6, 0.05, w - 0.08, 0.68, 1.4, "white", (-62, 0, 0), (w / 2, 0.6, 0.12))
    c.add(0.12, 0.68, 0.1, w - 0.12, 0.7, 1.32, lid_kind, (-62, 0, 0), (w / 2, 0.6, 0.12))
    if film:
        # one corner of the protective film peeled back and left
        c.add(w - 0.32, 0.7, 1.12, w - 0.12, 0.72, 1.32, "mirror", (-62, 0, 35), (w - 0.22, 0.7, 1.22))
    for x in (0.04, w - 0.1):                                                   # release clamps on the rim
        c.add(x, 0.5, 0.9, x + 0.06, 0.62, 1.05, "steel")
        c.add(x, 0.5, 1.6, x + 0.06, 0.62, 1.75, "steel")
    for z in (0.7, 1.15, 1.6):                                                  # sensor pads on the bed
        c.add(0.4, 0.56, z, 0.6, 0.58, z + 0.12, "black")
    c.add(w / 2 - 0.05, 0.0, 0.0, w / 2 + 0.05, 0.1, 0.25, "black")             # cable run to the console
    c.add(0.1, 0.13, d - 0.1, w - 0.1, 0.2, d - 0.06, "screen" if lit else "grey")   # status strip at the foot
    return c.boxes


def headset_stand():
    w, h, d = 0.32, 1.25, 0.32
    c = Part(w, h, d)
    c.add(0.04, 0.0, 0.04, w - 0.04, 0.04, d - 0.04, "grey")                    # weighted foot
    c.add(0.14, 0.04, 0.14, 0.18, 1.0, 0.18, "steel")                           # pole
    c.add(0.06, 1.0, 0.08, w - 0.06, 1.2, d - 0.08, "white")                    # headset shell
    c.add(0.06, 1.05, d - 0.09, w - 0.06, 1.15, d - 0.07, "black")              # visor
    c.add(w - 0.07, 1.06, 0.1, w - 0.05, 1.14, d - 0.1, "grey")                 # grey tape over the side
    c.add(0.1, 0.95, 0.12, 0.12, 1.0, d - 0.12, "black")                        # chin strap
    return c.boxes


def headset_shelf():
    """Wall shelf over the console: six headsets on six stands, each with grey tape across one side."""
    w, h, d = 1.9, 0.45, 0.32
    c = Part(w, h, d)
    c.add(0.0, 0.0, 0.0, w, 0.04, d, "white")                                   # shelf board
    for x in (0.05, w - 0.09):
        c.add(x, -0.0, 0.0, x + 0.04, 0.12, 0.2, "steel")                       # brackets (under the board, to the wall)
    for i in range(6):
        x0 = 0.08 + i * 0.3
        c.add(x0 + 0.1, 0.04, 0.12, x0 + 0.14, 0.18, 0.16, "steel")             # stand
        c.add(x0, 0.18, 0.06, x0 + 0.24, 0.38, d - 0.04, "white")               # headset shell
        c.add(x0, 0.22, d - 0.05, x0 + 0.24, 0.32, d - 0.03, "black")           # visor
        c.add(x0 + 0.2, 0.24, 0.08, x0 + 0.24, 0.32, d - 0.06, "grey")          # tape
    return c.boxes


def dive_console():
    """Monitoring console: one screen with a slowly scrolling list (unreadable bars), a steady green uplink bulb, a pad
    of intake forms and a row of sensor pads waiting on the desk edge."""
    w, h, d = 2.0, 1.3, 0.8
    c = Part(w, h, d)
    c.add(0.0, 0.0, 0.0, w, 0.72, 0.6, "grey")                                  # desk body
    c.add(0.0, 0.72, 0.0, w, 0.77, d, "white")                                  # desk top
    c.add(0.55, 0.77, 0.12, 0.65, 0.9, 0.2, "black")                            # monitor stem
    c.add(0.2, 0.9, 0.1, 1.0, 1.28, 0.16, "black")                              # monitor
    c.add(0.24, 0.94, 0.16, 0.96, 1.24, 0.165, "dark")
    for i in range(6):                                                          # the list: lines of bars, no text
        y = 0.97 + i * 0.045
        c.add(0.28, y, 0.165, 0.28 + (0.3 + 0.08 * (i % 3)), y + 0.02, 0.17, "screen")
    c.add(1.2, 0.77, 0.15, 1.28, 0.85, 0.23, "green")                           # uplink bulb
    c.add(0.45, 0.77, 0.4, 0.95, 0.79, 0.62, "black")                           # keyboard
    c.add(1.2, 0.77, 0.4, 1.5, 0.79, 0.62, "paper")                             # intake forms
    for i in range(5):                                                          # sensor pads on the edge
        c.add(1.55 + i * 0.08, 0.77, 0.66, 1.61 + i * 0.08, 0.785, 0.76, "black")
    return c.boxes


_reg("divePod", _pod(), (1.0, 1.35, 2.2))
_reg("divePodFilm", _pod(film=True), (1.0, 1.35, 2.2))
_reg("divePodLit", _pod(lit=True), (1.0, 1.35, 2.2))
_reg("diveHeadsetStand", headset_stand(), (0.32, 1.25, 0.32))
_reg("diveHeadsetShelf", headset_shelf(), (1.9, 0.45, 0.32))
_reg("diveConsole", dive_console(), (2.0, 1.3, 0.8))
