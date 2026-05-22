-- Poison: toxic, radioactive, aggressive
-- Black → dark green → vivid green → radioactive yellow-green
return {
  {  0,   0,   0},   -- z=0:  off
  {  0,  12,   0},   -- z=1
  {  0,  24,   0},   -- z=2
  {  0,  36,   0},   -- z=3
  {  0,  48,   2},   -- z=4
  {  2,  58,   4},   -- z=5
  {  4,  68,   6},   -- z=6
  {  8,  76,   6},   -- z=7
  { 14,  84,   4},   -- z=8
  { 22,  92,   4},   -- z=9
  { 32, 100,   4},   -- z=10
  { 42, 108,   4},   -- z=11
  { 54, 114,   6},   -- z=12
  { 66, 120,   8},   -- z=13
  { 80, 124,  12},   -- z=14
  { 96, 127,  20},   -- z=15: radioactive glow
}
