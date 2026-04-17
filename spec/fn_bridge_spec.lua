local fn_bridge = require("lib.fn_bridge")

assert(type(fn_bridge.new_state) == "function", "fn_bridge.new_state should exist")
assert(type(fn_bridge.hold) == "function", "fn_bridge.hold should exist")
assert(type(fn_bridge.release) == "function", "fn_bridge.release should exist")

do
  local posted = {}
  local state = fn_bridge.new_state()

  local ok, err = fn_bridge.hold(state, {
    post = function(is_down)
      posted[#posted + 1] = is_down
      return true
    end,
  })

  assert(ok == true, "hold should succeed when posting fn down works")
  assert(err == nil, "hold should not return an error on success")
  assert(state.fn_down == true, "hold should mark fn as down")
  assert(#posted == 1 and posted[1] == true, "hold should post a single fn down event")

  ok, err = fn_bridge.hold(state, {
    post = function()
      error("hold should not repost fn when already down")
    end,
  })

  assert(ok == true, "hold should be idempotent while fn is already down")
  assert(err == nil, "hold should remain silent when fn is already down")
end

do
  local posted = {}
  local state = fn_bridge.new_state()
  state.fn_down = true

  local ok, err = fn_bridge.release(state, {
    post = function(is_down)
      posted[#posted + 1] = is_down
      return true
    end,
  })

  assert(ok == true, "release should succeed when posting fn up works")
  assert(err == nil, "release should not return an error on success")
  assert(state.fn_down == false, "release should mark fn as up")
  assert(#posted == 1 and posted[1] == false, "release should post a single fn up event")

  ok, err = fn_bridge.release(state, {
    post = function()
      error("release should not repost fn when already up")
    end,
  })

  assert(ok == true, "release should be idempotent while fn is already up")
  assert(err == nil, "release should remain silent when fn is already up")
end
