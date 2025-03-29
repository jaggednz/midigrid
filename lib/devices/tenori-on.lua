-- Tenori-ON support for Norns midigrid
-- Requires pika.blue Tenori-ON firmware A042 (https://pika.blue)
-- which introduces a new "Grid" layer mode on Tenori-ON

local tenori_on = include('midigrid/lib/devices/generic_device')

tenori_on.width=16
tenori_on.height=16

tenori_on.grid_layer_configured=0

tenori_on.grid_notes= {
{0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15},
{16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31},
{32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47},
{48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63},
{64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79},
{80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95},
{96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111},
{112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127},
{128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143},
{144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159},
{160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175},
{176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191},
{192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207},
{208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223},
{224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239},
{240, 241, 242, 243, 244, 245, 246, 247, 248, 249, 250, 251, 252, 253, 254, 255},
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
local prevBuffer3 = {
  {0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0},
}
local prevBuffer4 = {
  {0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0},
}

tenori_on.brightness_map = {0,40,40,40,40,40,80,80,80,80,120,120,120,120,120,120}

tenori_on.init_device_msg = { 0xB0, 0x55, 0x47 }


function tenori_on._update_led(self,x,y,z)
  if (self.grid_layer_configured == 0) then
    if midi.devices[self.midi_id] then
      print("midigrid/lib/devices/tenori-on.lua sending Tenori-ON init message until it responds")
      midi.devices[self.midi_id]:send(tenori_on.init_device_msg)
    end
    return
  end

  if y < 1 or #self.grid_notes < y or x < 1 or #self.grid_notes[y] < x then
    return
  end

  local vel = self.brightness_map[z+1]
  local note = self.grid_notes[y][x]

  if note < 128 then
    local midi_msg = {0x90,note,vel}
    if midi.devices[self.midi_id] then midi.devices[self.midi_id]:send(midi_msg) end
  else
    local midi_msg = {0xA0, note-128,vel}
    if midi.devices[self.midi_id] then midi.devices[self.midi_id]:send(midi_msg) end
  end
  --TODO: do we accept a few error msg on failed unmount and check device status in :refresh

end

function tenori_on.event(self,vgrid,event)
  -- type="note_on", note, vel, ch
  -- Note that midi msg already translates note on vel 0 to note off type
  local midi_msg = midi.to_msg(event)

  if (midi_msg.type == 'note_on' or midi_msg.type == 'note_off') then
    print("tenori_on.event: midi_msg.type="..midi_msg.type.."; midi_msg.note="..midi_msg.note)
    local key = self.note_to_grid_lookup[midi_msg.note]
    local key_state = (midi_msg.type == 'note_on') and 1 or 0
    if key then
      self._key_callback(self.current_quad,key['x'],key['y'],key_state)
    else
      self:_aux_btn_handler('note',midi_msg.note,key_state)
    end
  elseif (midi_msg.type =='key_pressure') then
    print("tenori_on.event: key_pressure midi_msg.val="..midi_msg.val.."; midi_msg.note="..midi_msg.note)
    local key = self.note_to_grid_lookup[midi_msg.note + 128]
    local key_state = (midi_msg.val >0 ) and 1 or 0
    if key then
      self._key_callback(self.current_quad,key['x'],key['y'],key_state)
    else
      self:_aux_btn_handler('note',midi_msg.note,key_state)
    end

  elseif (midi_msg.type == 'cc') then
    if ((event[1] == 0xB0) and (event[2] == 0x55)) then

      if (event[3] == 0x23) then
        self.grid_layer_configured = 1
      end
      if (event[3] == 0x20) or (event[3] == 0x21) or (event[3] == 0x22) then
        self.grid_layer_configured = 0
      end

      if (event[3] == 0x16) then
        key(1, 1)
      end
      if (event[3] == 0x06) then
        key(1, 0)
      end
      if (event[3] == 0x17) then
        key(2, 1)
      end
      if (event[3] == 0x07) then
        key(2, 0)
      end
      if (event[3] == 0x18) then
        key(3, 1)
      end
      if (event[3] == 0x08) then
        key(3, 0)
      end
      if (event[3] == 0x14) then
        self._clear_all_buffers()
      end

    end
  end
end

function dumpTable(tbl, indent)
    indent = indent or 0
    for k, v in pairs(tbl) do
        print(string.rep(" ", indent) .. tostring(k) .. ":")
        if type(v) == "table" then
            dumpTable(v, indent + 2)
        else
            print(string.rep(" ", indent + 2) .. tostring(v))
        end
    end
end


tenori_on.aux = {}

function tenori_on:_clear_all_buffers(self)
  print("Clearing all buffers")
  for x = 1,8 do
    for y = 1,8 do
      prevBuffer1[x][y] = 0
      prevBuffer2[x][y] = 0
      prevBuffer3[x][y] = 0
      prevBuffer4[x][y] = 0
    end
  end
end


function tenori_on:refresh(quad)
  if quad.id == 1 then
    for x = 1,self.width do
      for y = 1,self.height do
        if x <= 8 and y<= 8 then

          if self.vgrid.quads[1].buffer[x][y] ~= prevBuffer1[x][y] then
            self._update_led(self,x,y,self.vgrid.quads[1].buffer[x][y])
            prevBuffer1[x][y] = self.vgrid.quads[1].buffer[x][y]
          end

        elseif x > 8 and y <= 8 then

          if self.vgrid.quads[2].buffer[x-8][y] ~= prevBuffer2[x-8][y] then
            self._update_led(self,x,y,self.vgrid.quads[2].buffer[x-8][y])
            prevBuffer2[x-8][y] = self.vgrid.quads[2].buffer[x-8][y]
          end

        elseif x <= 8 and y > 8 then

          if self.vgrid.quads[3].buffer[x][y-8] ~= prevBuffer3[x][y-8] then
            self._update_led(self,x,y,self.vgrid.quads[3].buffer[x][y-8])
            prevBuffer3[x][y-8] = self.vgrid.quads[3].buffer[x][y-8]
          end
        elseif x >8 and y >8 then

          if self.vgrid.quads[4].buffer[x-8][y-8] ~= prevBuffer4[x-8][y-8] then
            self._update_led(self,x,y,self.vgrid.quads[4].buffer[x-8][y-8])
            prevBuffer4[x-8][y-8] = self.vgrid.quads[4].buffer[x-8][y-8]
          end


        end
      end
    end
  end
end

return tenori_on
