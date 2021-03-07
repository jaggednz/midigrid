-- Randomly lights launchpad LED 
-- Expects LP on Midi device 1
-- 
-- Compatible LP mini mk 1 & 2    
--                              
--   looks for the ghost LEDs
--                               
--                             (=o

local m = midi.connect(1)
m.event = function(data) tab.print(data) end

local grid_metro = metro.init()

local brightness = {16,16,32,32,48,48,49,49,33,33,50,50,34,34,51}

local notes =  {  
    --1,
   -- 2,  3,  4,  5,  6,  7,  8 ,
    --17, 
    --18, 19, 20, 21, 22, 23, 24,
    --33, 
    34, 35, 36, 37, 38, 39, 40,
    --49, 
    50, 51, 52, 53, 54, 55, 56,
    --65, 
    66, 67, 68, 69, 70, 71, 72,
    --81, 
    82, 83, 84, 85, 86, 87, 88,
    --97, 
    98, 99,100,101,102,103, 104,
    --113,
    114,115,116,117,118,119,120  
    }

grid_metro.event = function()
  for n = 1,#notes do
    m:note_on(notes[n],brightness[ math.random( #brightness ) ])
  end
end


function init()
  m:send({ 0xB0, 0x00, 0x00 })
  grid_metro:start(0.01)
end
  
function redraw()

end

