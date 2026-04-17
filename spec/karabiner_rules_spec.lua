local rules = require("lib.karabiner_rules")

assert(type(rules.build_digit_rules) == "function", "build_digit_rules should exist")
assert(type(rules.merge_rules_into_config) == "function", "merge_rules_into_config should exist")

local digit_rules = rules.build_digit_rules({
  bundle_identifier = "^com\\.mitchellh\\.ghostty$",
  hs_cli_path = "/opt/homebrew/bin/hs",
  hold_threshold_milliseconds = 280,
  focus_delay_milliseconds = 0,
  speech_delay_milliseconds = 900,
})

assert(#digit_rules == 10, "build_digit_rules should emit rules for digits 1 through 0")

local first = digit_rules[1]
local manipulator = first.manipulators[1]

assert(manipulator.from.key_code == "1", "first digit rule should target the 1 key")
assert(manipulator.to == nil, "digit rules should not send a pre-held lazy fn that can interfere with the held-down path")
assert(manipulator.to_if_alone[1].key_code == "1", "short press should preserve the digit")
assert(
  manipulator.to_if_held_down[1].shell_command:match("^/usr/bin/open "),
  "held rule should dispatch focus via a non-blocking URL event, not a blocking hs CLI call"
)
assert(
  manipulator.to_if_held_down[1].shell_command:match("hammerspoon://auto%-speak%-focus%?index=1"),
  "held rule should target the auto-speak-focus URL event for the matching digit"
)
assert(
  manipulator.to_if_held_down[2].key_code == "fn",
  "fn must be the last held-down event so its key_up is bound to the physical digit key_up"
)
assert(manipulator.to_after_key_up == nil, "digit rules should not need a separate Hammerspoon key-up release path")
assert(manipulator.parameters["basic.to_if_held_down_threshold_milliseconds"] == 280, "held threshold should be configurable")
assert(manipulator.conditions[1].bundle_identifiers[1] == "^com\\.mitchellh\\.ghostty$", "digit rules should be limited to Ghostty")

local merged = rules.merge_rules_into_config({
  profiles = {
    {
      name = "Default profile",
      selected = true,
      complex_modifications = {
        rules = {
          {
            description = "existing",
            manipulators = {},
          },
        },
      },
    },
  },
}, digit_rules)

local merged_rules = merged.profiles[1].complex_modifications.rules
assert(#merged_rules == 11, "merge_rules_into_config should append digit rules to the selected profile")
assert(merged_rules[1].description == "existing", "merge_rules_into_config should preserve existing rules")
assert(merged_rules[2].description:match("Digit 1"), "merge_rules_into_config should append new digit rules")
