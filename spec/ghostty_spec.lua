local ghostty = require("lib.ghostty")

assert(type(ghostty.list_selected_tab_terminals) == "function", "ghostty list function missing")
assert(type(ghostty.focus_terminal) == "function", "ghostty focus function missing")
assert(type(ghostty.input_text) == "function", "ghostty input function missing")
