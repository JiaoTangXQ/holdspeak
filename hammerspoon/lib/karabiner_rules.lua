local key_logic = require("lib.key_logic")

local M = {}

local DIGIT_KEYS = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0" }
local RULE_PREFIX = "Auto Speak Digit "

local function deep_copy(value)
  if type(value) ~= "table" then
    return value
  end

  local copy = {}
  for key, nested_value in pairs(value) do
    copy[key] = deep_copy(nested_value)
  end
  return copy
end

local function sleep_seconds_text(delay_ms)
  return string.format("%.3f", delay_ms / 1000)
end

local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function build_focus_shell_command(hs_cli_path, pane_index, focus_delay_ms, event_name)
  local url = string.format("hammerspoon://%s?index=%d", event_name, pane_index)
  local command = string.format("/usr/bin/open %s", shell_quote(url))
  if focus_delay_ms and focus_delay_ms > 0 then
    command = string.format("%s && /bin/sleep %s", command, sleep_seconds_text(focus_delay_ms))
  end
  return command
end

local function build_digit_rule(key, config)
  local pane_index = key_logic.target_index_for_key(key)

      return {
        description = string.format("%s%s", RULE_PREFIX, key),
        manipulators = {
                  {
                    type = "basic",
        from = {
          key_code = key,
          modifiers = {
            optional = { "any" },
          },
        },
        to_if_alone = {
          {
            key_code = key,
            halt = true,
          },
        },
        to_if_held_down = {
          {
            shell_command = build_focus_shell_command(
              config.hs_cli_path,
              pane_index,
              config.focus_delay_milliseconds,
              config.event_name
            ),
          },
          {
            key_code = "fn",
            halt = true,
          },
        },
        parameters = {
          ["basic.to_if_alone_timeout_milliseconds"] = config.hold_threshold_milliseconds,
          ["basic.to_if_held_down_threshold_milliseconds"] = config.hold_threshold_milliseconds,
        },
        conditions = {
          {
            type = "frontmost_application_if",
            bundle_identifiers = {
              config.bundle_identifier,
            },
          },
        },
      },
    },
  }
end

local function selected_profile(config)
  if type(config.profiles) ~= "table" then
    return nil
  end

  for _, profile in ipairs(config.profiles) do
    if profile.selected then
      return profile
    end
  end

  return config.profiles[1]
end

local function filtered_rules(rules)
  local kept = {}
  for _, rule in ipairs(rules or {}) do
    local description = type(rule) == "table" and rule.description or nil
    if type(description) ~= "string" or description:sub(1, #RULE_PREFIX) ~= RULE_PREFIX then
      kept[#kept + 1] = rule
    end
  end
  return kept
end

function M.build_digit_rules(config)
  local merged = {
    bundle_identifier = "^com\\.mitchellh\\.ghostty$",
    hs_cli_path = "/opt/homebrew/bin/hs",
    event_name = "auto-speak-focus",
    hold_threshold_milliseconds = 250,
    focus_delay_milliseconds = 0,
    speech_delay_milliseconds = 850,
  }

  if config then
    for key, value in pairs(config) do
      merged[key] = value
    end
  end

  local rules = {}
  for _, key in ipairs(DIGIT_KEYS) do
    rules[#rules + 1] = build_digit_rule(key, merged)
  end

  return rules
end

function M.merge_rules_into_config(config, rules)
  local copy = deep_copy(config)
  local profile = selected_profile(copy)
  if not profile then
    return copy
  end

  profile.complex_modifications = profile.complex_modifications or {}
  local existing = filtered_rules(profile.complex_modifications.rules)
  profile.complex_modifications.rules = existing

  for _, rule in ipairs(rules or {}) do
    profile.complex_modifications.rules[#profile.complex_modifications.rules + 1] = deep_copy(rule)
  end

  return copy
end

return M
