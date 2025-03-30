local deluge = include('midigrid/lib/devices/generic_device')

deluge.channel_select = 16 -- channel 1 - 16, picking because it's probably least used
deluge.LED_msg = 0x90 + (deluge.channel_select - 1) -- 1001 (9) is note_on, 1111 (15) is midi channel (1-16)

deluge.width = 16
deluge.height = 8

-- mapping velocity (0-127) to LED brightness on deluge side, brightness map needs 16 values
deluge.brightness_map = {0,15,23,31,39,47,55,63,71,79,87,95,103,111,119,126}

-- 0 is bottom left of deluge main grid, 127 is top right of deluge main grid
-- 0 is C-2, 127 is G8
deluge.grid_notes= {
  {112,113,114,115,116,117,118,119,120,121,122,123,124,125,126,127},
  { 96, 97, 98, 99,100,101,102,103,104,105,106,107,108,109,110,111},
  { 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95},
  { 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79},
  { 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63},
  { 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47},
  { 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31},
  {  0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15}
}

local prevBuffer1 = {
  {0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0},
}
local prevBuffer2 = {
  {0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0},
}

-- from deluge to norns
-- hardcoding midi note_on commands from deluge to midigrid to only work with channel deluge.channel_select
function deluge.event(self,vgrid,event)

  local midi_msg = midi.to_msg(event)

  -- Debug incomming midi messages
  -- print(midi_msg.type..midi_msg.cc..midi_msg.val..midi_msg.ch)
  
  if (midi_msg.type == 'note_on' or midi_msg.type == 'note_off') and (midi_msg.ch == self.channel_select) then
    local key = self.note_to_grid_lookup[midi_msg.note]
    local key_state = (midi_msg.type == 'note_on') and 1 or 0
    if key then
      self._key_callback(self.current_quad,key['x'],key['y'],key_state)
    else
      self:_aux_btn_handler('note',midi_msg.note,key_state)
    end
  elseif (midi_msg.type == 'cc') then
    self:_aux_btn_handler('cc',midi_msg.cc,(midi_msg.val>0) and 1 or 0)
  end
end

-- from norns to deluge
-- using midi cc messages instead of note_on messages
function deluge._update_led(self,x,y,z)
  if y < 1 or #self.grid_notes < y or x < 1 or #self.grid_notes[y] < x then
    print("_update_led: x="..x.."; y="..y.."; z="..z)
    return
  end
  local vel = self.brightness_map[z+1]
  local note = self.grid_notes[y][x]
  local midi_msg = {self.LED_msg,note,vel}
  if midi.devices[self.midi_id] then midi.devices[self.midi_id]:send(midi_msg) end
end

-- from norns to deluge
-- mg_128 creates 2 quads of 64, copied from linnstrument.lua
function deluge:refresh(quad)
  if quad.id == 1 then
    for x = 1,self.width do
      for y = 1,self.height do
        if x <= 8 then
          if self.vgrid.quads[1].buffer[x][y] ~= prevBuffer1[x][y] then
            self._update_led(self,x,y,self.vgrid.quads[1].buffer[x][y])
            prevBuffer1[x][y] = self.vgrid.quads[1].buffer[x][y]
          end
        else
          if self.vgrid.quads[2].buffer[x-8][y] ~= prevBuffer2[x-8][y] then
            self._update_led(self,x,y,self.vgrid.quads[2].buffer[x-8][y])
            prevBuffer2[x-8][y] = self.vgrid.quads[2].buffer[x-8][y]
          end
        end
      end
    end
  end  
end

return deluge
