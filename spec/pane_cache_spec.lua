local pane_cache = require("lib.pane_cache")

assert(type(pane_cache.new_state) == "function", "pane_cache.new_state should exist")
assert(type(pane_cache.signature_for_listing) == "function", "pane_cache.signature_for_listing should exist")
assert(type(pane_cache.store) == "function", "pane_cache.store should exist")
assert(type(pane_cache.lookup) == "function", "pane_cache.lookup should exist")

local state = pane_cache.new_state()

local listing = {
  terminals = { "terminal-a", "terminal-b", "terminal-c" },
}

local signature = pane_cache.signature_for_listing(listing)
assert(signature == "terminal-a\30terminal-b\30terminal-c", "signature should preserve terminal order")

pane_cache.store(state, listing, {
  { id = "pane-1" },
  { id = "pane-2" },
  { id = "pane-3" },
})

local pane = pane_cache.lookup(state, listing, 2)
assert(pane and pane.id == "pane-2", "lookup should return the cached pane when the listing matches")

local missing_pane, missing_err = pane_cache.lookup(state, listing, 9)
assert(missing_pane == nil, "lookup should reject missing indexes")
assert(missing_err == "pane index not cached", "lookup should explain missing pane indexes")

local stale_pane, stale_err = pane_cache.lookup(state, {
  terminals = { "terminal-a", "terminal-c", "terminal-b" },
}, 2)
assert(stale_pane == nil, "lookup should reject stale cache entries")
assert(stale_err == "pane cache unavailable", "lookup should explain stale cache misses")
