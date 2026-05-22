-- midigrid/lib/devices/push3.lua
-- Ableton Push 3 device using SysEx palette control for LED brightness.
--
-- Instead of relying on the default Push color palette (like push2 does via
-- velocity+brightness_map), this device configures a custom 16-entry RGB
-- palette via SysEx command 0x03 at init time. This gives precise monome-style
-- amber brightness control across all 16 z-levels.
--
-- Palette entries 0-15 are set to warm amber at linear brightness scale.
-- Note On velocity (0-15) maps directly to these entries, giving a clean
-- brightness ramp without the non-linear color jumps of the default palette.
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

-- Amber base color for the palette (monome-style warm amber)
-- Adjust these to change the grid LED color
local AMBER_R = 255
local AMBER_G = 150
local AMBER_B = 30

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

--- Configure palette entries 0-15 with amber at linear brightness.
-- Each entry maps to a z-level in the grid (0 = off, 15 = full brightness).
function push:configure_palette()
  local dev = midi.devices[self.midi_id]
  if not dev then return end

  for i = 0, 15 do
    local scale = i / 15  -- 0.0 to 1.0
    local r = math.floor(AMBER_R * scale)
    local g = math.floor(AMBER_G * scale)
    local b = math.floor(AMBER_B * scale)

    local rl, rh = split7(r)
    local gl, gh = split7(g)
    local bl, bh = split7(b)
    local wl, wh = split7(0)  -- white component = 0

    -- SysEx 0x03: Set LED Color Palette Entry
    -- Format: header + 0x03 + index + r_lo r_hi + g_lo g_hi + b_lo b_hi + w_lo w_hi + F7
    dev:send(sysex_msg(CMD_SET_PALETTE, i, rl, rh, gl, gh, bl, bh, wl, wh))
  end

  -- SysEx 0x05: Reapply Color Palette (updates all active LEDs with new palette)
  dev:send(sysex_msg(CMD_REAPPLY_PALETTE))

  -- SysEx 0x06: Set global LED brightness to max
  dev:send(sysex_msg(CMD_SET_BRIGHTNESS, 127))
end

--- Override _reset to configure SysEx palette on device init/connect.
function push:_reset()
  local dev = midi.devices[self.midi_id]
  if not dev then return end
  self:configure_palette()
end

--- Auto-create quad switching handlers for left/right arrow buttons.
function push:create_quad_handlers(quad_count)
  if quad_count > 1 then
    for q = 1, quad_count do
      self.aux.row_handlers[q + 8] = function(self, val) self:change_quad(q) end
    end
  end
end

return push
