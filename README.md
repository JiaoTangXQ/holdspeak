# holdspeak

One-key pane switch + WeChat hold-to-talk voice input for Ghostty on macOS. Tap a digit (`1`–`0`) to type it; long-press the same digit to jump to that pane and start `Fn` voice dictation in a single gesture. Built with Karabiner-Elements and Hammerspoon.

## How It Works

- **Karabiner-Elements** handles keyboard transformation:
  - A short tap emits the digit normally.
  - A `to_delayed_action` fires at 200 ms, asynchronously invoking Hammerspoon to switch the Ghostty pane.
  - At 550 ms, `to_if_held_down` fires `fn` via the virtual HID driver. By this time the pane focus has settled at the accessibility layer, so WeChat's hold-to-talk starts listening in the correct pane.
- **Hammerspoon** maintains a background cache of the current Ghostty tab's pane order and exposes `hammerspoon://auto-speak-focus?index=N` as a URL event handler. The shell command triggering it uses `open -g` so Hammerspoon never steals focus from Ghostty.
- Digit `0` maps to pane `10`.

## Requirements

- macOS
- [Ghostty](https://ghostty.org)
- [Karabiner-Elements](https://karabiner-elements.pqrs.org)
- [Hammerspoon](https://www.hammerspoon.org)
- WeChat for macOS with `Fn` hold-to-talk enabled
- Lua 5.4+ (only needed to run the specs locally)

## Installation

### 1. Install prerequisite apps

```sh
brew install --cask ghostty karabiner-elements hammerspoon
```

Install WeChat from the App Store and enable **Fn hold-to-talk** in its settings.

### 2. Clone this repo

```sh
git clone https://github.com/JiaoTangXQ/holdspeak.git ~/holdspeak
```

Put the clone wherever you like; the examples below assume `~/holdspeak`.

### 3. Wire up Hammerspoon

Append one line to `~/.hammerspoon/init.lua`:

```lua
dofile(os.getenv("HOME") .. "/holdspeak/hammerspoon/init.lua")
```

Click the Hammerspoon menu-bar icon → **Reload Config**.

### 4. Install the Karabiner rules

**Option A — fresh machine, no other Karabiner rules yet**

```sh
cp ~/holdspeak/karabiner/karabiner.json ~/.config/karabiner/karabiner.json
```

Karabiner-Elements hot-reloads automatically. This overwrites your default profile, so only use it on a clean Karabiner install.

**Option B — existing Karabiner config**

1. Open `~/holdspeak/karabiner/karabiner.json` and copy the ten `Auto Speak Digit N` objects from `profiles[0].complex_modifications.rules`.
2. Paste them into your own `~/.config/karabiner/karabiner.json` under `profiles[<your-profile>].complex_modifications.rules`.
3. Save. Karabiner-Elements auto-reloads.

### 5. Grant system permissions

- **Hammerspoon** — System Settings → Privacy & Security → enable both:
  - Accessibility
  - Input Monitoring
- **Karabiner-Elements** — follow the first-run prompts to approve its Virtual HID driver.

### 6. Verify

Open Ghostty with at least two panes. Put focus in any pane other than pane `1`. Long-press `1` for about a second. The target pane should gain focus and WeChat's voice bubble should appear. Speak, then release `1`; the transcript lands in the target pane.

## Usage

| Gesture | Behavior |
| --- | --- |
| Tap digit (< 200 ms) | Types the digit normally |
| Long-press digit (≥ 550 ms) | Switches to the matching Ghostty pane and starts WeChat `Fn` voice input |
| Release | Ends voice input and submits the transcription |

Digits `1`–`9` map to panes 1–9. `0` maps to pane 10.

## Tuning

To adjust timings, edit the `parameters` block on each rule in `~/.config/karabiner/karabiner.json`:

- `basic.to_if_alone_timeout_milliseconds` (default `200`) — the window during which release still counts as a tap and emits the digit.
- `basic.to_delayed_action_delay_milliseconds` (default `200`) — when the pane-switch URL event is dispatched. Should be less than or equal to the alone timeout.
- `basic.to_if_held_down_threshold_milliseconds` (default `550`) — when `fn` fires. The gap between this and the delay is the budget for pane focus to settle at the accessibility layer; reducing it speeds up voice activation but raises the failure rate under load.

## Disabling

- **Temporary** — Karabiner-Elements → Complex Modifications → toggle off each `Auto Speak Digit N` rule.
- **Per session** — quit Hammerspoon or Karabiner-Elements from the menu bar.
- **Permanent** — remove the `dofile(...)` line from `~/.hammerspoon/init.lua` and delete the ten rules from `~/.config/karabiner/karabiner.json`.

## Files

- `hammerspoon/init.lua` — loader and runtime configuration.
- `hammerspoon/ghostty_remote.lua` — pane-cache runtime and URL-event entry point.
- `hammerspoon/lib/ghostty.lua` — Ghostty AppleScript bridge.
- `hammerspoon/lib/karabiner_rules.lua` — Karabiner rule generator.
- `hammerspoon/lib/pane_cache.lua` — pane-cache signature and lookup helpers.
- `hammerspoon/lib/pane_discovery.lua` — focused-pane frame probing and sorting.
- `karabiner/karabiner.json` — reference Karabiner-Elements config containing the ten rules.

## Development

```sh
lua scripts/run_lua_specs.lua                                                # run the Lua specs
find hammerspoon spec scripts -name '*.lua' -print0 | xargs -0 -n1 luac -p   # validate Lua syntax
```

## Known Limitations

- Pane discovery relies on Ghostty's accessibility exposure and may need tuning if Ghostty changes its AX layout.
- The first long-press after a brand-new pane layout change may miss while the background cache refresh finishes.
- Karabiner-Elements dispatches `shell_command` asynchronously and does not wait for it before firing subsequent events in the same `to_*` array. This is why pane switching is scheduled via `to_delayed_action` *before* the hold threshold rather than inside `to_if_held_down` alongside `fn`.
- Hammerspoon-synthesized `fn` events via `hs.eventtap` are not recognized by WeChat's hold-to-talk, so posting `fn` through Karabiner's Virtual HID driver is the only reliable path. This project cannot be reimplemented without Karabiner-Elements.
