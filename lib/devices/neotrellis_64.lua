local trellis = include('midigrid/lib/devices/generic_device')

-- This is in reference to the trellicopter setup:
-- https://github.com/airportpeople/trellicopter

trellis.grid_notes= {
    {40, 41, 42, 43, 44, 45, 46, 47},
    {48, 49, 50, 51, 52, 53, 54, 55},
    {56, 57, 58, 59, 60, 61, 62, 63},
    {64, 65, 66, 67, 68, 69, 70, 71},
    {72, 73, 74, 75, 76, 77, 78, 79},
    {80, 81, 82, 83, 84, 85, 86, 87},
    {88, 89, 90, 91, 92, 93, 94, 95},
    {96, 97, 98, 99, 100, 101, 102, 103}
}

trellis.brightness_map = {0, 1, 2, 3, 10, 20, 30, 50, 60, 70, 91, 100, 109, 118, 127}

trellis.quad_leds = {}

return trellis