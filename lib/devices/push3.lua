-- midigrid/lib/devices/push3.lua
-- Ableton Push 3 device using SysEx palette control for LED brightness.
--
-- The Push has no SysEx command for setting individual LED colors directly.
-- Instead, LEDs are addressed via Note On (pads) and CC (buttons), where the
-- velocity/value selects a palette index (0-127). We use SysEx 0x03 to
-- reprogram palette entries 0-15 to match our 16-level rgb_lut, giving us
-- full RGB color control through the same palette files used by Launchpad Gen3.
--
-- Palette changes are detected by table reference comparison: when midigrid
-- assigns a new rgb_lut, the next refresh reconfigures the Push hardware.
--
-- SysEx reference: https://github.com/Ableton/push-interface
-- Push 3 protocol: https://github.com/danielknng/push3-protocol-docs

local push = include('midigrid/lib/devices/generic_device')

-- Push 3 SysEx header (same as Push 2: F0 00 21 1D 01 01)
local SYSEX = { 0xF0, 0x00, 0x21, 0x1D, 0x01, 0x01 }

-- SysEx command IDs
local CMD_SET_PALETTE     = 0x03
local CMD_REAPPLY_PALETTE = 0x05
local CMD_SET_BRIGHTNESS  = 0x06

-- Pad note mapping (identical to Push 2: note 36 bottom-left to 99 top-right)
push.grid_notes = {
  {92, 93, 94, 95, 96, 97, 98, 99},
  {84, 85, 86, 87, 88, 89, 90, 91},
  {76, 77, 78, 79, 80, 81, 82, 83},
  {68, 69, 70, 71, 72, 73, 74, 75},
  {60, 61, 62, 63, 64, 65, 66, 67},
  {52, 53, 54, 55, 56, 57, 58, 59},
  {44, 45, 46, 47, 48, 49, 50, 51},
  {36, 37, 38, 39, 40, 41, 42, 43}
}

-- Identity brightness map: z value (0-15) passes through as palette index.
-- Our SysEx-configured palette entries 0-15 contain the actual brightness
-- levels, so no mapping table is needed.
push.brightness_map = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15}

push.rotate_second_device = false

-- Set of allowed note numbers (grid pads). Populated in _init after
-- potential rotation so it stays in sync with grid_notes.
push._allowed_notes = nil

-- Set of allowed CC numbers (aux buttons only). Built once here.
push._allowed_ccs = nil

-- Default RGB palette: vintage_amber (warm monome-style tone)
-- Overridden by midigrid palette system when a mod palette is selected.
-- Same palette file format used by Launchpad Gen3 devices.
push.rgb_lut = {
  {  0,   0,   0},   -- z=0:  off
  {  8,   2,   0},   -- z=1
  { 16,   4,   0},   -- z=2
  { 24,   8,   0},   -- z=3
  { 32,  12,   0},   -- z=4
  { 40,  18,   0},   -- z=5
  { 50,  24,   0},   -- z=6
  { 60,  32,   2},   -- z=7
  { 70,  40,   4},   -- z=8
  { 80,  50,   8},   -- z=9
  { 90,  60,  12},   -- z=10
  {100,  72,  18},   -- z=11
  {110,  84,  24},   -- z=12
  {118,  96,  32},   -- z=13
  {124, 110,  42},   -- z=14
  {127, 122,  56},   -- z=15: warm white
}

--- Track last-synced palette to detect external changes (table reference).
push._last_configured_lut = nil

push.aux = {}

-- Column aux: Scene/Repeat buttons on right edge (CC 36-43, top to bottom)
push.aux.col = {
  {'cc', 43, 0},
  {'cc', 42, 0},
  {'cc', 41, 0},
  {'cc', 40, 0},
  {'cc', 39, 0},
  {'cc', 38, 0},
  {'cc', 37, 0},
  {'cc', 36, 0}
}

-- Row aux: upper display row (CC 20-27) + navigation arrows for quad switching
push.aux.row = {
  {'cc', 20, 0},
  {'cc', 21, 0},
  {'cc', 22, 0},
  {'cc', 23, 0},
  {'cc', 24, 0},
  {'cc', 25, 0},
  {'cc', 26, 0},
  {'cc', 27, 0},
  {'cc', 44, 0},  -- Left arrow
  {'cc', 45, 0},  -- Right arrow
  {'cc', 46, 0},  -- Up arrow
  {'cc', 47, 0},  -- Down arrow
}

--- Split an 8-bit value into two 7-bit MIDI bytes (low, high).
local function split7(value)
  return value % 128, math.floor(value / 128)
end

--- Build a complete SysEx message with Push header and F7 terminator.
local function sysex_msg(cmd, ...)
  local msg = { table.unpack(SYSEX) }
  msg[#msg + 1] = cmd
  local args = { ... }
  for _, v in ipairs(args) do
    msg[#msg + 1] = v
  end
  msg[#msg + 1] = 0xF7
  return msg
end

--- Configure palette entries 0-15 from rgb_lut.
-- Writes each entry as an RGB color to the Push hardware palette via SysEx 0x03,
-- then reapplies so active LEDs update immediately.
function push:configure_palette()
  local dev = midi.devices[self.midi_id]
  if not dev then return end

  local lut = self.rgb_lut
  for i = 0, 15 do
    local rgb = lut[i + 1]  -- Lua is 1-indexed, Push palette is 0-indexed
    local r, g, b = rgb[1], rgb[2], rgb[3]

    local rl, rh = split7(r)
    local gl, gh = split7(g)
    local bl, bh = split7(b)
    local wl, wh = split7(0)  -- white component = 0

    dev:send(sysex_msg(CMD_SET_PALETTE, i, rl, rh, gl, gh, bl, bh, wl, wh))
  end

  -- SysEx 0x05: Reapply Color Palette (updates all active LEDs with new palette)
  dev:send(sysex_msg(CMD_REAPPLY_PALETTE))

  -- SysEx 0x06: Set global LED brightness to max
  dev:send(sysex_msg(CMD_SET_BRIGHTNESS, 127))

  self._last_configured_lut = lut
end

--- Build whitelist lookup tables for MIDI filtering.
local function build_whitelists(self)
  local notes = {}
  for y = 1, #self.grid_notes do
    for x = 1, #self.grid_notes[y] do
      notes[self.grid_notes[y][x]] = true
    end
  end
  self._allowed_notes = notes

  local ccs = {}
  if self.aux.col then
    for _, btn in ipairs(self.aux.col) do ccs[btn[2]] = true end
  end
  if self.aux.row then
    for _, btn in ipairs(self.aux.row) do ccs[btn[2]] = true end
  end
  self._allowed_ccs = ccs
end

--- Override _init: install MIDI whitelist filter to prevent stray
--- CCs (clock, transport, script events) from lighting hardware buttons.
local _parent_init = push._init
function push:_init(vgrid, device_number)
  _parent_init(self, vgrid, device_number)

  -- Build whitelists after parent init (which may rotate grid_notes)
  build_whitelists(self)

  -- Install send filter: only allow our Note On (pad LEDs),
  -- our CCs (aux button LEDs), and SysEx (palette config).
  -- Everything else is silently dropped.
  local dev = midi.devices[self.midi_id]
  if dev and not dev._push3_filtered then
    local original_send = dev.send
    local allowed_notes = self._allowed_notes
    local allowed_ccs = self._allowed_ccs
    dev.send = function(self_inner, data)
      if type(data) == "table" and #data >= 2 then
        local b1 = data[1]
        if b1 == 0xF0 then
          -- SysEx: always pass through
        elseif b1 >= 0x80 and b1 <= 0x9F then
          -- Note On / Note Off: only allowed grid pad notes
          if not allowed_notes[data[2]] then return end
        elseif b1 >= 0xB0 and b1 <= 0xBF then
          -- CC: only allowed aux button CCs
          if not allowed_ccs[data[2]] then return end
        else
          -- Anything else: drop
          return
        end
      elseif type(data) == "number" then
        if data ~= 0xF0 then return end
      elseif type(data) == "string" then
        if data:byte(1) ~= 0xF0 then return end
      end
      return original_send(self_inner, data)
    end
    dev._push3_filtered = true
    self._midi_dev_patched = dev
    self._original_midi_send = original_send
  end
end

--- Cleanup: restore original MIDI send.
function push:_cleanup()
  if self._midi_dev_patched and self._original_midi_send then
    self._midi_dev_patched.send = self._original_midi_send
    self._midi_dev_patched._push3_filtered = nil
    self._midi_dev_patched = nil
    self._original_midi_send = nil
  end
end

--- Override _reset to configure SysEx palette on device init/connect.
function push:_reset()
  local dev = midi.devices[self.midi_id]
  if not dev then return end
  self:configure_palette()
end

--- Override refresh: detect palette changes and reconfigure hardware.
local _parent_refresh = push.refresh
function push:refresh(quad)
  -- Reconfigure Push hardware palette if rgb_lut was swapped externally
  -- (midigrid flush_palette assigns a new table reference)
  if self.rgb_lut ~= self._last_configured_lut then
    self:configure_palette()
  end
  _parent_refresh(self, quad)
end

--- Override change_quad: force immediate grid redraw on page switch.
function push:change_quad(quad)
  self.current_quad = quad
  self.force_full_refresh = true
  if self.vgrid then
    for _, q in pairs(self.vgrid.quads) do
      q.force_full_redraw = true
    end
    self.vgrid:refresh()
  end
end

--- Auto-create quad switching handlers for left/right arrow buttons.
function push:create_quad_handers(quad_count)  -- match parent spelling
  if quad_count > 1 then
    for q = 1, quad_count do
      self.aux.row_handlers[q + 8] = function(self, val) self:change_quad(q) end
    end
  end
end

return push
