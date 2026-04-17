# Ghostty Digit Voice Router

## Requirements

- macOS
- Ghostty
- Hammerspoon
- Karabiner-Elements
- WeChat for macOS with `Fn` hold-to-talk enabled
- Lua 5.4+

## Status

Workspace implementation for routing long-press number keys in `Ghostty` to
dynamic panes while delegating speech recognition to WeChat's `Fn` hold-to-talk
input.

## How It Works

- `Karabiner-Elements` handles the keyboard transformation.
- `Hammerspoon` keeps a background cache of the current Ghostty tab's pane order.
- Short tap on `1` through `0`: keep the original digit.
- Long press on `1` through `0` while `Ghostty` is frontmost:
  - call `Hammerspoon` synchronously through `hs -c 'return auto_speak_focus(N)'`
  - look up pane `N` from the cached pane map
  - focus the matching pane in the current Ghostty tab
  - hold `Fn` so WeChat voice input starts in the newly focused pane
  - release `Fn` automatically when you release the digit

`0` maps to pane `10`.

## Files

- `hammerspoon/init.lua`: loader and runtime configuration
- `hammerspoon/ghostty_remote.lua`: Hammerspoon pane-cache runtime and focus entrypoint
- `hammerspoon/lib/ghostty.lua`: Ghostty AppleScript bridge
- `hammerspoon/lib/karabiner_rules.lua`: Karabiner rule generator and config merger
- `hammerspoon/lib/pane_cache.lua`: pane-cache signature and lookup helpers
- `hammerspoon/lib/pane_discovery.lua`: focused-pane frame probing and sorting

## Setup

1. Give `Hammerspoon` `Accessibility` and `Input Monitoring`.
2. Install `Karabiner-Elements` and allow its virtual HID driver.
3. Confirm WeChat voice input can be triggered by holding `Fn` inside `Ghostty`.
4. Load [hammerspoon/init.lua](hammerspoon/init.lua)
   from your existing `~/.hammerspoon/init.lua`.

Minimal loader snippet (replace `<repo-path>` with the absolute path to your clone):

```lua
dofile("<repo-path>/hammerspoon/init.lua")
```

## Verification

Run the local Lua specs:

```bash
lua scripts/run_lua_specs.lua
```

Run Lua syntax validation:

```bash
find hammerspoon spec scripts -name '*.lua' -print0 | xargs -0 -n1 luac -p
```

## Known Limitations

- Pane discovery relies on Ghostty accessibility exposure and may need tuning if Ghostty changes.
- Cache refresh still performs pane discovery in the background after a pane layout change, so you may see a brief focus flicker when Ghostty's terminal set changes.
- Immediately after a brand-new pane layout change, the first long press may miss until the cache refresh finishes.
- WeChat voice input still depends on `Fn`, so this setup only works if WeChat recognizes Karabiner's virtual `Fn`.
