local source = debug.getinfo(1, "S").source:sub(2)
local dir = source:match("(.*/)")

local function append_loader_log(message)
  local file = io.open("/tmp/auto-speak-loader.log", "a")
  if not file then
    return
  end

  file:write(os.date("%Y-%m-%d %H:%M:%S "), message, "\n")
  file:close()
end

append_loader_log("loader_start")

local function append_diag_log(message)
  local file = io.open("/tmp/auto-speak-diag.log", "a")
  if not file then
    return
  end

  file:write(os.date("%Y-%m-%d %H:%M:%S "), message, "\n")
  file:close()
end

local function append_event_log(message)
  local file = io.open("/tmp/auto-speak-events.log", "a")
  if not file then
    return
  end

  file:write(os.date("%Y-%m-%d %H:%M:%S "), message, "\n")
  file:close()
end

package.path = table.concat({
  dir .. "?.lua",
  dir .. "?/init.lua",
  dir .. "?/?.lua",
  package.path,
}, ";")

local ok_ipc, ipc_err = pcall(require, "hs.ipc")
append_loader_log("require_hs_ipc " .. tostring(ok_ipc) .. " " .. tostring(ipc_err))

local ok_require, remote = pcall(require, "ghostty_remote")
append_loader_log("require_ghostty_remote " .. tostring(ok_require) .. " " .. tostring(remote))

local function flags_summary(event)
  local ok, flags = pcall(function()
    return event:getFlags()
  end)
  if not ok or type(flags) ~= "table" then
    return "flags=nil"
  end

  local enabled = {}
  for _, name in ipairs({ "fn", "shift", "ctrl", "alt", "cmd" }) do
    if flags[name] then
      enabled[#enabled + 1] = name
    end
  end

  if #enabled == 0 then
    return "flags=none"
  end

  return "flags=" .. table.concat(enabled, "+")
end

local function start_debug_tap()
  if not hs or not hs.eventtap or not hs.keycodes then
    return nil, "eventtap unavailable"
  end

  if _G.auto_speak_debug_tap then
    _G.auto_speak_debug_tap:stop()
    _G.auto_speak_debug_tap = nil
  end

  local event_types = {
    hs.eventtap.event.types.flagsChanged,
    hs.eventtap.event.types.keyDown,
    hs.eventtap.event.types.keyUp,
  }

  local fn_code = hs.keycodes.map.fn
  local one_code = hs.keycodes.map["1"]
  _G.auto_speak_debug_tap = hs.eventtap.new(event_types, function(event)
    local event_type = event:getType()
    local key_code = event:getKeyCode()

    local should_log =
      key_code == fn_code or
      key_code == one_code or
      (event_type == hs.eventtap.event.types.flagsChanged and event:getFlags().fn)

    if should_log then
      append_event_log(string.format(
        "type=%s key_code=%s %s",
        tostring(event_type),
        tostring(key_code),
        flags_summary(event)
      ))
    end

    return false
  end)

  _G.auto_speak_debug_tap:start()
  return true
end

if ok_require then
  local ok_start, start_err = pcall(remote.start, {
    event_name = "auto-speak-focus",
    discovery = {
      focus_settle_us = 70000,
      row_tolerance = 30,
    },
  })
  append_loader_log("ghostty_remote_start " .. tostring(ok_start) .. " " .. tostring(start_err))

  local ok_global, global_err = pcall(function()
    _G.auto_speak_focus = function(index)
      append_diag_log("auto_speak_focus_begin index=" .. tostring(index))
      local ok, err = remote.focus_index(index, nil, remote.config)
      append_diag_log(string.format(
        "auto_speak_focus_end index=%s ok=%s err=%s",
        tostring(index),
        tostring(ok),
        tostring(err)
      ))
      return ok, err
    end

    _G.auto_speak_focus_and_hold_fn = function(index)
      append_diag_log("auto_speak_focus_and_hold_fn_begin index=" .. tostring(index))
      local ok, err = remote.focus_index_and_hold_fn(index, nil, remote.config)
      append_diag_log(string.format(
        "auto_speak_focus_and_hold_fn_end index=%s ok=%s err=%s",
        tostring(index),
        tostring(ok),
        tostring(err)
      ))
      return ok, err
    end

    _G.auto_speak_focus_wait_for_ax_and_hold_fn = function(index)
      append_diag_log("auto_speak_focus_wait_for_ax_and_hold_fn_begin index=" .. tostring(index))
      local ok, err = remote.focus_index_wait_for_ax_and_hold_fn(index, nil, remote.config)
      append_diag_log(string.format(
        "auto_speak_focus_wait_for_ax_and_hold_fn_end index=%s ok=%s err=%s",
        tostring(index),
        tostring(ok),
        tostring(err)
      ))
      return ok, err
    end

    _G.auto_speak_focus_wait_for_ax = function(index)
      append_diag_log("auto_speak_focus_wait_for_ax_begin index=" .. tostring(index))
      local detail, err = remote.focus_index_wait_for_ax(index, nil, remote.config)
      append_diag_log(string.format(
        "auto_speak_focus_wait_for_ax_end index=%s ok=%s err=%s signature=%s",
        tostring(index),
        tostring(detail ~= nil),
        tostring(err),
        tostring(detail and detail.signature or nil)
      ))
      return detail ~= nil, err
    end

    _G.auto_speak_release_fn = function()
      append_diag_log("auto_speak_release_fn_begin")
      local ok, err = remote.release_fn()
      append_diag_log(string.format(
        "auto_speak_release_fn_end ok=%s err=%s",
        tostring(ok),
        tostring(err)
      ))
      return ok, err
    end
  end)
  append_loader_log("auto_speak_focus_export " .. tostring(ok_global) .. " " .. tostring(global_err))

  local ok_tap, tap_err = pcall(start_debug_tap)
  append_loader_log("debug_tap_start " .. tostring(ok_tap) .. " " .. tostring(tap_err))
end
