-- mods on the generic device for Push 2
local push = include('midigrid/lib/devices/generic_device')

print('loading push')

-- mapping for Push's main pads
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

-- probably want to change these as I've not thought to much about them at this point :-)
push.brightness_map = {0,11,11,9,9,9,13,13,51,51,51,49,49,59,59,57}
push.rotate_second_device = false

push.aux = {}
-- Format is { 'cc'/'note', cc or note number, current/default state (1-16) }
--top to bottom
push.aux.col = {
  {'cc',   43, 0},
  {'cc',   42, 0},
  {'cc',   41, 0},
  {'cc',   40, 0},
  {'cc',   39, 0},
  {'cc',   38, 0},
  {'cc',   37, 0},
  {'cc',   36, 0}
}
--left to right
push.aux.row = {
  {'cc',   20, 0},
  {'cc',   21, 0},
  {'cc',   22, 0},
  {'cc',   23, 0},
  {'cc',   24, 0},
  {'cc',   25, 0},
  {'cc',   26, 0},
  {'cc',   27, 0},
  {'cc',   44, 0}, -- Left arrow
  {'cc',   45, 0}, -- Right arrow
  {'cc',   46, 0}, -- Up arrow
  {'cc',   47, 0}, -- Down arrow
  
}

function push:create_quad_handers(quad_count)
  -- Auto create Quad switching handlers attached to left and right arrow buttons
  if quad_count > 1 then
    for q = 1,quad_count do
      self.aux.row_handlers[q+8] = function(self,val) self:change_quad(q) end
    end
  end
end

return push
