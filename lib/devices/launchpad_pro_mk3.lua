local launchpad = include('midigrid/lib/devices/launchpad_rgb')

--Put the device into programmers mode
launchpad.init_device_msg = { 0xf0,0x00,0x20,0x29,0x02,0x0e,0x0e,0x01,0xf7 }

launchpad.rotate_second_device = false

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

-- Override change_quad to force an immediate grid redraw when switching pages.
-- Without this, the Launchpad won't update until the script's next dirty_grid
-- cycle, which may not be running (e.g. when playback is stopped).
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
