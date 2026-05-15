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

-- The state of midigrid as controlled by this mod

local state = {
  midigrid_active = true,  -- is midigrid active?
  grid_size = 2,           -- size of midigrid.  default 2 -> grid 128
  rotate_second_device = true, -- rotate the second device 90 degrees CCW
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
      midigrid:init(grid_sizes[state.grid_size], state.rotate_second_device)

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

  m.params:add_option("rotate_second_device", "rotate second device",
                      {"on", "off"},
                      state.rotate_second_device and 1 or 2)
  m.params:set_action("rotate_second_device",
                      function(v)
                          local rotate = v == 1 and true or false
                          if state.rotate_second_device ~= rotate then
                              state.dirty = true
                          end
                          state.rotate_second_device = rotate
                      end)

  m.exit_hook = function(m)
    if state.dirty then
      log("saving midigrid configuration")

      if not util.file_exists(data_directory) then
        os.execute("mkdir -p " .. data_directory)
      end

      local t, error = tab.save(state, state_file)

      if error then
        log("Could not save midigrid configuration: " .. error)
      end
    end
    state.dirty = false
  end
end

-- Setup is done at system startup so that the fake grid is already in place by
-- the time the script code is evaluated.

mod.hook.register("system_post_startup", "midigrid startup", function()
  log("starting up")

  local t, error = tab.load(state_file)

  if not error then
    state.midigrid_active = t.midigrid_active
    state.grid_size = t.grid_size
    if t.rotate_second_device ~= nil then
      state.rotate_second_device = t.rotate_second_device
    end
    state.dirty = false
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

return api
