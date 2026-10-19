function create_buffer(width,height)
  local new_buffer = {}

  for r = 1,width do
    new_buffer[r] = {}
    for c = 1,height do
      new_buffer[r][c] = 0
    end
  end

  return new_buffer
end

local Vgrid = {
  layout=nil,
  width=8,
  height=8,
  quads = {},
  devices = {},
  key=nil
}

function Vgrid:init(layout)
  self.layout = layout or '128'
  print("vgrid init with layout: ".. self.layout)
  -- Clear stale state from previous script to prevent quad accumulation
  self.quads = {}
  self.devices = {}
  self.placing = nil
  -- Reset dimensions to default; 128/256 branches will expand as needed
  self.width = 8
  self.height = 8
  if self.layout == '64' then
     self.locate_in_layout = function(self,x,y)
      if (x < 1 or y < 1) then return nil end
      if (x > self.width or y > self.height) then return nil end
      return 1 end
    self.new_quad(1,8,8,0,0)
     
  elseif self.layout == '128' or '256' then
    self.locate_in_layout = function(self,x,y)
      if (x < 1 or y < 1) then return nil end
      if (x > self.width or y > self.height) then return nil end
      if (y <= self.quads[1].height) then
        if (x <= self.quads[1].width) then return 1 else return 2 end
      end
      if (x <= self.quads[1].width) then return 3 else return 4 end
    end

    self.new_quad(1,8,8,0,0)
    self.new_quad(2,8,8,8,0)
    self.width = 16
    if layout == '256' then
      self.new_quad(3,8,8,0,8)
      self.new_quad(4,8,8,8,8)
      self.height = 16
    end
  else
    print("ERROR: Unknown layout " .. layout)
  end
end

local function natural_sort_key(name)
  -- Pad digit runs so duplicate-device suffixes sort naturally:
  -- "... 2", "... 2 2", "... 2 3", ..., "... 2 10".
  return string.lower(name or ""):gsub("(%d+)", function(n)
    return string.format("%08d", tonumber(n))
  end)
end

-- places (optional): { [midi_name] = quad } remembered by "place devices" (press a pad on each
-- device in turn). A device with a remembered place goes to that quad; the others fill the
-- remaining quads in name order, as before.
function Vgrid:attach_devices(compatible_devices, places)
  local ordered_devices = {}

  for _, dev in pairs(compatible_devices) do
    table.insert(ordered_devices, dev)
  end

  table.sort(ordered_devices, function(a, b)
    local a_key = natural_sort_key(a.midi_name)
    local b_key = natural_sort_key(b.midi_name)

    if a_key == b_key then
      return (a.midi_id or 0) < (b.midi_id or 0)
    end

    return a_key < b_key
  end)

  local quad_count = tab.count(self.quads)
  local quad_for = self:_assign_quads(ordered_devices, quad_count, places)

  print('Attaching devices:')
  for device_number, dev in ipairs(ordered_devices) do
    -- Stable device/quadrant assignment: a remembered place, else
    -- device 1 -> quad 1, device 2 -> quad 2, etc.
    dev.current_quad = quad_for[dev]
    table.insert(self.devices, dev)

    print("device " .. device_number
          .. " -> quad " .. dev.current_quad
          .. " (" .. (dev.midi_name or ("midi " .. dev.midi_id)) .. ")")

    -- Set callback for real device events to become virtual grid events.
    midi.devices[dev.midi_id].event = function(e) dev.event(dev,self,e) end

    dev._key_callback = function(dev_quad,dev_x,dev_y,state)
      if self.placing then return self:_place_press(dev, state) end
      -- the release of the press that finished placing is not the script's
      if dev._swallow_release and state == 0 then dev._swallow_release = nil return end
      self:_handle_grid_key(dev_quad,dev_x,dev_y,state)
    end

    -- Call device init after its quadrant has been assigned.
    dev:_init(self,device_number)
  end
end

-- Which quad each device shows: remembered places first (each quad once), then the rest in
-- order, filling the quads no place took (wrapping round when there are more devices).
function Vgrid:_assign_quads(ordered_devices, quad_count, places)
  local quad_for, taken = {}, {}
  if type(places) == "table" then
    for _, dev in ipairs(ordered_devices) do
      local q = places[dev.midi_name]
      if type(q) == "number" and q >= 1 and q <= quad_count and not taken[q] then
        quad_for[dev] = q
        taken[q] = true
      end
    end
  end
  local next_free = 1
  for device_number, dev in ipairs(ordered_devices) do
    if not quad_for[dev] then
      while next_free <= quad_count and taken[next_free] do next_free = next_free + 1 end
      if next_free <= quad_count then
        quad_for[dev] = next_free
        taken[next_free] = true
      else
        quad_for[dev] = ((device_number - 1) % quad_count) + 1
      end
    end
  end
  return quad_for
end

-------------------------------------------------------------------------------
-- Placing: press a pad on each device in turn (top left, top right, bottom
-- left, bottom right) to tell midigrid where it sits.  While placing, keys go
-- here instead of to the script and the devices show placing lights: dim to
-- be placed, bright when placed.
-------------------------------------------------------------------------------

-- How many devices to place: one per quad, or fewer when fewer are connected.
function Vgrid:places_to_fill()
  return math.min(#self.quads, #self.devices)
end

-- on_step(n, total) asks for the device of quad n; on_done(places) gets
-- { [midi_name] = quad } once every device is placed.
function Vgrid:start_placing(on_step, on_done)
  if self:places_to_fill() < 1 then return false end
  self.placing = { order = {}, taken = {}, on_step = on_step, on_done = on_done }
  self:_draw_placing()
  if on_step then on_step(1, self:places_to_fill()) end
  return true
end

function Vgrid:cancel_placing()
  if not self.placing then return end
  self.placing = nil
  self:_redraw_all()
end

function Vgrid:_place_press(dev, state)
  local p = self.placing
  if state ~= 1 or p.taken[dev] then return end
  table.insert(p.order, dev)
  p.taken[dev] = true
  self:_draw_placing()
  local total = self:places_to_fill()
  if #p.order < total then
    if p.on_step then p.on_step(#p.order + 1, total) end
    return
  end
  -- every device placed: show the quads there from now on
  local places = {}
  for q, d in ipairs(p.order) do
    d.current_quad = q
    places[d.midi_name] = q
  end
  self.placing = nil
  dev._swallow_release = true
  self:_redraw_all()
  if p.on_done then p.on_done(places) end
end

function Vgrid:_draw_placing()
  local p = self.placing
  for _, dev in pairs(self.devices) do
    dev:fill(p.taken[dev] and 15 or 3)
  end
end

function Vgrid:_redraw_all()
  for _, q in pairs(self.quads) do q.force_full_redraw = true end
  for _, dev in pairs(self.devices) do dev.force_full_refresh = true end
  self:refresh()
end

function Vgrid:_handle_grid_key(quad_id,qx,qy,state)
  -- Send device event to quad
  --print('q:'..quad_id..' x:'.. qx ..' y:'..qy..' s:'..state)
  self.quads[quad_id]:key(qx,qy,state,self.key)
end

function Vgrid:find_quad(x,y)
  local qid = 1
  
  if self.locate_in_layout then qid = self.locate_in_layout(self,x,y) end
  return self.quads[qid]
end

function Vgrid:set(x,y,z)
  local q = self:find_quad(x,y)
  if q then
    q:_relative_set(x,y,z)
  else
    print('Coords '..x..', '..y..' (x,y) outside Virtual Grid!')
  end
end

function Vgrid:set_all(z)
  for qid = 1, #Vgrid.quads do
    q = self.quads[qid]
    for x = 1,q.width do
      for y = 1,q.height do
        q:_set(x,y,z)
      end
    end
  end
end

function Vgrid:refresh(device_id)
  if self.placing then                -- the devices show placing lights meanwhile
    for _, quad in pairs(self.quads) do quad:reset_updates() end   -- the script's changes: redrawn in full afterwards
    return
  end
  for qid,quad in pairs(self.quads) do
    --print('vgrid refresh ' .. qid)
    
    quad:freeze_updates()
    
    if device_id then
      self.devices[device_id]:refresh(quad)
    else
      for _,device in pairs(self.devices) do
        device:refresh(quad)
      end
    end
    
    quad:reset_updates()
  end
end

function Vgrid.new_quad(id,width,height,offset_x,offset_y)
  q = {
    id=id,
    width=width,
    height=height,
    offset_x=offset_x,
    offset_y=offset_y,
    buffer = create_buffer(width,height),
    updates_x = {}, -- list of changed x values for delta updates
    updates_y = {}, -- list of changed y values for delta updates
    update_count = 0,
    force_full_redraw = false
  }
  function q:_set(qx,qy,qz)
    if (self.buffer[qx][qy] ~= qz) then
      self.update_count = self.update_count + 1
      table.insert(self.updates_x,qx)
      table.insert(self.updates_y,qy)
      self.buffer[qx][qy] = qz
    end
  end
  
  -- The changes since the last refresh, for the devices to send.  The same
  -- tables are used every refresh (new ones each time made garbage 30 or
  -- more times a second); they are only read between freeze and reset.
  function q:freeze_updates()
    local f = self.frozen_update
    if not f then f = {}; self.frozen_update = f end
    f.update_count = self.update_count
    f.updates_x = self.updates_x
    f.updates_y = self.updates_y
  end

  function q:reset_updates()
    local ux, uy = self.updates_x, self.updates_y
    for k = #ux, 1, -1 do ux[k] = nil end
    for k = #uy, 1, -1 do uy[k] = nil end
    self.update_count = 0
    if self.frozen_update then self.frozen_update.update_count = 0 end
  end

  function q:_relative_set(rx,ry,qz)
    local qx = rx - self.offset_x
    local qy = ry - self.offset_y

    self:_set(qx,qy,qz)
  end

  function q:each_with(device,callback)
    for x = 1,self.width do
      for y = 1,self.height do
        callback(device,x,y,self.buffer[x][y])
      end
    end
  end

  function q:updates_with(device,callback)
    if self.frozen_update and self.frozen_update.update_count > 0 then
      for u = 1,self.frozen_update.update_count do
        local x = self.frozen_update.updates_x[u]
        local y = self.frozen_update.updates_y[u]
        callback(device,x,y,self.buffer[x][y])
      end
    end
  end
  
  function q:key(qx,qy,state,callback)
    local rx = qx + self.offset_x
    local ry = qy + self.offset_y
    callback(rx,ry,state)
  end

  table.insert(Vgrid.quads,q)

  return q
end

return Vgrid
