local ITEM_SEPARATOR = string.char(30)

local M = {}

function M.new_state()
  return {
    signature = nil,
    panes_by_index = {},
    pending_signature = nil,
    refresh_in_progress = false,
    refresh_timer = nil,
  }
end

function M.signature_for_listing(listing)
  if type(listing) ~= "table" or type(listing.terminals) ~= "table" then
    return nil
  end

  local terminals = {}
  for _, terminal_id in ipairs(listing.terminals) do
    terminals[#terminals + 1] = tostring(terminal_id)
  end

  return table.concat(terminals, ITEM_SEPARATOR)
end

function M.store(state, listing, panes)
  local target = state or M.new_state()
  target.signature = M.signature_for_listing(listing)
  target.panes_by_index = {}

  for index, pane in ipairs(panes or {}) do
    target.panes_by_index[index] = pane
  end

  return target
end

function M.lookup(state, listing, index)
  if
    not state or
    not state.signature or
    type(state.panes_by_index) ~= "table"
  then
    return nil, "pane cache unavailable"
  end

  local current_signature = M.signature_for_listing(listing)
  if not current_signature or current_signature ~= state.signature then
    return nil, "pane cache unavailable"
  end

  local pane = state.panes_by_index[index]
  if not pane then
    return nil, "pane index not cached"
  end

  return pane
end

return M
