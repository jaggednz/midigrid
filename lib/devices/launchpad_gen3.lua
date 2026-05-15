-----------------------------------------------------------------------
-- Launchpad Gen 3 — Shared SysEx RGB driver
--
-- Supports: Launchpad X, Launchpad Mini MK3, Launchpad Pro MK3
--
-- Inherits from launchpad_rgb → generic_device for event routing,
-- quad management, aux button handling, and grid rotation.
-- Overrides LED output to use SysEx RGB instead of palette velocity,
-- adds init-time flash/pulse clearing, and non-SysEx MIDI blocking.
--
-- Key features inherited from the Launchpad Pro MK3 rewrite:
--  1. Non-SysEx MIDI blocking (prevents flash/pulse and aux LED artifacts)
--  2. SysEx RGB grid LEDs (warm palette ported from launchpad_rgb)
--  3. SysEx init clearing (flash/pulse/button layers)
--  4. Single batched SysEx for grid + aux button LEDs
--  5. Immediate redraw on quad change
--
-- Child drivers MUST set before _init() is called:
--   self.sysex_device_id   -- 0x0C (X), 0x0D (Mini MK3), or 0x0E (Pro MK3)
--   self.init_device_msg   -- SysEx message to enter Programmer mode
--   self.aux.col           -- aux column buttons
--   self.aux.row           -- aux row buttons
--   self._extra_btn_ccs    -- (optional) extra button CCs to clear, e.g. {90, 99}
--
-- Child drivers MAY override before _init() is called:
--   self.rgb_lut           -- custom 16-entry RGB colour palette (z=0..15)
-----------------------------------------------------------------------

local launchpad = include('midigrid/lib/devices/launchpad_rgb')

-----------------------------------------------------------------------
-- RGB colour LUT: converted from the LP hardware palette
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
-- Default RGB colour palette (warm amber/yellow/white)
-- Child drivers can override self.rgb_lut before calling _init().
local default_rgb_lut = {
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

launchpad.rgb_lut = default_rgb_lut

-- Clamp a z/brightness value to valid rgb_lut index (1–16)
local function clamp_rgb_index(z)
  if type(z) ~= "number" then return 1 end
  if z < 0 then return 1 end
  if z > 15 then return 16 end
  return z + 1
end

-----------------------------------------------------------------------
-- Helper: collect all button CCs from aux arrays + extras
-----------------------------------------------------------------------
local function get_all_btn_ccs(self)
  local ccs = {}
  if self.aux.col then
    for _, btn in ipairs(self.aux.col) do
      ccs[#ccs + 1] = btn[2]
    end
  end
  if self.aux.row then
    for _, btn in ipairs(self.aux.row) do
      ccs[#ccs + 1] = btn[2]
    end
  end
  if self._extra_btn_ccs then
    for _, cc in ipairs(self._extra_btn_ccs) do
      ccs[#ccs + 1] = cc
    end
  end
  return ccs
end

-----------------------------------------------------------------------
-- Override _init: build SysEx header and add MIDI send blocking
-----------------------------------------------------------------------
local _parent_init = launchpad._init
function launchpad:_init(vgrid, device_number)
  assert(self.sysex_device_id,
    "launchpad_gen3: sysex_device_id not set by child driver")

  -- Build the SysEx RGB header from the device-specific ID
  self.syx_rgb = { 0xF0, 0x00, 0x20, 0x29, 0x02, self.sysex_device_id, 0x03 }

  -- Placeholder: _parent_init calls _reset which iterates _grid_leds.
  -- Must exist before _parent_init to avoid ipairs(nil) crash.
  self._grid_leds = {}

  _parent_init(self, vgrid, device_number)

  -- Now populate after parent init (which may rotate grid_notes)
  for y = 1, 8 do
    for x = 1, 8 do
      self._grid_leds[#self._grid_leds + 1] = self.grid_notes[y][x]
    end
  end

  -- Block all non-SysEx MIDI: norns may send note_off, CC resets,
  -- or transport messages on clock stop that interfere with
  -- Programmer Mode button LEDs.  All our output is SysEx, so
  -- anything else is unwanted.
  local dev = midi.devices[self.midi_id]
  if dev and not dev._gen3_filtered then
    local original_send = dev.send
    dev.send = function(self_inner, data)
      if type(data) == "table" then
        if data[1] ~= 0xF0 then return end
      elseif type(data) == "number" then
        if data ~= 0xF0 then return end
      elseif type(data) == "string" then
        if data:byte(1) ~= 0xF0 then return end
      end
      return original_send(self_inner, data)
    end
    dev._gen3_filtered = true
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

  local syx = self.syx_rgb

  -- Grid: clear flash layer (type 0x01, colours A=0 B=0)
  do
    local m = { table.unpack(syx) }
    for _, led in ipairs(self._grid_leds) do
      m[#m + 1] = 0x01; m[#m + 1] = led; m[#m + 1] = 0; m[#m + 1] = 0
    end
    m[#m + 1] = 0xF7
    dev:send(m)
  end

  -- Grid: clear pulse layer (type 0x02, palette 0)
  do
    local m = { table.unpack(syx) }
    for _, led in ipairs(self._grid_leds) do
      m[#m + 1] = 0x02; m[#m + 1] = led; m[#m + 1] = 0
    end
    m[#m + 1] = 0xF7
    dev:send(m)
  end

  -- Buttons: clear static RGB (type 0x03, R=0 G=0 B=0)
  local btn_ccs = get_all_btn_ccs(self)
  do
    local m = { table.unpack(syx) }
    for _, cc in ipairs(btn_ccs) do
      m[#m + 1] = 0x03; m[#m + 1] = cc
      m[#m + 1] = 0; m[#m + 1] = 0; m[#m + 1] = 0
    end
    m[#m + 1] = 0xF7
    dev:send(m)
  end

  -- Buttons: clear flash layer
  do
    local m = { table.unpack(syx) }
    for _, cc in ipairs(btn_ccs) do
      m[#m + 1] = 0x01; m[#m + 1] = cc; m[#m + 1] = 0; m[#m + 1] = 0
    end
    m[#m + 1] = 0xF7
    dev:send(m)
  end

  -- Buttons: clear pulse layer
  do
    local m = { table.unpack(syx) }
    for _, cc in ipairs(btn_ccs) do
      m[#m + 1] = 0x02; m[#m + 1] = cc; m[#m + 1] = 0
    end
    m[#m + 1] = 0xF7
    dev:send(m)
  end

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
  local rgb = self.rgb_lut[clamp_rgb_index(z)]
  local dev = midi.devices[self.midi_id]
  if dev then
    dev:send({
      table.unpack(self.syx_rgb),
      0x03, led, rgb[1], rgb[2], rgb[3],
      0xF7
    })
  end
end

-----------------------------------------------------------------------
-- Helper: append aux button RGB specs to a SysEx message
-----------------------------------------------------------------------
local function append_aux_specs(self, m)
  local lut = self.rgb_lut
  local function add_btn(button)
    if button[3] == nil or type(button[3]) ~= "number" then return end
    local rgb = lut[clamp_rgb_index(button[3])]
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
-- the device from briefly blanking aux LEDs between two separate messages.
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
      local m = { table.unpack(self.syx_rgb) }
      for y = 1, quad.height do
        for x = 1, quad.width do
          local led = self.grid_notes[y][x]
          local rgb = self.rgb_lut[clamp_rgb_index(quad.buffer[x][y])]
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
        local m = { table.unpack(self.syx_rgb) }
        for u = 1, quad.frozen_update.update_count do
          local x = quad.frozen_update.updates_x[u]
          local y = quad.frozen_update.updates_y[u]
          local led = self.grid_notes[y][x]
          local rgb = self.rgb_lut[clamp_rgb_index(quad.buffer[x][y])]
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
  local m = { table.unpack(self.syx_rgb) }
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
