-----------------------------------------------------------------------
-- Launchpad Pro MK3 — SysEx RGB on top of launchpad_rgb inheritance
--
-- Inherits from launchpad_rgb → generic_device for event routing,
-- quad management, aux button handling, and grid rotation.
-- Overrides LED output methods to use SysEx RGB instead of palette
-- velocity, and adds init-time flash/pulse clearing.
--
-- Key features:
--  1. Non-SysEx MIDI blocking (prevents flash/pulse and aux LED artifacts)
--  2. SysEx RGB grid LEDs (palette ported from the original launchpad_rgb)
--  3. SysEx init clearing (flash/pulse/button layers)
--  4. Single batched SysEx for button LEDs (no CC flicker)
-----------------------------------------------------------------------

local launchpad = include('midigrid/lib/devices/launchpad_rgb')

-- Enter Programmer Mode
launchpad.init_device_msg = { 0xf0, 0x00, 0x20, 0x29, 0x02, 0x0e, 0x0e, 0x01, 0xf7 }

launchpad.rotate_second_device = false

launchpad.aux.col = {
  {'cc', 10, 0}, {'cc', 20, 0}, {'cc', 30, 0}, {'cc', 40, 0},
  {'cc', 50, 0}, {'cc', 60, 0}, {'cc', 70, 0}, {'cc', 80, 0}
}
launchpad.aux.row = {
  {'cc', 91, 0}, {'cc', 92, 0}, {'cc', 93, 0}, {'cc', 94, 0},
  {'cc', 95, 0}, {'cc', 96, 0}, {'cc', 97, 0}, {'cc', 98, 0}
}

-----------------------------------------------------------------------
-- Pre-computed tables
-----------------------------------------------------------------------
local grid_leds = {}
do
  for y = 1, 8 do
    for x = 1, 8 do
      grid_leds[#grid_leds + 1] = launchpad.grid_notes[y][x]
    end
  end
end

local all_btn_ccs = {
  10, 20, 30, 40, 50, 60, 70, 80,
  19, 29, 39, 49, 59, 69, 79, 89,
  91, 92, 93, 94, 95, 96, 97, 98,
  90, 99
}

-- Page buttons = top row (aux.row, CC 91-98)

-----------------------------------------------------------------------
-- RGB colour LUT: converted from the LP Pro MK3 hardware palette
--
-- Each entry is the exact RGB colour the original brightness_map
-- produced on the hardware, converted from the firmware's 0-63 range
-- to SysEx MIDI 0-127 range.  This reproduces the palette's warm
-- yellow/amber/white gradient via SysEx RGB, bypassing the flash/pulse
-- layers that caused flickering with palette velocity.
--
-- Original brightness_map: {0, 11, 100, 125, 83, 117, 14, 62,
--                           99, 118, 126, 97, 109, 13, 12, 119}
-----------------------------------------------------------------------
local rgb_lut = {
  {  0,   0,   0},   -- z=0:  off              (palette 0)
  { 32,   8,   0},   -- z=1:  dark red           (palette 11)
  { 28,  20,   0},   -- z=2:  dark amber         (palette 100)
  { 30,  24,   0},   -- z=3:  dark yellow        (palette 125)
  { 20,   8,   0},   -- z=4:  very dark amber    (palette 83)
  { 30,  30,  30},   -- z=5:  gray               (palette 117)
  { 64,  64,   0},   -- z=6:  yellow             (palette 14)
  { 58,  40,   0},   -- z=7:  amber              (palette 62)
  { 64,  44,   2},   -- z=8:  amber              (palette 99)
  { 56,  56,  56},   -- z=9:  gray               (palette 118)
  { 89,  40,   0},   -- z=10: orange             (palette 126)
  { 91,  83,   0},   -- z=11: yellow             (palette 97)
  {127,  95,  18},   -- z=12: bright warm amber  (palette 109)
  {127, 127,   0},   -- z=13: bright yellow      (palette 13)
  {127,  87,  22},   -- z=14: bright amber       (palette 12)
  {111, 127, 127},   -- z=15: warm white         (palette 119)
}

-- (button colors come from rgb_lut via aux state)

-----------------------------------------------------------------------
-- Pre-built SysEx messages for init clearing
-----------------------------------------------------------------------
local flash_clear_sysx
do
  local m = { 0xF0, 0x00, 0x20, 0x29, 0x02, 0x0E, 0x03 }
  for _, led in ipairs(grid_leds) do
    m[#m + 1] = 0x01; m[#m + 1] = led; m[#m + 1] = 0; m[#m + 1] = 0
  end
  m[#m + 1] = 0xF7
  flash_clear_sysx = m
end

local pulse_clear_sysx
do
  local m = { 0xF0, 0x00, 0x20, 0x29, 0x02, 0x0E, 0x03 }
  for _, led in ipairs(grid_leds) do
    m[#m + 1] = 0x02; m[#m + 1] = led; m[#m + 1] = 0
  end
  m[#m + 1] = 0xF7
  pulse_clear_sysx = m
end

local btn_flash_clear_sysx
do
  local m = { 0xF0, 0x00, 0x20, 0x29, 0x02, 0x0E, 0x03 }
  for _, cc in ipairs(all_btn_ccs) do
    m[#m + 1] = 0x01; m[#m + 1] = cc; m[#m + 1] = 0; m[#m + 1] = 0
  end
  m[#m + 1] = 0xF7
  btn_flash_clear_sysx = m
end

local btn_pulse_clear_sysx
do
  local m = { 0xF0, 0x00, 0x20, 0x29, 0x02, 0x0E, 0x03 }
  for _, cc in ipairs(all_btn_ccs) do
    m[#m + 1] = 0x02; m[#m + 1] = cc; m[#m + 1] = 0
  end
  m[#m + 1] = 0xF7
  btn_pulse_clear_sysx = m
end

-----------------------------------------------------------------------
-- Override _init: add MIDI clock blocking
-----------------------------------------------------------------------
local _parent_init = launchpad._init
function launchpad:_init(vgrid, device_number)
  _parent_init(self, vgrid, device_number)

  local dev = midi.devices[self.midi_id]
  if dev then
    local original_send = dev.send
    dev.send = function(self_inner, data)
      -- Block all non-SysEx MIDI: norns may send note_off, CC resets,
      -- or transport messages on clock stop that clear Programmer Mode
      -- button LEDs.  All our output is SysEx, so anything else is
      -- unwanted.
      if type(data) == "table" then
        if data[1] ~= 0xF0 then return end
      elseif type(data) == "number" then
        if data ~= 0xF0 then return end
      end
      return original_send(self_inner, data)
    end
  end
end

-----------------------------------------------------------------------
-- Override _reset: add SysEx flash/pulse/button clearing
-----------------------------------------------------------------------
local _parent_reset = launchpad._reset
function launchpad:_reset()
  _parent_reset(self)

  local dev = midi.devices[self.midi_id]
  if not dev then return end

  -- Grid: clear flash + pulse layers
  dev:send(flash_clear_sysx)
  dev:send(pulse_clear_sysx)

  -- Buttons: clear static RGB, flash, pulse via SysEx
  local bm = { 0xF0, 0x00, 0x20, 0x29, 0x02, 0x0E, 0x03 }
  for _, cc in ipairs(all_btn_ccs) do
    bm[#bm + 1] = 0x03; bm[#bm + 1] = cc
    bm[#bm + 1] = 0; bm[#bm + 1] = 0; bm[#bm + 1] = 0
  end
  bm[#bm + 1] = 0xF7
  dev:send(bm)

  dev:send(btn_flash_clear_sysx)
  dev:send(btn_pulse_clear_sysx)

  -- Light aux buttons immediately (page indicators, etc.)
  self:update_aux()
end

-----------------------------------------------------------------------
-- Override _update_led: use SysEx RGB instead of palette velocity
-----------------------------------------------------------------------
function launchpad._update_led(self, x, y, z)
  if y < 1 or #self.grid_notes < y or x < 1 or #self.grid_notes[y] < x then
    return
  end
  local led = self.grid_notes[y][x]
  local rgb = rgb_lut[z + 1]
  local dev = midi.devices[self.midi_id]
  if dev then
    dev:send({
      0xF0, 0x00, 0x20, 0x29, 0x02, 0x0E, 0x03,
      0x03, led, rgb[1], rgb[2], rgb[3],
      0xF7
    })
  end
end

-----------------------------------------------------------------------
-- Helper: append aux button RGB specs to a SysEx message
-----------------------------------------------------------------------
local function append_aux_specs(self, m)
  local function add_btn(button)
    if button[3] == nil then return end  -- skip handlers
    local rgb = rgb_lut[button[3] + 1]
    m[#m + 1] = 0x03
    m[#m + 1] = button[2]   -- CC number = LED index
    m[#m + 1] = rgb[1]
    m[#m + 1] = rgb[2]
    m[#m + 1] = rgb[3]
  end
  if self.aux.row then
    for _, button in ipairs(self.aux.row) do add_btn(button) end
  end
  if self.aux.col then
    for _, button in ipairs(self.aux.col) do add_btn(button) end
  end
end

-----------------------------------------------------------------------
-- Override refresh: combined grid + aux SysEx (single atomic update)
--
-- Grid and aux button specs are sent in one SysEx message to prevent
-- the LP from briefly blanking aux LEDs between two separate messages.
-----------------------------------------------------------------------
function launchpad:refresh(quad)
  if quad.id ~= self.current_quad then
    return
  end

  -- Update aux button states before building SysEx
  self:update_quad_btn_aux()

  if self.refresh_counter > 9 then
    self.force_full_refresh = true
    self.refresh_counter = 0
  end

  local dev = midi.devices[self.midi_id]
  if dev then
    if self.force_full_refresh then
      local m = { 0xF0, 0x00, 0x20, 0x29, 0x02, 0x0E, 0x03 }
      for y = 1, quad.height do
        for x = 1, quad.width do
          local led = self.grid_notes[y][x]
          local rgb = rgb_lut[quad.buffer[x][y] + 1]
          m[#m + 1] = 0x03
          m[#m + 1] = led
          m[#m + 1] = rgb[1]; m[#m + 1] = rgb[2]; m[#m + 1] = rgb[3]
        end
      end
      append_aux_specs(self, m)
      m[#m + 1] = 0xF7
      dev:send(m)
      self.force_full_refresh = false
    else
      if quad.frozen_update and quad.frozen_update.update_count > 0 then
        local m = { 0xF0, 0x00, 0x20, 0x29, 0x02, 0x0E, 0x03 }
        for u = 1, quad.frozen_update.update_count do
          local x = quad.frozen_update.updates_x[u]
          local y = quad.frozen_update.updates_y[u]
          local led = self.grid_notes[y][x]
          local rgb = rgb_lut[quad.buffer[x][y] + 1]
          m[#m + 1] = 0x03
          m[#m + 1] = led
          m[#m + 1] = rgb[1]; m[#m + 1] = rgb[2]; m[#m + 1] = rgb[3]
        end
        append_aux_specs(self, m)
        m[#m + 1] = 0xF7
        dev:send(m)
      else
        -- No grid changes, still push aux button states
        self:send_aux_sysx(dev)
      end
      self.refresh_counter = self.refresh_counter + 1
    end
  end
end

-----------------------------------------------------------------------
-- Standalone aux SysEx sender (used by _reset and no-delta refresh)
--
-- Builds and sends a SysEx with all aux button RGB specs.
-- Assumes update_quad_btn_aux() has already been called if needed.
-----------------------------------------------------------------------
function launchpad:send_aux_sysx(dev)
  local m = { 0xF0, 0x00, 0x20, 0x29, 0x02, 0x0E, 0x03 }
  append_aux_specs(self, m)
  m[#m + 1] = 0xF7
  dev:send(m)
end

-----------------------------------------------------------------------
-- Override update_aux: for external callers (change_quad, etc.)
-----------------------------------------------------------------------
function launchpad:update_aux()
  self:update_quad_btn_aux()
  local dev = midi.devices[self.midi_id]
  if dev then self:send_aux_sysx(dev) end
end

-----------------------------------------------------------------------
-- Override change_quad: force immediate grid redraw
-----------------------------------------------------------------------
function launchpad:change_quad(quad)
  self.current_quad = quad
  self.force_full_refresh = true
  if self.vgrid then
    for _, q in pairs(self.vgrid.quads) do
      q.force_full_redraw = true
    end
    self.vgrid:refresh()
  end
end

return launchpad
