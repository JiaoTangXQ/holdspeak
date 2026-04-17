package.path = table.concat({
  "./hammerspoon/?.lua",
  "./hammerspoon/?/init.lua",
  "./hammerspoon/?/?.lua",
  "./spec/?.lua",
  package.path,
}, ";")

local specs = {
  "key_logic_spec",
  "pane_sort_spec",
  "fn_bridge_spec",
  "focus_probe_spec",
  "pane_cache_spec",
  "ghostty_spec",
  "ghostty_remote_spec",
  "karabiner_rules_spec",
  "pane_discovery_spec",
}

local failures = {}

for _, spec in ipairs(specs) do
  local ok, err = pcall(require, spec)
  if not ok then
    failures[#failures + 1] = string.format("%s: %s", spec, err)
  end
end

if #failures > 0 then
  io.stderr:write(table.concat(failures, "\n"), "\n")
  os.exit(1)
end

print(string.format("PASS %d specs", #specs))
