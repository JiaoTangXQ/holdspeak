local M = {}

local FIELD_SEPARATOR = string.char(31)
local ITEM_SEPARATOR = string.char(30)
local GHOSTTY_BUNDLE_ID = "com.mitchellh.ghostty"
local GHOSTTY_APP_NAME = "Ghostty"

local function quote_applescript(text)
  return string.format("%q", text)
end

local function split(text, delimiter)
  local items = {}

  if not text or text == "" then
    return items
  end

  local pattern = string.format("([^%s]+)", delimiter)
  for item in string.gmatch(text, pattern) do
    items[#items + 1] = item
  end

  return items
end

local function run_applescript(script)
  if not hs or not hs.osascript then
    error("Ghostty scripting requires Hammerspoon runtime")
  end

  local ok, result, err = hs.osascript.applescript(script)
  if not ok then
    return nil, err
  end

  return result
end

function M.is_frontmost()
  local app = hs and hs.application and hs.application.frontmostApplication()
  if not app then
    return false
  end

  local bundle_id = app:bundleID()
  local name = app:name()
  return bundle_id == GHOSTTY_BUNDLE_ID or name == GHOSTTY_APP_NAME
end

function M.frontmost_application_identity()
  local app = hs and hs.application and hs.application.frontmostApplication()
  if not app then
    return {
      name = nil,
      bundle_id = nil,
    }
  end

  return {
    name = app:name(),
    bundle_id = app:bundleID(),
  }
end

function M.is_ghostty_application(app)
  if not app then
    return false
  end

  local bundle_id = app.bundleID and app:bundleID() or nil
  local name = app.name and app:name() or nil
  return bundle_id == GHOSTTY_BUNDLE_ID or name == GHOSTTY_APP_NAME
end

function M.front_window_frame()
  local window = hs and hs.window and hs.window.frontmostWindow()
  if not window then
    return nil
  end

  return window:frame()
end

function M.list_selected_tab_terminals()
  local script = [[
    tell application "Ghostty"
      set focusedId to id of focused terminal of selected tab of front window
      set terminalIds to {}
      repeat with t in terminals of selected tab of front window
        set end of terminalIds to id of t
      end repeat
      set AppleScript's text item delimiters to (character id 30)
      return focusedId & (character id 31) & (terminalIds as text)
    end tell
  ]]

  local result, err = run_applescript(script)
  if not result then
    return nil, err
  end

  local focused, rest = tostring(result):match("^(.-)" .. FIELD_SEPARATOR .. "(.*)$")
  if not focused then
    return nil, "unexpected Ghostty terminal listing payload"
  end

  return {
    focused = focused,
    terminals = split(rest, ITEM_SEPARATOR),
  }
end

function M.focus_terminal(terminal_id)
  local script = string.format([[
    tell application "Ghostty"
      focus (first terminal of selected tab of front window whose id is %s)
    end tell
  ]], quote_applescript(terminal_id))

  local _, err = run_applescript(script)
  if err then
    return nil, err
  end

  return true
end

function M.input_text(terminal_id, text)
  local script = string.format([[
    tell application "Ghostty"
      input text %s to (first terminal of selected tab of front window whose id is %s)
    end tell
  ]], quote_applescript(text), quote_applescript(terminal_id))

  local _, err = run_applescript(script)
  if err then
    return nil, err
  end

  return true
end

return M
