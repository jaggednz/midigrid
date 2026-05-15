-----------------------------------------------------------------------
-- Launchpad Pro MK3 — Gen 3 SysEx RGB driver
--
-- SysEx device ID: 0x0E
-- Aux: left column (CC 10-80), top row (CC 91-98)
-- Extra buttons: Setup (CC 90), User (CC 99)
-----------------------------------------------------------------------

local launchpad = include('midigrid/lib/devices/launchpad_gen3')

-- Palette selection (uncomment one):
-- launchpad.rgb_lut = include('midigrid/lib/devices/palettes/arctic_aurora')
-- launchpad.rgb_lut = include('midigrid/lib/devices/palettes/blood_moon')
-- launchpad.rgb_lut = include('midigrid/lib/devices/palettes/candlelight')
-- launchpad.rgb_lut = include('midigrid/lib/devices/palettes/cyberpunk')
-- launchpad.rgb_lut = include('midigrid/lib/devices/palettes/deep_space')
-- launchpad.rgb_lut = include('midigrid/lib/devices/palettes/electric_violet')
-- launchpad.rgb_lut = include('midigrid/lib/devices/palettes/lava')
-- launchpad.rgb_lut = include('midigrid/lib/devices/palettes/mono')
-- launchpad.rgb_lut = include('midigrid/lib/devices/palettes/neon_mint')
-- launchpad.rgb_lut = include('midigrid/lib/devices/palettes/nordic_frost')
-- launchpad.rgb_lut = include('midigrid/lib/devices/palettes/ocean')
-- launchpad.rgb_lut = include('midigrid/lib/devices/palettes/peach_blossom')
-- launchpad.rgb_lut = include('midigrid/lib/devices/palettes/poison')
-- launchpad.rgb_lut = include('midigrid/lib/devices/palettes/sunset')
launchpad.rgb_lut = include('midigrid/lib/devices/palettes/vintage_amber')

launchpad.sysex_device_id = 0x0E

-- Enter Programmer Mode via Programmer/Live toggle
launchpad.init_device_msg = { 0xf0, 0x00, 0x20, 0x29, 0x02, 0x0e, 0x0e, 0x01, 0xf7 }

-- Extra buttons beyond aux: Setup and User
launchpad._extra_btn_ccs = { 90, 99 }

-- Left column (bottom to top)
launchpad.aux.col = {
  {'cc', 10, 0}, {'cc', 20, 0}, {'cc', 30, 0}, {'cc', 40, 0},
  {'cc', 50, 0}, {'cc', 60, 0}, {'cc', 70, 0}, {'cc', 80, 0}
}

-- Top row (left to right)
launchpad.aux.row = {
  {'cc', 91, 0}, {'cc', 92, 0}, {'cc', 93, 0}, {'cc', 94, 0},
  {'cc', 95, 0}, {'cc', 96, 0}, {'cc', 97, 0}, {'cc', 98, 0}
}

return launchpad
