local launchpad = include('midigrid/lib/devices/launchpad_rgb')

--Put the device into programmers mode
launchpad.init_device_msg = { 0xf0,0x00,0x20,0x29,0x02,0x10,0x2c,0x03,0xf7 }

launchpad.aux.col = {
  {'cc', 89, 0},
  {'cc', 79, 0},
  {'cc', 69, 0},
  {'cc', 59, 0},
  {'cc', 49, 0},
  {'cc', 39, 0},
  {'cc', 29, 0},
  {'cc', 19, 0}
}

launchpad.aux.row = {
  {'cc', 91, 0},
  {'cc', 92, 0},
  {'cc', 93, 0},
  {'cc', 94, 0},
  {'cc', 95, 0},
  {'cc', 96, 0},
  {'cc', 97, 0},
  {'cc', 98, 0}
}

return launchpad