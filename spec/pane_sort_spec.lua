local key_logic = require("lib.key_logic")

local panes = {
  { id = "b", frame = { x = 400, y = 20, w = 100, h = 100 } },
  { id = "a", frame = { x = 10, y = 10, w = 100, h = 100 } },
  { id = "c", frame = { x = 15, y = 220, w = 100, h = 100 } },
}

local sorted = key_logic.sort_panes(panes, 30)

assert(sorted[1].id == "a", "top-left pane should sort first")
assert(sorted[2].id == "b", "top-right pane should sort second")
assert(sorted[3].id == "c", "bottom-left pane should sort third")
