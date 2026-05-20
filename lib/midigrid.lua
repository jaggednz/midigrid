--[[ cheapskate lib for getting midi grid devices to behave like monome grid devices
     two things are run before returning, `setup_connect_handling()` and `update_devices()`.
     `setup_connect_handling()` copies over 'og' midi "add" and "remove" callbacks, and
     provides its own add and remove handlers, i.e. the call backs for:
       - `midi.add()`
       - `midi.remove()`
       - `midi.update_devices()`
     `find_midi_device_id()` iterates through `midi.devices` to see if the name matches, then
     returns `id`, this system manages its own ids, which is why you have to initialize it and
     why first, you connect to it (`midigrid.connect()`), which returns a midigrid object and
     does `set_midi_handler()`
]]

local vgrid = include('midigrid/lib/vgrid')
local supported_devices = include('midigrid/lib/supported_devices')

local midigrid = {
  is_midigrid = true,
  vgrid = vgrid,
  device = nil,

  -- If the global 'grid' object contains a 'real_grid' element, then it must
  -- have already been replaced by the midigrid mod.  Use the mod's 'real_grid'
  -- if it exists, and the global 'grid' otherwise.
  --
  -- This ensures that 'core_grid' actually points to the underlying grid
  -- subsystem.

  core_grid = grid.real_grid or grid,
  core_midi_add = nil,
  core_midi_remove = nil,
  cols = 8,
  rows = 8,
  key = nil,
}

function midigrid:init(layout, rotate_second, palette_name)
  self.vgrid:init(layout)
  self.cols = self.vgrid.width
  self.rows = self.vgrid.height
  self.rotate_second_device = rotate_second
  self.palette_name = palette_name
end

function midigrid.connect(dummy_id)
  -- If already instantiated (script switch), clear stale hardware state
  if _ENV.midigrid then
    -- Zero all quad buffers so the new script starts with a clean slate
    for _, quad in pairs(midigrid.vgrid.quads) do
      for x = 1, quad.width do
        for y = 1, quad.height do
          quad.buffer[x][y] = 0
        end
      end
    end
    -- Force every device to resend all LEDs on next refresh (clears hardware)
    for _, device in pairs(midigrid.vgrid.devices) do
      device.force_full_refresh = true
    end
    -- Push the all-off state to hardware immediately
    midigrid.vgrid:refresh()
    return _ENV.midigrid
  end
  
  if midigrid.vgrid.layout == nil then
    print("Default 64 layout init")
    -- User is calling connect without calling init, default to 64 button layout
    midigrid:init('64', nil, nil)
  end

  local midi_devices = midigrid._find_midigrid_devices()

  -- If no midi devices found
  if next(midi_devices) == nil then
    print('No supported device found' .. #midi_devices)

    tab.print(midi_devices)
    -- Make midigrid transparent if no devices found and return the core grid connect()
    return midigrid.core_grid.connect()
  end

  local connected_devices = midigrid._load_midi_devices(midi_devices)

  -- Some script check grid.device is not nil to prove a grid is attached
  if connected_devices then
    midigrid.device = {
        id = 999,
        cols = midigrid.cols,
        rows = midigrid.rows,
        -- leaving out 'port' because a dummy value might cause undefined
        -- behavior.  Better to have an error if some script actually needs to
        -- use the port number than to silently do something weird.
        name = "midigrid",
        serial = 1234567
    }
  end

  vgrid:attach_devices(connected_devices)
  midigrid.setup_connect_handling()

  --Expose midigrid globally
  _ENV.midigrid = midigrid
  
  return midigrid
end

function vgrid.key(x,y,z)
  if midigrid.key then
    midigrid.key(x,y,z)
  end
end

--this looks to the supported_devices.lua file and returns a table of supported midi devices currently connected
function midigrid._find_midigrid_devices()
  local found_device = nil
  local mounted_devices = {}

  print(tab.count(midi.devices)," core midi devices")
  print("Scanning for supported midigrid devices:")
  for _, dev in pairs(midi.devices) do
    found_device = supported_devices.find_midi_device_type(dev)

    if found_device then 
      print(found_device," -- Supported")
      mounted_devices[dev.id] = found_device 
    else
      print(dev.name," -- Not supported")
    end
  end

  print("mounted_devices")
  tab.print(mounted_devices)

  return mounted_devices
end

function midigrid._load_midi_devices(midi_devs)
  local connected_devices = {}

  -- Resolve palette: use init()'s explicit setting, or fall back to mod state
  local palette_name = midigrid.palette_name
  if not palette_name then
    local ok, mod_api = pcall(function() return require("midigrid/lib/mod") end)
    if ok and mod_api and mod_api.get_state then
      local s = mod_api.get_state()
      if s.palette and mod_api.palette_names then
        palette_name = mod_api.palette_names[s.palette]
      end
    end
  end

  for midi_id,midi_device_type in pairs(midi_devs) do
    print("Loading midi device type:" .. midi_device_type .. " on midi port " .. midi_id)
    local device = include('midigrid/lib/devices/'..midi_device_type)
    device.midi_id = midi_id
    -- Apply the mod-level rotate setting to the device
    device.rotate_second_device = midigrid.rotate_second_device
    -- Apply the palette setting (Gen3 RGB devices)
    if palette_name and device.rgb_lut then
      device.rgb_lut = include('midigrid/lib/devices/palettes/' .. palette_name)
    end
    connected_devices[midi_id] = device
  end

  return connected_devices
end

-- Flush a new palette to all connected devices and force a full redraw.
-- Called from the mod menu exit_hook when the palette setting changes.
function midigrid:flush_palette(palette_name)
  if not palette_name then return end
  for _, device in pairs(self.vgrid.devices) do
    if device.rgb_lut then
      device.rgb_lut = include('midigrid/lib/devices/palettes/' .. palette_name)
    end
  end
  -- Force a full refresh so the hardware picks up the new colours immediately
  for _, quad in pairs(self.vgrid.quads) do
    quad.force_full_redraw = true
  end
  -- Also force devices to resend every LED on next refresh
  for _, device in pairs(self.vgrid.devices) do
    if device.force_full_refresh ~= nil then
      device.force_full_refresh = true
    end
  end
  self.vgrid:refresh()
end

function midigrid.setup_connect_handling()
    midigrid.core_midi_add = midi.add
    midigrid.core_midi_remove = midi.remove
    midi.add = midigrid._handle_dev_add
    midi.remove = midigrid._handle_dev_remove
end

function midigrid._handle_dev_add(id, name, dev)
    midigrid.core_midi_add(id, name, dev)
    -- midigrid.update_devices()
end

function midigrid._handle_dev_remove(id)
    midigrid.core_midi_remove(id)
    -- midigrid.update_devices()
end

function midigrid.update_devices()
    --TODO WTF does this do?
    midi.update_devices()
end

-- Grid emulation functions

function midigrid:intensity(i)
   --TODO unimplemented
end

function midigrid:rotation(dir)
  --TODO Is there a sane way to implement this with multi device?
  --TODO impement for single 64 device
end

function midigrid:all(z)
  return self.vgrid:set_all(z)
end

function midigrid:led(x,y,z)
  return self.vgrid:set(x,y,z)
end

function midigrid:refresh()
  return self.vgrid:refresh()
end

midigrid.name = 'Midi Grid'
midigrid.vports = { }
midigrid.vports[1] = midigrid

return midigrid
