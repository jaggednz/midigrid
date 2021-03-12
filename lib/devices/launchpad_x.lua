local launchpad = include('midigrid/lib/devices/launchpad_rgb')

launchpad.device_name = 'launchpad_x'

-- https://llllllll.co/t/how-do-i-send-midi-sysex-messages-on-norns/34359/14
function launchpad:init()
  print('Setting Launchpad Programmer mode')
  m = midi.devices[launchpad.midi_id]
  d = {0x0,0x20,0x29,0x02,0x0D,0x00,0x7F}
  m:send{0xf0}
  for i,v in ipairs(d) do
    m:send{d[i]}
  end
  m:send{0xf7}
end

return launchpad