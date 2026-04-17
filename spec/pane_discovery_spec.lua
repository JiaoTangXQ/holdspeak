local pane_discovery = require("lib.pane_discovery")

local frame = pane_discovery.normalize_frame(10.4, 20.2, 300.7, 200.5)

assert(frame.x == 10, "frame x should floor")
assert(frame.y == 20, "frame y should floor")
assert(frame.w == 301, "frame width should ceil")
assert(frame.h == 201, "frame height should ceil")
