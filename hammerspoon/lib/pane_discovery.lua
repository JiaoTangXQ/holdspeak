local ghostty = require("lib.ghostty")
local key_logic = require("lib.key_logic")

local M = {}

function M.normalize_frame(x, y, w, h)
  return {
    x = math.floor(x),
    y = math.floor(y),
    w = math.ceil(w),
    h = math.ceil(h),
  }
end

local function as_frame(value)
  if not value then
    return nil
  end

  if value.x and value.y and value.w and value.h then
    return M.normalize_frame(value.x, value.y, value.w, value.h)
  end

  if value.x and value.y and value.width and value.height then
    return M.normalize_frame(value.x, value.y, value.width, value.height)
  end

  return nil
end

local function frame_from_element(element)
  if not element then
    return nil
  end

  local frame = as_frame(element:attributeValue("AXFrame"))
  if frame then
    return frame
  end

  local position = element:attributeValue("AXPosition")
  local size = element:attributeValue("AXSize")
  if position and size and position.x and position.y and size.w and size.h then
    return M.normalize_frame(position.x, position.y, size.w, size.h)
  end

  if position and size and position.x and position.y and size.width and size.height then
    return M.normalize_frame(position.x, position.y, size.width, size.height)
  end

  return nil
end

local function capture_focused_frame(window_frame)
  local focused = hs.axuielement.systemWideElement():attributeValue("AXFocusedUIElement")
  if not focused then
    return nil, "no focused accessibility element"
  end

  local path = focused:path()
  for i = #path, 1, -1 do
    local frame = frame_from_element(path[i])
    if frame and frame.w > 50 and frame.h > 50 then
      if not window_frame then
        return frame
      end

      local within_window =
        frame.x >= window_frame.x - 4 and
        frame.y >= window_frame.y - 4 and
        (frame.x + frame.w) <= (window_frame.x + window_frame.w + 4) and
        (frame.y + frame.h) <= (window_frame.y + window_frame.h + 4)

      if within_window then
        return frame
      end
    end
  end

  return nil, "no usable pane frame found"
end

function M.discover_current_tab_panes(options)
  if not hs or not hs.axuielement then
    error("Pane discovery requires Hammerspoon runtime")
  end

  local opts = options or {}
  local delay_us = opts.focus_settle_us or 80000
  local row_tolerance = opts.row_tolerance or 30
  local listing, err = ghostty.list_selected_tab_terminals()
  if not listing then
    return nil, err
  end

  local window_frame = ghostty.front_window_frame()
  local panes = {}

  for _, terminal_id in ipairs(listing.terminals) do
    local ok, focus_err = ghostty.focus_terminal(terminal_id)
    if not ok then
      return nil, focus_err
    end

    hs.timer.usleep(delay_us)
    local frame, frame_err = capture_focused_frame(window_frame)
    if not frame then
      return nil, frame_err
    end

    panes[#panes + 1] = {
      id = terminal_id,
      frame = frame,
    }
  end

  if listing.focused then
    ghostty.focus_terminal(listing.focused)
  end

  return key_logic.sort_panes(panes, row_tolerance)
end

function M.target_terminal_for_index(index, options)
  local panes, err = M.discover_current_tab_panes(options)
  if not panes then
    return nil, err
  end

  return panes[index]
end

return M
