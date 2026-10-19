--
-- A mod to enable and disable midigrid, and to configure user preferences such
-- as grid size.
--
-- The mod is controlled throught the SYSTEM > MODS > MIDIGRID menu, and the
-- configuration is persisted when the user leaves that menu.
--
-- In order for midigrid to function, the mod must be enabled, and the
-- 'midigrid_active' setting must be set to "on" (as it is by default).  This
-- allows the user to enable and disable midigrid without needing to restart
-- norns.  However, due to the nature of midigrid, changes will have an effect
-- the next time a script tries to connect to a grid.
--

local mod = require 'core/mods'
local script = require 'core/script'
local modmenu = require 'midigrid/lib/modmenu'

-------------------------------------------------------------------------------
-- Utilities
-------------------------------------------------------------------------------

-- Debug and state persistence utilities:

local log_prefix = "midigrid"
local data_directory = _path.data .. "midigrid/"
local state_file = data_directory .. "state"
local log_file = data_directory .. "log"

local function log(s)
  print(log_prefix .. ": " .. s)

  -- logging to a file is also possible, for debugging startup/shutdown issues:

  -- local f = io.open(log_file, "a+")
  -- if f then
  --   f:write(s .. "\n")
  --   f:close()
  -- end
end

-------------------------------------------------------------------------------
-- Mod Menu Support
-------------------------------------------------------------------------------

-- The available grid sizes

local grid_sizes = { "64", "128", "256" }

-- Physical orientation of each attached controller.  The value stored in state
-- is the number of 90-degree CCW turns from the device's normal orientation.
local rotation_names = { "0", "90 CCW", "180", "90 CW" }

-- The available palettes (for Launchpad Gen 3 RGB devices)

local palette_names = {
  "vintage_amber", "arctic_aurora", "blood_moon", "candlelight",
  "cyberpunk", "deep_space", "electric_violet", "lava",
  "mono", "neon_mint", "soft_mint", "nordic_frost", "ocean",
  "peach_blossom", "poison", "sunset"
}

-- The state of midigrid as controlled by this mod

local state = {
  midigrid_active = true,  -- is midigrid active?
  grid_size = 2,           -- size of midigrid. default 2 -> grid 128
  -- Per-device physical orientation, expressed as 90-degree CCW turns.
  -- Defaults preserve the historical "rotate second device" behaviour.
  device_rotations = { 0, 1, 0, 0 },
  palette = 1,             -- palette index. default 1 -> vintage_amber
  -- Where each device sits, from "place devices": { [midi device name] = quad }.
  -- Empty: devices take quads in name order, as before.
  device_places = {},
  dirty = false            -- has the state been changed since last persisted?
}

-------------------------------------------------------------------------------
-- Midigrid Enablement
-------------------------------------------------------------------------------

-- midigrid is enabled by substituting a facade 'fake_grid' for the real global
-- 'grid' object.
local fake_grid = {
    real_grid = grid
}

-- A grid has the following public functions:
--
-- Grid.add (dev)    -- static callback when any grid device is added; user
--                      scripts can redefine
-- Grid.remove (dev) -- static callback when any grid device is removed; user
--                      scripts can redefine
-- Grid.connect (n)  -- create device, returns object with handler and send.
-- Grid.cleanup ()   -- clear handlers.
--
-- The fake grid substitutes its own 'connect' function and allows the rest to
-- be handled by the real grid.

setmetatable(fake_grid, {__index = grid})

-- We have substitude 'fake_grid' for the real grid, but midigrid doesn't know.
-- So if midigrid has trouble it might fall back on trying to connect to the
-- real grid and end up back here ... entering an infinite loop.
--
-- This variable allows us to detect and avoid this situation.

local reentrance_guard = false

fake_grid.connect = function(idx)
  local v = idx and idx or ''
  log("'connect(" .. v .. ")' called")

  if idx == nil then
    idx = 1
  end

  -- For the moment, if midigrid is active we rather rudely provide midigrid no
  -- matter what index was requested.

  if not reentrance_guard then
    if state.midigrid_active then
      log("Connecting to midigrid")
      local midigrid = include "midigrid/lib/midigrid"
      midigrid:init(grid_sizes[state.grid_size], state.device_rotations, palette_names[state.palette],
                    state.device_places)

      reentrance_guard = true
      local g = midigrid.connect(idx)
      reentrance_guard = false
      return g
    end
  else
    log("Refusing to re-enter fake_grid.connect")
  end

  log("Connecting to real grid @ index " .. idx)

  return fake_grid.real_grid.connect(idx)
end

--
-- menu: Use the modmenu module to get a PARAMETERS-style menu for the mod.
--

local m = modmenu.new("midigridmenu", mod.this_name:upper())

-- Register the mod menu

mod.menu.register(mod.this_name, m)

local function save_state()
  if not util.file_exists(data_directory) then
    os.execute("mkdir -p " .. data_directory)
  end
  local t, error = tab.save(state, state_file)
  if error then
    log("Could not save midigrid configuration: " .. error)
  end
end

-- "place devices": press a pad on each device in turn.  The mod menu shows
-- which place to press next; K2 cancels.  The places are saved at once.
local place_names = {
  [2] = { "LEFT", "RIGHT" },
  [4] = { "TOP LEFT", "TOP RIGHT", "BOTTOM LEFT", "BOTTOM RIGHT" },
}

-- The rotation settings belong to devices by number (USB name order), which says nothing about
-- where each one sits.  With a grid connected, each one's label shows its corner, e.g.
-- "device 1 (BR) rotation", so a rotation is set for the device that is really there.
local corner_names = {
  [2] = { "L", "R" },
  [4] = { "TL", "TR", "BL", "BR" },
}

local function rotation_label(d)
  local mg = _ENV.midigrid
  local vg = mg and mg.vgrid
  local dev = vg and vg.devices and vg.devices[d]
  local corner = dev and (corner_names[#vg.quads] or {})[dev.current_quad]
  if corner then return "device " .. d .. " (" .. corner .. ") rotation" end
  return "device " .. d .. " rotation"
end

local function label_rotations()
  for d = 1, 4 do
    local p = m.params.lookup["device_" .. d .. "_rotation"] and m.params:lookup_param("device_" .. d .. "_rotation")
    if p then p.name = rotation_label(d) end
  end
end
m.entry_hook = function() label_rotations() end

local function start_placing()
  local mg = _ENV.midigrid
  if not (mg and mg.vgrid and #mg.vgrid.devices > 0 and #mg.vgrid.quads > 1) then
    m.overlay = { lines = { "load a script that uses", "the grid, with midigrid", "at 128 or 256", "", "K2 back" },
                  key = function(n, z) if z == 1 then m.overlay = nil end end }
    mod.menu.redraw()
    return
  end
  local names = place_names[#mg.vgrid.quads] or {}
  local ok = mg:start_placing(function(n, total)
    m.overlay = {
      lines = { "press any pad on the", (names[n] or ("place " .. n)) .. " device", "",
                n .. " of " .. total, "K2 cancel" },
      key = function(k, z)
        if k == 2 and z == 1 then mg:cancel_placing(); m.overlay = nil end
      end,
      on_exit = function() mg:cancel_placing() end }    -- leaving the menu cancels too
    mod.menu.redraw()
  end, function(places)
    state.device_places = places
    save_state()
    label_rotations()
    log("devices placed")
    m.overlay = { lines = { "devices placed", "", "they keep their places", "while each stays in", "its USB socket" },
                  key = function(_, z) if z == 1 then m.overlay = nil end end }
    mod.menu.redraw()
  end)
  if not ok then m.overlay = nil end
end

-- Install the parameters to be edited in the mod menu.

local function init_params()
  m.params:add_option("midigrid_active", "midigrid active",
                      {"on", "off"},
                      state.midigrid_active and 1 or 2)
  m.params:set_action("midigrid_active",
                      function(v)
                          local active = v == 1 and true or false
                          if state.midigrid_active ~= active then
                              state.dirty = true
                          end
                          state.midigrid_active = active
                      end)

  m.params:add_option("midigrid_size", "midigrid size",
                      grid_sizes,
                      state.grid_size)
  m.params:set_action("midigrid_size",
                      function(v)
                          if state.grid_size ~= v then
                              state.dirty = true
                          end
                          state.grid_size = v
                      end)

  for device_number = 1,4 do
    local d = device_number
    local param_id = "device_" .. d .. "_rotation"
    m.params:add_option(param_id, "device " .. d .. " rotation",
                        rotation_names,
                        (state.device_rotations[d] or 0) + 1)
    m.params:set_action(param_id,
                        function(v)
                            local rotation = v - 1
                            if state.device_rotations[d] ~= rotation then
                                state.dirty = true
                                state.rotations_dirty = true
                            end
                            state.device_rotations[d] = rotation
                        end)
  end

  m.params:add_trigger("place_devices", "place devices")
  m.params:set_action("place_devices", function() start_placing() end)
  m.params:add_trigger("forget_places", "forget device places")
  m.params:set_action("forget_places", function()
    state.device_places = {}
    if _ENV.midigrid then _ENV.midigrid.device_places = nil end
    save_state()
    log("device places forgotten: name order from the next grid connect")
  end)

  m.params:add_option("palette", "palette",
                      palette_names,
                      state.palette)
  m.params:set_action("palette",
                      function(v)
                          if state.palette ~= v then
                              state.dirty = true
                          end
                          state.palette = v
                      end)

  m.exit_hook = function(m)
    if state.dirty then
      log("saving midigrid configuration")

      save_state()

      -- Turn the connected devices to their new rotations without a restart
      if state.rotations_dirty and _ENV.midigrid and state.midigrid_active then
        log("applying rotations")
        _ENV.midigrid:apply_rotations(state.device_rotations)
      end
      -- Flush palette changes to connected devices without requiring a restart
      if _ENV.midigrid and state.midigrid_active then
        local new_palette = palette_names[state.palette]
        log("flushing palette: " .. (new_palette or "nil"))
        _ENV.midigrid:flush_palette(new_palette)
      end
    end
    state.dirty = false
    state.rotations_dirty = false
  end
end

-- Setup is done at system startup so that the fake grid is already in place by
-- the time the script code is evaluated.

mod.hook.register("system_post_startup", "midigrid startup", function()
  log("starting up")

  local t, error = tab.load(state_file)

  if not error then
    local migrated = false

    state.midigrid_active = t.midigrid_active
    state.grid_size = t.grid_size
    if type(t.device_rotations) == "table" then
      for device_number = 1,4 do
        if t.device_rotations[device_number] ~= nil then
          state.device_rotations[device_number] = t.device_rotations[device_number] % 4
        end
      end
    elseif t.rotate_second_device ~= nil then
      -- Migrate the legacy boolean setting to the new per-device model.
      state.device_rotations = { 0, t.rotate_second_device and 1 or 0, 0, 0 }
      migrated = true
    end
    if t.palette ~= nil then
      state.palette = t.palette
    end
    if type(t.device_places) == "table" then
      for name, q in pairs(t.device_places) do
        if type(name) == "string" and type(q) == "number" then state.device_places[name] = q end
      end
    end
    state.dirty = migrated
  else
    log("Could not load midigrid configuration: " .. error)
  end

  init_params()

  grid = fake_grid

  -- I am not sure if this is needed by the mods system.  It is not used
  -- directly by this mod.

  state.system_post_startup = true
end)

mod.hook.register("system_pre_shutdown", "midigrid shutdown", function()
  -- Note that none of this code is run unless the user chooses SYSTEM>SLEEP
  -- from the menu, so this is strictly code for dealiing with powering down
  -- the device.
  --
  -- That means the code here effectively does nothing.

  -- I am not sure if this is needed by the mods system.  It is not used
  -- directly by this mod.

  state.system_post_startup = false

  grid = fake_grid.real_grid

  log("shutting down")
end)

-- This boilerplate is provided by convention.
--
-- Returning a value from the module allows the mod to provide library
-- functionality to scripts via the normal lua `require` function.

local api = {}

api.get_state = function()
  return state
end

api.palette_names = palette_names
api.rotation_names = rotation_names

return api
