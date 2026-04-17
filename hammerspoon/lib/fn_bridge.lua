local M = {}

function M.new_state()
  return {
    fn_down = false,
  }
end

local function post_fn(is_down, deps)
  if deps and deps.post then
    return deps.post(is_down)
  end

  if not hs or not hs.eventtap or not hs.eventtap.event then
    return nil, "fn bridge requires Hammerspoon eventtap support"
  end

  hs.eventtap.event.newKeyEvent({}, "fn", is_down):post()
  return true
end

function M.hold(state, deps)
  local target = state or M.new_state()
  if target.fn_down then
    return true
  end

  local ok, err = post_fn(true, deps)
  if not ok then
    return nil, err
  end

  target.fn_down = true
  return true
end

function M.release(state, deps)
  local target = state or M.new_state()
  if not target.fn_down then
    return true
  end

  local ok, err = post_fn(false, deps)
  if not ok then
    return nil, err
  end

  target.fn_down = false
  return true
end

return M
