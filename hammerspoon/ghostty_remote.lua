local fn_bridge = require("lib.fn_bridge")
local focus_probe = require("lib.focus_probe")
local ghostty = require("lib.ghostty")
local pane_cache = require("lib.pane_cache")
local pane_discovery = require("lib.pane_discovery")

local M = {}

local DEFAULT_CONFIG = {
  event_name = "auto-speak-focus",
  cache = {
    poll_interval_seconds = 0.5,
    refresh_delay_seconds = 0.25,
  },
  bridge = {
    focus_to_fn_delay_us = 250000,
    pane_refocus_click_settle_us = 80000,
    speech_ready_delay_us = 250000,
    ax_focus_probe = {
      poll_interval_us = 20000,
      timeout_us = 700000,
      stable_samples = 3,
    },
  },
  discovery = {
    focus_settle_us = 70000,
    row_tolerance = 30,
  },
}

local LOG_PATH = "/tmp/auto-speak-remote.log"

local function append_log(message)
  local file = io.open(LOG_PATH, "a")
  if not file then
    return
  end

  file:write(os.date("%Y-%m-%d %H:%M:%S "), message, "\n")
  file:close()
end

local function merge_config(overrides)
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

  local function deep_merge(target, source)
    for key, value in pairs(source or {}) do
      if type(value) == "table" and type(target[key]) == "table" then
        deep_merge(target[key], value)
      else
        target[key] = deep_copy(value)
      end
    end
  end

  local config = deep_copy(DEFAULT_CONFIG)
  deep_merge(config, overrides)
  return config
end

local function sleep_microseconds(delay_us, deps)
  if not delay_us or delay_us <= 0 then
    return true
  end

  if deps and deps.sleep then
    deps.sleep(delay_us)
    return true
  end

  if hs and hs.timer then
    hs.timer.usleep(delay_us)
    return true
  end

  return nil, "no sleep implementation available"
end

local function center_point_for_frame(frame)
  if not frame then
    return nil
  end

  return {
    x = frame.x + math.floor(frame.w / 2),
    y = frame.y + math.floor(frame.h / 2),
  }
end

local function click_point(point, deps)
  if not point then
    return nil, "click point unavailable"
  end

  if deps and deps.click then
    return deps.click(point)
  end

  if not hs or not hs.eventtap or not hs.eventtap.event then
    return nil, "no click implementation available"
  end

  local event = hs.eventtap.event
  local types = event.types
  event.newMouseEvent(types.leftMouseDown, point):post()
  event.newMouseEvent(types.leftMouseUp, point):post()
  return true
end

local function cache_state(deps)
  return deps and deps.cache_state or M.cache_state
end

local function list_terminals(deps)
  return deps and deps.list or ghostty.list_selected_tab_terminals
end

local function discover_panes(deps)
  return deps and deps.discover or pane_discovery.discover_current_tab_panes
end

local function focus_terminal(deps)
  return deps and deps.focus or ghostty.focus_terminal
end

local function lookup_pane(index, deps)
  local lookup = deps and deps.lookup or function(requested_index)
    return M.cached_pane_for_index(requested_index, deps)
  end

  return lookup(index, {})
end

local function list_current_terminals(deps)
  return list_terminals(deps)()
end

local function is_frontmost_ghostty(deps)
  local predicate = deps and deps.is_frontmost or ghostty.is_frontmost
  return predicate()
end

local function append_cache_log(prefix, detail)
  append_log(string.format("%s %s", prefix, detail or ""))
end

local function append_ax_focus_log(message)
  local file = io.open("/tmp/auto-speak-ax-focus.log", "a")
  if not file then
    return
  end

  file:write(os.date("%Y-%m-%d %H:%M:%S "), message, "\n")
  file:close()
end

local function describe_probe_detail(detail)
  if not detail then
    return "detail=nil"
  end

  local parts = {
    string.format("attempt=%s", tostring(detail.attempt)),
    string.format("elapsed_us=%s", tostring(detail.elapsed_us)),
    string.format("stable_count=%s", tostring(detail.stable_count)),
    string.format("previous_signature=%s", tostring(detail.previous_signature)),
    string.format("signature=%s", tostring(detail.signature)),
    string.format("err=%s", tostring(detail.err)),
  }

  if detail.snapshot then
    parts[#parts + 1] = focus_probe.describe_snapshot(detail.snapshot)
  else
    parts[#parts + 1] = "snapshot=nil"
  end

  return table.concat(parts, " ")
end

local function wait_for_ax_focus_change(baseline_snapshot, deps, config)
  local probe = deps and deps.focus_probe or focus_probe
  local baseline_err = nil
  if not baseline_snapshot then
    baseline_snapshot, baseline_err = probe.read_snapshot(deps)
  end

  if not baseline_snapshot then
    return nil, baseline_err or "focused accessibility snapshot unavailable"
  end

  local previous_signature = baseline_snapshot and baseline_snapshot.signature or nil

  append_ax_focus_log(string.format(
    "baseline signature=%s err=%s %s",
    tostring(previous_signature),
    tostring(baseline_err),
    baseline_snapshot and probe.describe_snapshot(baseline_snapshot) or "snapshot=nil"
  ))

  local probe_options =
    config and
    config.bridge and
    config.bridge.ax_focus_probe or
    nil

  local result, wait_err, detail = probe.wait_for_stable_change(previous_signature, probe_options, {
    get_element = deps and deps.get_element or nil,
    snapshot_for_element = deps and deps.snapshot_for_element or nil,
    sleep = deps and deps.sleep or nil,
    log_probe_sample = function(sample)
      append_ax_focus_log(string.format(
        "sample attempt=%s elapsed_us=%s stable_count=%s changed=%s signature=%s err=%s %s",
        tostring(sample.attempt),
        tostring(sample.elapsed_us),
        tostring(sample.stable_count),
        tostring(sample.changed),
        tostring(sample.signature),
        tostring(sample.err),
        sample.snapshot and probe.describe_snapshot(sample.snapshot) or "snapshot=nil"
      ))
    end,
  })

  if not result then
    append_ax_focus_log(string.format("result ok=nil err=%s %s", tostring(wait_err), describe_probe_detail(detail)))
    return nil, wait_err
  end

  append_ax_focus_log(string.format("result ok=true %s", describe_probe_detail(result)))
  return result
end

function M.cached_pane_for_index(index, deps)
  local listing, list_err = list_terminals(deps)()
  if not listing then
    return nil, list_err
  end

  return pane_cache.lookup(cache_state(deps), listing, index)
end

function M.refresh_cache(deps, config, expected_signature)
  local state = cache_state(deps)
  if not state then
    return nil, "pane cache state unavailable"
  end

  if state.refresh_in_progress then
    return nil, "pane cache refresh already running"
  end

  if not is_frontmost_ghostty(deps) then
    return nil, "ghostty not frontmost"
  end

  local listing, list_err = list_terminals(deps)()
  if not listing then
    return nil, list_err
  end

  local current_signature = pane_cache.signature_for_listing(listing)
  if expected_signature and current_signature ~= expected_signature then
    return nil, "stale pane cache refresh request"
  end

  state.refresh_in_progress = true

  local panes, discover_err = discover_panes(deps)(config and config.discovery or {})
  if not panes then
    state.refresh_in_progress = false
    append_cache_log("refresh_cache_failed", tostring(discover_err))
    return nil, discover_err
  end

  local final_listing = listing
  local refreshed_listing = list_terminals(deps)()
  if refreshed_listing then
    final_listing = refreshed_listing
  end

  pane_cache.store(state, final_listing, panes)
  state.pending_signature = nil
  state.refresh_in_progress = false

  append_cache_log("refresh_cache", string.format("signature=%s panes=%d", tostring(state.signature), #panes))

  return true
end

function M.schedule_cache_refresh(deps, config, reason)
  local state = cache_state(deps)
  if not state then
    return nil, "pane cache state unavailable"
  end

  if not is_frontmost_ghostty(deps) then
    return nil, "ghostty not frontmost"
  end

  local listing, list_err = list_terminals(deps)()
  if not listing then
    return nil, list_err
  end

  local signature = pane_cache.signature_for_listing(listing)
  if not signature then
    return nil, "unable to derive pane cache signature"
  end

  if signature == state.signature or signature == state.pending_signature then
    return true
  end

  state.pending_signature = signature

  local delay = config and config.cache and config.cache.refresh_delay_seconds or 0
  local schedule = deps and deps.schedule
  local callback = function()
    state.refresh_timer = nil
    local ok, err = M.refresh_cache(deps, config, signature)
    if not ok then
      state.pending_signature = nil
    end
    append_cache_log(
      "schedule_cache_refresh",
      string.format("reason=%s signature=%s ok=%s err=%s", tostring(reason), tostring(signature), tostring(ok), tostring(err))
    )
  end

  if schedule then
    schedule(callback, delay)
    return true
  end

  if hs and hs.timer then
    if state.refresh_timer then
      state.refresh_timer:stop()
      state.refresh_timer = nil
    end

    state.refresh_timer = hs.timer.doAfter(delay, callback)
    return true
  end

  return nil, "no cache refresh scheduler available"
end

function M.start_cache_polling(config)
  if not hs or not hs.timer then
    return nil, "ghostty_remote cache polling requires Hammerspoon timer support"
  end

  if M.cache_poll_timer then
    M.cache_poll_timer:stop()
    M.cache_poll_timer = nil
  end

  local interval = config and config.cache and config.cache.poll_interval_seconds or DEFAULT_CONFIG.cache.poll_interval_seconds
  M.cache_poll_timer = hs.timer.doEvery(interval, function()
    M.schedule_cache_refresh(nil, config, "poll")
  end)

  return true
end

function M.focus_index(index, deps, config)
  local numeric_index = tonumber(index)
  if not numeric_index or numeric_index < 1 or numeric_index > 10 then
    return nil, "invalid pane index"
  end

  local lookup = deps and deps.lookup or function(requested_index)
    return M.cached_pane_for_index(requested_index, deps)
  end
  local focus = focus_terminal(deps)
  local merged_config = config and config.discovery or {}

  local pane, lookup_err = lookup(numeric_index, merged_config)
  if not pane then
    if deps == nil or deps.schedule or hs then
      M.schedule_cache_refresh(deps, config or M.config, "focus_miss")
    end

    append_log(string.format("focus_index_failed index=%s err=%s", tostring(numeric_index), tostring(lookup_err)))
    return nil, lookup_err
  end

  local ok, focus_err = focus(pane.id)
  append_log(string.format(
    "focus_index index=%s pane=%s ok=%s err=%s",
    tostring(numeric_index),
    tostring(pane.id),
    tostring(ok),
    tostring(focus_err)
  ))

  if not ok then
    return nil, focus_err
  end

  return true
end

function M.focus_index_and_hold_fn(index, deps, config)
  local focus_impl = deps and deps.focus_index or M.focus_index
  local ok, err = focus_impl(index, deps, config or M.config)
  if not ok then
    return nil, err
  end

  local merged_config = config or M.config or DEFAULT_CONFIG
  local delay_us =
    merged_config and
    merged_config.bridge and
    merged_config.bridge.focus_to_fn_delay_us or
    DEFAULT_CONFIG.bridge.focus_to_fn_delay_us

  local sleep_ok, sleep_err = sleep_microseconds(delay_us, deps)
  if not sleep_ok then
    return nil, sleep_err
  end

  local bridge = deps and deps.fn_bridge or fn_bridge
  local state = deps and deps.fn_state or M.fn_state
  return bridge.hold(state, deps)
end

function M.focus_index_wait_for_ax(index, deps, config)
  local merged_config = config or M.config or DEFAULT_CONFIG
  local numeric_index = tonumber(index)
  if not numeric_index or numeric_index < 1 or numeric_index > 10 then
    return nil, "invalid pane index"
  end

  local target_pane, target_err = lookup_pane(numeric_index, deps)
  if not target_pane then
    return nil, target_err
  end

  local listing, listing_err = list_current_terminals(deps)
  if not listing then
    return nil, listing_err
  end

  local already_focused = tostring(listing.focused) == tostring(target_pane.id)
  local probe = deps and deps.focus_probe or focus_probe
  local baseline_snapshot = nil

  if not already_focused then
    baseline_snapshot, target_err = probe.read_snapshot(deps)
    if not baseline_snapshot then
      return nil, target_err
    end
  end

  local focus_impl = deps and deps.focus_index or M.focus_index
  local ok, err = focus_impl(numeric_index, deps, merged_config)
  if not ok then
    return nil, err
  end

  if already_focused then
    local snapshot, snapshot_err = probe.read_snapshot(deps)
    if not snapshot then
      return nil, snapshot_err
    end

    append_ax_focus_log(string.format(
      "already_focused signature=%s %s",
      tostring(snapshot.signature),
      probe.describe_snapshot(snapshot)
    ))

    return {
      attempt = 0,
      elapsed_us = 0,
      stable_count = 0,
      previous_signature = snapshot.signature,
      signature = snapshot.signature,
      snapshot = snapshot,
      already_focused = true,
    }
  end

  local probe_result, probe_err = wait_for_ax_focus_change(baseline_snapshot, deps, merged_config)
  if not probe_result then
    return nil, probe_err
  end

  local delay_us =
    merged_config.bridge and
    merged_config.bridge.focus_to_fn_delay_us or
    DEFAULT_CONFIG.bridge.focus_to_fn_delay_us

  local sleep_ok, sleep_err = sleep_microseconds(delay_us, deps)
  if not sleep_ok then
    return nil, sleep_err
  end

  append_ax_focus_log(string.format(
    "post_focus_delay elapsed_us=%s signature=%s",
    tostring(delay_us),
    tostring(probe_result.signature)
  ))

  local click_point_target = center_point_for_frame(target_pane.frame)
  if click_point_target then
    local click_ok, click_err = click_point(click_point_target, deps)
    if not click_ok then
      return nil, click_err
    end

    append_ax_focus_log(string.format(
      "pane_refocus_click point=%d,%d signature=%s",
      click_point_target.x,
      click_point_target.y,
      tostring(probe_result.signature)
    ))

    local click_settle_us =
      merged_config.bridge and
      merged_config.bridge.pane_refocus_click_settle_us or
      80000

    local click_sleep_ok, click_sleep_err = sleep_microseconds(click_settle_us, deps)
    if not click_sleep_ok then
      return nil, click_sleep_err
    end

    append_ax_focus_log(string.format(
      "pane_refocus_click_settle elapsed_us=%s signature=%s",
      tostring(click_settle_us),
      tostring(probe_result.signature)
    ))
  end

  local speech_ready_delay_us =
    merged_config.bridge and
    merged_config.bridge.speech_ready_delay_us or
    DEFAULT_CONFIG.bridge.speech_ready_delay_us

  local speech_sleep_ok, speech_sleep_err = sleep_microseconds(speech_ready_delay_us, deps)
  if not speech_sleep_ok then
    return nil, speech_sleep_err
  end

  append_ax_focus_log(string.format(
    "speech_ready_delay elapsed_us=%s signature=%s",
    tostring(speech_ready_delay_us),
    tostring(probe_result.signature)
  ))

  return probe_result
end

function M.focus_index_wait_for_ax_and_hold_fn(index, deps, config)
  local merged_config = config or M.config or DEFAULT_CONFIG
  local probe_result, probe_err = M.focus_index_wait_for_ax(index, deps, merged_config)
  if not probe_result then
    return nil, probe_err
  end

  local bridge = deps and deps.fn_bridge or fn_bridge
  local state = deps and deps.fn_state or M.fn_state
  return bridge.hold(state, deps)
end

function M.release_fn(deps)
  local bridge = deps and deps.fn_bridge or fn_bridge
  local state = deps and deps.fn_state or M.fn_state
  return bridge.release(state, deps)
end

function M.start(config)
  if not hs or not hs.urlevent then
    error("ghostty_remote requires Hammerspoon runtime")
  end

  M.config = merge_config(config)
  M.cache_state = pane_cache.new_state()
  M.fn_state = fn_bridge.new_state()

  hs.urlevent.bind(M.config.event_name, function(_, params)
    local ok, err = M.focus_index(params and params.index, nil, M.config)
    append_log(string.format(
      "url_event event=%s index=%s ok=%s err=%s",
      tostring(M.config.event_name),
      tostring(params and params.index),
      tostring(ok),
      tostring(err)
    ))
  end)

  M.start_cache_polling(M.config)
  M.schedule_cache_refresh(nil, M.config, "start")
end

return M
