local apcmini = include('midigrid/lib/devices/generic_device')

apcmini.brightness_map = {0,1,1,1,1,1,1,1,3,3,3,3,5,5,5,5}

 --these are the keys in the apc to the sides of our apc, not necessary for strict grid emulation but handy!
 --they are up to down, so 70 is the auxkey to row 1
 apcmini.aux = {}
 
 apcmini.aux.col = {
    {'note',  82, 1},
    {'note',  83, 2},
    {'note',  84, 3},
    {'note',  85, 4},
    {'note',  86, 10},
    {'note',  87, 12},
    {'note',  88, 14},
    {'note',  89, 16}
  }
  --left to right, 52 is aux key to column 1
  apcmini.aux.row = {
    {'note',  64, 1},
    {'note',  65, 2},
    {'note',  66, 3},
    {'note',  67, 4},
    {'note',  68, 10},
    {'note',  69, 12},
    {'note',  70, 14},
    {'note',  71, 16}
  }

return apcmini
