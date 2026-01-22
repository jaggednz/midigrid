local launchpad = include('midigrid/lib/devices/launchpad_rgb')

-- Novation Launchpad Pro MK3 specific settings
launchpad.init_device_msg = {0xf0, 0x00, 0x20, 0x29, 0x02, 0x0e, 0x0e, 0x01, 0xf7}

return launchpad
