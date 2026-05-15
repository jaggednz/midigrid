-----------------------------------------------------------------------
-- Launchpad Mini MK3 — Gen 3 SysEx RGB driver
--
-- SysEx device ID: 0x0D
-- Aux: right column (CC 89,79,...,19), top row (CC 91-98)
-- MIDI interface: port 2 (LPMiniMK3 MIDI In/Out)
-----------------------------------------------------------------------

local launchpad = include('midigrid/lib/devices/launchpad_gen3')

launchpad.sysex_device_id = 0x0D

-- Enter Programmer Mode via Programmer/Live toggle
launchpad.init_device_msg = { 0xf0, 0x00, 0x20, 0x29, 0x02, 0x0d, 0x0e, 0x01, 0xf7 }

-- Right column (bottom to top)
launchpad.aux.col = {
  {'cc', 89, 0}, {'cc', 79, 0}, {'cc', 69, 0}, {'cc', 59, 0},
  {'cc', 49, 0}, {'cc', 39, 0}, {'cc', 29, 0}, {'cc', 19, 0}
}

-- Top row (left to right)
launchpad.aux.row = {
  {'cc', 91, 0}, {'cc', 92, 0}, {'cc', 93, 0}, {'cc', 94, 0},
  {'cc', 95, 0}, {'cc', 96, 0}, {'cc', 97, 0}, {'cc', 98, 0}
}

return launchpad
