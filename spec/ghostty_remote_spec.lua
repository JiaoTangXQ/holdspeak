local remote = require("ghostty_remote")

assert(type(remote.focus_index) == "function", "focus_index should exist")
assert(type(remote.focus_index_and_hold_fn) == "function", "focus_index_and_hold_fn should exist")
assert(type(remote.focus_index_wait_for_ax) == "function", "focus_index_wait_for_ax should exist")
assert(type(remote.focus_index_wait_for_ax_and_hold_fn) == "function", "focus_index_wait_for_ax_and_hold_fn should exist")
assert(type(remote.release_fn) == "function", "release_fn should exist")

do
  local calls = {}

  local ok, err = remote.focus_index(3, {
    lookup = function(index, config)
      calls.index = index
      calls.config = config
      return { id = "pane-3" }
    end,
    focus = function(terminal_id)
      calls.terminal_id = terminal_id
      return true
    end,
  }, {
    discovery = {
      row_tolerance = 20,
    },
  })

  assert(ok == true, "focus_index should return success when a pane is found")
  assert(err == nil, "focus_index should not return an error on success")
  assert(calls.index == 3, "focus_index should pass the requested pane index to cache lookup")
  assert(calls.terminal_id == "pane-3", "focus_index should focus the discovered terminal")
  assert(calls.config.row_tolerance == 20, "focus_index should forward discovery config")
end

do
  local ok, err = remote.focus_index(4, {
    lookup = function(index, config)
      return nil, "pane cache unavailable"
    end,
    focus = function()
      error("focus should not be called when the pane cache misses")
    end,
  }, {
    discovery = {
      row_tolerance = 20,
    },
  })

  assert(ok == nil, "focus_index should fail when the pane cache is unavailable")
  assert(err == "pane cache unavailable", "focus_index should surface pane cache misses")
end

do
  local ok, err = remote.focus_index("x", {
    lookup = function()
      error("lookup should not be called for invalid index")
    end,
    focus = function()
      error("focus should not be called for invalid index")
    end,
  }, {})

  assert(ok == nil, "focus_index should reject invalid pane indexes")
  assert(err == "invalid pane index", "focus_index should explain invalid pane index failures")
end

do
  local state = {
    signature = nil,
    panes_by_index = {},
    pending_signature = nil,
    refresh_in_progress = false,
  }

  local ok, err = remote.refresh_cache({
    cache_state = state,
    is_frontmost = function()
      return true
    end,
    list = function()
      return {
        terminals = { "pane-a", "pane-b" },
      }
    end,
    discover = function(config)
      assert(config.row_tolerance == 22, "refresh_cache should forward discovery config")
      return {
        { id = "pane-1" },
        { id = "pane-2" },
      }
    end,
  }, {
    discovery = {
      row_tolerance = 22,
    },
  })

  assert(ok == true, "refresh_cache should store discovered panes")
  assert(err == nil, "refresh_cache should not return an error on success")
  assert(state.signature == "pane-a\30pane-b", "refresh_cache should persist the current listing signature")
  assert(state.panes_by_index[1].id == "pane-1", "refresh_cache should store the first discovered pane")
end

do
  local calls = {}

  local ok, err = remote.focus_index_and_hold_fn(2, {
    focus_index = function(index, deps, config)
      calls.focus_index = index
      return true
    end,
    sleep = function(delay_us)
      calls.delay_us = delay_us
    end,
    fn_bridge = {
      hold = function(state, deps)
        calls.hold = true
        return true
      end,
    },
    fn_state = {},
  }, {
    bridge = {
      focus_to_fn_delay_us = 220000,
    },
  })

  assert(ok == true, "focus_index_and_hold_fn should succeed when focus and fn hold succeed")
  assert(err == nil, "focus_index_and_hold_fn should not return an error on success")
  assert(calls.focus_index == 2, "focus_index_and_hold_fn should focus the requested pane index")
  assert(calls.delay_us == 220000, "focus_index_and_hold_fn should wait before pressing fn")
  assert(calls.hold == true, "focus_index_and_hold_fn should press fn after focusing")
end

do
  local calls = {}
  local phase = "baseline"
  calls.order = {}
  calls.delays = {}
  calls.clicks = {}

  local ok, err = remote.focus_index_wait_for_ax(2, {
    list = function()
      return {
        focused = "pane-1",
        terminals = { "pane-1", "pane-2" },
      }
    end,
    lookup = function(index, config)
      calls.lookup = index
      return {
        id = "pane-2",
        frame = {
          x = 100,
          y = 200,
          w = 400,
          h = 300,
        },
      }
    end,
    focus_index = function(index, deps, config)
      calls.order[#calls.order + 1] = "focus_index"
      calls.focus_index = index
      phase = "candidate"
      return true
    end,
    focus_probe = {
      read_snapshot = function(deps)
        calls.order[#calls.order + 1] = "read_snapshot"
        calls.read_snapshot = true
        return {
          signature = phase,
          role = "AXTextArea",
        }
      end,
      wait_for_stable_change = function(previous_signature, options, wait_deps)
        calls.order[#calls.order + 1] = "wait_for_stable_change"
        calls.previous_signature = previous_signature
        calls.stable_samples = options.stable_samples
        wait_deps.log_probe_sample({
          attempt = 1,
          elapsed_us = 0,
          stable_count = 1,
          changed = true,
          signature = "candidate",
          snapshot = {
            signature = "candidate",
            role = "AXTextArea",
          },
        })
        return {
          attempt = 3,
          elapsed_us = 40000,
          stable_count = 3,
          previous_signature = previous_signature,
          signature = "candidate",
          snapshot = {
            signature = "candidate",
            role = "AXTextArea",
          },
        }
      end,
      describe_snapshot = function(snapshot)
        return string.format("signature=%s role=%s", tostring(snapshot.signature), tostring(snapshot.role))
      end,
    },
    sleep = function(delay_us)
      calls.delays[#calls.delays + 1] = delay_us
    end,
    click = function(point)
      calls.clicks[#calls.clicks + 1] = point
      return true
    end,
  }, {
    bridge = {
      ax_focus_probe = {
        stable_samples = 3,
      },
      focus_to_fn_delay_us = 220000,
      pane_refocus_click_settle_us = 80000,
      speech_ready_delay_us = 250000,
    },
  })

  assert(ok ~= nil, "focus_index_wait_for_ax should return probe details when AX focus changes")
  assert(err == nil, "focus_index_wait_for_ax should not return an error on success")
  assert(ok.signature == "candidate", "focus_index_wait_for_ax should surface the stabilized AX signature")
  assert(calls.lookup == 2, "focus_index_wait_for_ax should resolve the requested pane before focus")
  assert(calls.focus_index == 2, "focus_index_wait_for_ax should focus the requested pane index")
  assert(calls.read_snapshot == true, "focus_index_wait_for_ax should capture the pre-focus AX baseline")
  assert(calls.order[1] == "read_snapshot", "focus_index_wait_for_ax should capture the AX baseline before changing panes")
  assert(calls.order[2] == "focus_index", "focus_index_wait_for_ax should focus the requested pane after capturing the baseline")
  assert(calls.previous_signature == "baseline", "focus_index_wait_for_ax should wait for a changed AX focus signature from the pre-focus snapshot")
  assert(calls.stable_samples == 3, "focus_index_wait_for_ax should forward probe options")
  assert(calls.clicks[1].x == 300 and calls.clicks[1].y == 350, "focus_index_wait_for_ax should click the center of the target pane to commit real input focus")
  assert(calls.delays[1] == 220000, "focus_index_wait_for_ax should wait for focus settling before returning")
  assert(calls.delays[2] == 80000, "focus_index_wait_for_ax should wait briefly after the refocus click")
  assert(calls.delays[3] == 250000, "focus_index_wait_for_ax should add an extra speech readiness delay after cross-pane focus succeeds")
end

do
  local calls = {}

  local detail, err = remote.focus_index_wait_for_ax(1, {
    list = function()
      return {
        focused = "pane-1",
        terminals = { "pane-1", "pane-2" },
      }
    end,
    lookup = function(index, config)
      calls.lookup = index
      return {
        id = "pane-1",
      }
    end,
    focus_index = function(index, deps, config)
      calls.focus_index = index
      return true
    end,
    focus_probe = {
      read_snapshot = function(deps)
        calls.read_snapshot = true
        return {
          signature = "already-focused",
          role = "AXTextArea",
        }
      end,
      wait_for_stable_change = function()
        error("wait_for_stable_change should not be called when the target pane is already focused")
      end,
      describe_snapshot = function(snapshot)
        return string.format("signature=%s role=%s", tostring(snapshot.signature), tostring(snapshot.role))
      end,
    },
  }, {})

  assert(detail ~= nil, "focus_index_wait_for_ax should still succeed when the target pane is already focused")
  assert(err == nil, "focus_index_wait_for_ax should not return an error when the target pane is already focused")
  assert(calls.lookup == 1, "focus_index_wait_for_ax should inspect the requested pane before deciding whether focus must change")
  assert(calls.focus_index == 1, "focus_index_wait_for_ax should still run the focus path for the target pane")
  assert(calls.read_snapshot == true, "focus_index_wait_for_ax should capture the current AX snapshot when already focused")
  assert(detail.signature == "already-focused", "focus_index_wait_for_ax should surface the current AX signature for already-focused panes")
  assert(detail.already_focused == true, "focus_index_wait_for_ax should mark already-focused success explicitly")
end

do
  local calls = {}
  calls.delays = {}
  calls.clicks = {}

  local ok, err = remote.focus_index_wait_for_ax_and_hold_fn(2, {
    list = function()
      return {
        focused = "pane-1",
        terminals = { "pane-1", "pane-2" },
      }
    end,
    lookup = function(index, config)
      calls.lookup = index
      return {
        id = "pane-2",
        frame = {
          x = 20,
          y = 40,
          w = 200,
          h = 100,
        },
      }
    end,
    focus_index = function(index, deps, config)
      calls.focus_index = index
      return true
    end,
    sleep = function(delay_us)
      calls.delays[#calls.delays + 1] = delay_us
    end,
    click = function(point)
      calls.clicks[#calls.clicks + 1] = point
      return true
    end,
    focus_probe = {
      read_snapshot = function(deps)
        calls.read_snapshot = true
        return {
          signature = "baseline",
          role = "AXTextArea",
        }
      end,
      wait_for_stable_change = function(previous_signature, options, wait_deps)
        calls.previous_signature = previous_signature
        calls.stable_samples = options.stable_samples
        wait_deps.log_probe_sample({
          attempt = 1,
          elapsed_us = 0,
          stable_count = 1,
          changed = true,
          signature = "candidate",
          snapshot = {
            signature = "candidate",
            role = "AXTextArea",
          },
        })
        return {
          attempt = 3,
          elapsed_us = 40000,
          stable_count = 3,
          previous_signature = previous_signature,
          signature = "candidate",
          snapshot = {
            signature = "candidate",
            role = "AXTextArea",
          },
        }
      end,
      describe_snapshot = function(snapshot)
        return string.format("signature=%s role=%s", tostring(snapshot.signature), tostring(snapshot.role))
      end,
    },
    fn_bridge = {
      hold = function(state, deps)
        calls.hold = true
        return true
      end,
    },
    fn_state = {},
  }, {
    bridge = {
      focus_to_fn_delay_us = 220000,
      pane_refocus_click_settle_us = 80000,
      speech_ready_delay_us = 250000,
      ax_focus_probe = {
        stable_samples = 3,
      },
    },
  })

  assert(ok == true, "focus_index_wait_for_ax_and_hold_fn should succeed when AX focus changes and fn hold succeeds")
  assert(err == nil, "focus_index_wait_for_ax_and_hold_fn should not return an error on success")
  assert(calls.lookup == 2, "focus_index_wait_for_ax_and_hold_fn should resolve the requested pane before focus")
  assert(calls.focus_index == 2, "focus_index_wait_for_ax_and_hold_fn should focus the requested pane index")
  assert(calls.read_snapshot == true, "focus_index_wait_for_ax_and_hold_fn should capture the pre-focus AX baseline")
  assert(calls.previous_signature == "baseline", "focus_index_wait_for_ax_and_hold_fn should wait for a changed AX focus signature")
  assert(calls.stable_samples == 3, "focus_index_wait_for_ax_and_hold_fn should forward probe options")
  assert(calls.clicks[1].x == 120 and calls.clicks[1].y == 90, "focus_index_wait_for_ax_and_hold_fn should click the target pane center before pressing fn")
  assert(calls.delays[1] == 220000, "focus_index_wait_for_ax_and_hold_fn should still wait for focus settling before pressing fn")
  assert(calls.delays[2] == 80000, "focus_index_wait_for_ax_and_hold_fn should wait briefly after the refocus click")
  assert(calls.delays[3] == 250000, "focus_index_wait_for_ax_and_hold_fn should wait for cross-pane speech readiness before pressing fn")
  assert(calls.hold == true, "focus_index_wait_for_ax_and_hold_fn should press fn after AX focus stabilizes")
end

do
  local state = {}
  local calls = {}

  local ok, err = remote.release_fn({
    fn_bridge = {
      release = function(fn_state, deps)
        calls.release = true
        return true
      end,
    },
    fn_state = state,
  })

  assert(ok == true, "release_fn should succeed when fn release succeeds")
  assert(err == nil, "release_fn should not return an error on success")
  assert(calls.release == true, "release_fn should delegate to the fn bridge")
end
