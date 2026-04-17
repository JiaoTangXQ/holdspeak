local key_logic = require("lib.key_logic")

assert(key_logic.target_index_for_key("1") == 1, "1 should map to pane 1")
assert(key_logic.target_index_for_key("0") == 10, "0 should map to pane 10")
