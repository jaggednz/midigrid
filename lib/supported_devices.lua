local supported_devices = {
  midi_devices = {
    
    -- Basic midi grid devices
    { midi_base_name= 'apc mini',         device_type='apc_mini'      },
    { midi_base_name= 'apc mini mk2 1',   device_type='apc_mini_mk2'  },
    { midi_base_name= 'block 1',          device_type='livid_block'   },

    -- Novation Launchpads Gen.1
    
    { midi_base_name= 'launchpad',        device_type='launchpad'       },
    { midi_base_name= 'launchpad s',      device_type='launchpad'       },
    { midi_base_name= 'launchpad mini',   device_type='launchpad'       },
    
    -- Novation Launchpads Gen.2
    --
    -- LP Mini MK3 presents two MIDI interfaces over USB:
    --   launchpad mini mk3 1 - LPMiniMK3 DAW I/O (or first interface): For use
    --                        by DAWs and similar software to interact with the
    --                        MK3’s Session mode.
    --   launchpad mini mk3 2 - LPMiniMK3 MIDI I/O (or second interface): Used
    --                        to receive MIDI from Custom modes; and to provide
    --                        external MIDI input or Light controls in
    --                        Lighting Custom Modes and Programmer mode.
    --
    -- A second LP Mini MK3 displays these device names:
    --   launchpad mini mk3 1 2
    --   launchpad mini mk3 2 2
    -- LP Mini MK3 needs to be put in Programmer mode manually for midigrid use.
    { midi_base_name= 'launchpad mk2',          device_type='launchpad_rgb'   },
    { midi_base_name= 'launchpad mk2 2',          device_type='launchpad_rgb'   },
    { midi_base_name= 'launchpad mini mk3 2',   device_type='launchpad_minimk3' },
    { midi_base_name= 'launchpad mini mk3 2 2', device_type='launchpad_minimk3' },
    { midi_base_name= 'launchpad pro mk3',      device_type='launchpad_rgb' },
    { midi_base_name= 'launchpad pro mk3 1',      device_type='launchpad_mk3' },
    { midi_base_name= 'launchpad pro mk3 2',      device_type='launchpad_mk3' },
    { midi_base_name= 'launchpad pro mk3 3',      device_type='launchpad_mk3' },
    { midi_base_name= 'launchpad x 2',          device_type='launchpad_x' },
    { midi_base_name= 'launchpad x 2 2',        device_type='launchpad_x' },
    { midi_base_name= 'launchpad open 2',       device_type='launchpad_x' },
    
    -- Ableton Push 2
    { midi_base_name= 'ableton push 2 1',          device_type='push2'   },
    
    -- Linnstrument
    { midi_base_name= 'linnstrument midi',          device_type='linnstrument'   },

    -- Synthstrom Deluge
    { midi_base_name = 'deluge 1', device_type='deluge' },

  }
}

function supported_devices.find_midi_device_type(midi_device)
  --print('finding device: ' .. midi_device.id .. " with name " .. midi_device.name)
  local sysex_ident_resp = nil
  -- TODO get response to sysex indentify call

  if string.lower(midi_device.name):find 'launchpad mini %d' then
    -- Old launchpad mini's have user set hardware ID 1 - 16:
    -- e.g. ID 4 appears as midi_device.name "Launchpad Mini 4"
    return 'launchpad'
  else
    for _,device_def in pairs(supported_devices.midi_devices) do
      if sysex_ident_resp and device_def.sysex_ident then
        --TODO use General Sysex ident call to try and ID device
      end
      -- Fall back to midi name matching
      -- TODO strip / ignore device name suffix for multiple devices
      if (device_def.midi_base_name == string.lower(midi_device.name)) then return device_def.device_type end
    end
    return nil
  end
end

return supported_devices
