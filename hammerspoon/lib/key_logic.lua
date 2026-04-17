local M = {}

function M.target_index_for_key(key)
  if key == "0" then
    return 10
  end

  return tonumber(key)
end

function M.sort_panes(panes, row_tolerance)
  local tolerance = row_tolerance or 30
  local copy = {}

  for i, pane in ipairs(panes) do
    copy[i] = pane
  end

  table.sort(copy, function(left, right)
    local left_y = left.frame.y
    local right_y = right.frame.y

    if math.abs(left_y - right_y) <= tolerance then
      return left.frame.x < right.frame.x
    end

    return left_y < right_y
  end)

  return copy
end

return M
