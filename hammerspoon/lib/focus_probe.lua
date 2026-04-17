local M = {}

local DEFAULT_OPTIONS = {
  poll_interval_us = 20000,
  timeout_us = 700000,
  stable_samples = 3,
}

local function merged_options(options)
  local merged = {
    poll_interval_us = DEFAULT_OPTIONS.poll_interval_us,
    timeout_us = DEFAULT_OPTIONS.timeout_us,
    stable_samples = DEFAULT_OPTIONS.stable_samples,
  }

  if type(options) == "table" then
    for key, value in pairs(options) do
      merged[key] = value
    end
  end

  return merged
end

local function default_sleep(delay_us)
  if not hs or not hs.timer then
    error("focus probe requires Hammerspoon timer support")
  end

  hs.timer.usleep(delay_us)
end

local function default_get_element()
  if not hs or not hs.axuielement then
    return nil, "focus probe requires Hammerspoon accessibility support"
  end

  local system = hs.axuielement.systemWideElement()
  if not system then
    return nil, "system-wide accessibility element unavailable"
  end

  return system:attributeValue("AXFocusedUIElement")
end

local function normalize_frame(frame)
  if not frame then
    return nil
  end

  local x = frame.x
  local y = frame.y
  local w = frame.w or frame.width
  local h = frame.h or frame.height

  if x == nil or y == nil or w == nil or h == nil then
    return nil
  end

  return {
    x = math.floor(x),
    y = math.floor(y),
    w = math.ceil(w),
    h = math.ceil(h),
  }
end

local function frame_from_element(element)
  if not element then
    return nil
  end

  local frame = normalize_frame(element:attributeValue("AXFrame"))
  if frame then
    return frame
  end

  local position = element:attributeValue("AXPosition")
  local size = element:attributeValue("AXSize")
  if not position or not size then
    return nil
  end

  return normalize_frame({
    x = position.x,
    y = position.y,
    w = size.w or size.width,
    h = size.h or size.height,
  })
end

function M.snapshot_for_element(element)
  if not element then
    return nil
  end

  local path = element.path and element:path() or nil

  return {
    role = element:attributeValue("AXRole"),
    subrole = element:attributeValue("AXSubrole"),
    title = element:attributeValue("AXTitle"),
    description = element:attributeValue("AXDescription"),
    frame = frame_from_element(element),
    path_length = type(path) == "table" and #path or nil,
  }
end

function M.signature_for_snapshot(snapshot)
  if not snapshot then
    return nil
  end

  local frame = snapshot.frame
  local frame_signature = "noframe"
  if frame then
    frame_signature = string.format("%d,%d,%d,%d", frame.x, frame.y, frame.w, frame.h)
  end

  return table.concat({
    tostring(snapshot.role or ""),
    tostring(snapshot.subrole or ""),
    tostring(snapshot.title or ""),
    tostring(snapshot.description or ""),
    tostring(snapshot.path_length or ""),
    frame_signature,
  }, "|")
end

function M.describe_snapshot(snapshot)
  if not snapshot then
    return "snapshot=nil"
  end

  local parts = {
    string.format("role=%s", tostring(snapshot.role)),
    string.format("subrole=%s", tostring(snapshot.subrole)),
    string.format("title=%s", tostring(snapshot.title)),
    string.format("description=%s", tostring(snapshot.description)),
    string.format("path_length=%s", tostring(snapshot.path_length)),
  }

  local frame = snapshot.frame
  if frame then
    parts[#parts + 1] = string.format("frame=%d,%d,%d,%d", frame.x, frame.y, frame.w, frame.h)
  else
    parts[#parts + 1] = "frame=nil"
  end

  if snapshot.signature then
    parts[#parts + 1] = string.format("signature=%s", snapshot.signature)
  end

  return table.concat(parts, " ")
end

function M.read_snapshot(deps)
  local get_element = deps and deps.get_element or default_get_element
  local snapshot_builder = deps and deps.snapshot_for_element or M.snapshot_for_element

  local element, element_err = get_element()
  if not element then
    return nil, element_err or "focused accessibility element unavailable"
  end

  local snapshot = snapshot_builder(element)
  if not snapshot then
    return nil, "focused accessibility snapshot unavailable"
  end

  snapshot.signature = M.signature_for_snapshot(snapshot)
  return snapshot
end

function M.wait_for_stable_change(previous_signature, options, deps)
  local opts = merged_options(options)
  local sleep = deps and deps.sleep or default_sleep
  local log = deps and deps.log_probe_sample

  local attempts = 0
  local elapsed_us = 0
  local stable_count = 0
  local target_signature = nil
  local last_snapshot = nil
  local last_err = nil

  while true do
    attempts = attempts + 1

    local snapshot, snapshot_err = M.read_snapshot(deps)
    local signature = snapshot and snapshot.signature or nil
    local changed = signature ~= nil and (previous_signature == nil or signature ~= previous_signature)

    last_snapshot = snapshot or last_snapshot
    last_err = snapshot_err

    if changed then
      if signature == target_signature then
        stable_count = stable_count + 1
      else
        target_signature = signature
        stable_count = 1
      end
    else
      stable_count = 0
      target_signature = nil
    end

    if log then
      log({
        attempt = attempts,
        elapsed_us = elapsed_us,
        stable_count = stable_count,
        changed = changed,
        previous_signature = previous_signature,
        signature = signature,
        snapshot = snapshot,
        err = snapshot_err,
      })
    end

    if changed and stable_count >= opts.stable_samples then
      return {
        attempt = attempts,
        elapsed_us = elapsed_us,
        stable_count = stable_count,
        previous_signature = previous_signature,
        signature = signature,
        snapshot = snapshot,
      }
    end

    if elapsed_us >= opts.timeout_us then
      break
    end

    sleep(opts.poll_interval_us)
    elapsed_us = elapsed_us + opts.poll_interval_us
  end

  return nil, "AX focus did not change and stabilize", {
    attempt = attempts,
    elapsed_us = elapsed_us,
    stable_count = stable_count,
    previous_signature = previous_signature,
    signature = target_signature,
    snapshot = last_snapshot,
    err = last_err,
  }
end

return M
