local device = include('midigrid/lib/devices/generic_device')

device.channel_pad = 1
device.channel_aux = 16

-- Grid Clip setting
device.grid_notes= {
  {0,1,2,3,4,5,6,7},
  {16,17,18,19,20,21,22,23},
  {32,33,34,35,36,37,38,39},
  {48,49,50,51,52,53,54,55},
  {64,65,66,67,68,69,70,71},
  {80,81,82,83,84,85,86,87},
  {96,97,98,99,100,101,102,103},
  {112,113,114,115,116,117,118,119},
}

device.brightness_map = {
  0, -- No color
  16,
  16,
  32,
  32,
  48,
  48,
  48,
  64,
  64,
  80,
  80,
  96,
  96,
  127,
  127,
}

device.aux = {}

device.aux.row = {
  {'note', 112, 0},
  {'note', 113, 0},
  {'note', 114, 0},
  {'note', 115, 0},
  {'note', 116, 0},
  {'note', 117, 0},
  {'note', 118, 0},
  {'note', 119, 0}
}

device.aux.col = {
  {'cc', 0, 0},
  {'cc', 1, 0},
  {'cc', 2, 0},
  {'cc', 3, 0},
  {'cc', 4, 0},
  {'cc', 5, 0},
  {'cc', 6, 0},
  {'cc', 7, 0}
}

function device.event(self,vgrid,event)
  -- type="note_on", note, vel, ch
  local midi_msg = midi.to_msg(event)
  local key_state = (midi_msg.type == 'note_on') and 1 or 0
  
  if (midi_msg.type == 'note_on' or midi_msg.type == 'note_off') and (midi_msg.ch == self.channel_pad) then
    local key = self.note_to_grid_lookup[midi_msg.note]
    if key then
      self._key_callback(self.current_quad,key['x'],key['y'],key_state)
    else
      self:_aux_btn_handler('note',midi_msg.note,key_state)
    end
  elseif (midi_msg.type == 'cc') then
    self:_aux_btn_handler('cc',midi_msg.cc,(midi_msg.val>0) and 1 or 0)
  elseif (midi_msg.ch == self.channel_aux) then
    self:_aux_btn_handler('note',midi_msg.note,key_state)
  end
end

function device._update_led(self,x,y,z)
  if y < 1 or #self.grid_notes < y or x < 1 or #self.grid_notes[y] < x then
    print("_update_led: x="..x.."; y="..y.."; z="..z)
    return
  end

  local vel = self.brightness_map[z+1]
  local note = self.grid_notes[y][x]
  local midi_msg = {0x90,note,vel}
  local midi_msg_off = {0x80,note,0x00}
  --print("_update_led: note="..note.."; vel="..vel)
  --TODO: do we accept a few error msg on failed unmount and check device status in :refresh
  if midi.devices[self.midi_id] then midi.devices[self.midi_id]:send(midi_msg_off) end
  if midi.devices[self.midi_id] then midi.devices[self.midi_id]:send(midi_msg) end
end

return device
