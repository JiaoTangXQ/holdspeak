local focus_probe = require("lib.focus_probe")

assert(type(focus_probe.signature_for_snapshot) == "function", "focus_probe.signature_for_snapshot should exist")
assert(type(focus_probe.read_snapshot) == "function", "focus_probe.read_snapshot should exist")
assert(type(focus_probe.wait_for_stable_change) == "function", "focus_probe.wait_for_stable_change should exist")

do
  local signature = focus_probe.signature_for_snapshot({
    role = "AXTextArea",
    subrole = "AXStandardWindow",
    title = "Shell",
    description = "Focused terminal",
    path_length = 4,
    frame = {
      x = 10,
      y = 20,
      w = 300,
      h = 200,
    },
  })

  assert(
    signature == "AXTextArea|AXStandardWindow|Shell|Focused terminal|4|10,20,300,200",
    "signature_for_snapshot should include role metadata and frame coordinates"
  )
end

do
  local snapshot, err = focus_probe.read_snapshot({
    get_element = function()
      return "focused-element"
    end,
    snapshot_for_element = function(element)
      assert(element == "focused-element", "read_snapshot should pass the focused element to the snapshot builder")
      return {
        role = "AXTextArea",
        frame = {
          x = 1,
          y = 2,
          w = 3,
          h = 4,
        },
      }
    end,
  })

  assert(snapshot ~= nil, "read_snapshot should return a snapshot when the focused element exists")
  assert(err == nil, "read_snapshot should not return an error on success")
  assert(snapshot.signature == "AXTextArea|||||1,2,3,4", "read_snapshot should attach a derived signature")
end

do
  local sequence = {
    { marker = "baseline" },
    { marker = "candidate" },
    { marker = "candidate" },
    { marker = "candidate" },
  }
  local index = 0
  local slept = {}
  local samples = {}
  local baseline_signature = "AXTextArea|||baseline||0,0,100,40"

  local result, err = focus_probe.wait_for_stable_change(baseline_signature, {
    poll_interval_us = 10000,
    timeout_us = 50000,
    stable_samples = 3,
  }, {
    sleep = function(delay_us)
      slept[#slept + 1] = delay_us
    end,
    get_element = function()
      index = index + 1
      return sequence[index]
    end,
    snapshot_for_element = function(element)
      return {
        role = "AXTextArea",
        description = element.marker,
        frame = {
          x = 0,
          y = 0,
          w = 100,
          h = 40,
        },
      }
    end,
    log_probe_sample = function(sample)
      samples[#samples + 1] = sample
    end,
  })

  assert(result ~= nil, "wait_for_stable_change should succeed when a changed signature stabilizes")
  assert(err == nil, "wait_for_stable_change should not return an error on success")
  assert(
    result.signature == "AXTextArea|||candidate||0,0,100,40",
    "wait_for_stable_change should report the stabilized signature"
  )
  assert(result.stable_count == 3, "wait_for_stable_change should track the required stable sample count")
  assert(#slept == 3, "wait_for_stable_change should sleep between unsuccessful samples")
  assert(samples[1].changed == false, "wait_for_stable_change should treat the baseline sample as unchanged")
  assert(samples[2].changed == true, "wait_for_stable_change should mark changed samples")
end

do
  local attempts = 0
  local baseline_signature = "AXTextArea|||baseline||1,1,1,1"

  local result, err, detail = focus_probe.wait_for_stable_change(baseline_signature, {
    poll_interval_us = 5000,
    timeout_us = 10000,
    stable_samples = 2,
  }, {
    sleep = function()
    end,
    get_element = function()
      attempts = attempts + 1
      return {
        marker = "baseline",
      }
    end,
    snapshot_for_element = function(element)
      return {
        role = "AXTextArea",
        description = element.marker,
        frame = {
          x = 1,
          y = 1,
          w = 1,
          h = 1,
        },
      }
    end,
  })

  assert(result == nil, "wait_for_stable_change should fail when focus never changes")
  assert(err == "AX focus did not change and stabilize", "wait_for_stable_change should explain timeouts")
  assert(detail ~= nil, "wait_for_stable_change should return timeout details")
  assert(detail.attempt == 3, "wait_for_stable_change should keep sampling until timeout is reached")
end
