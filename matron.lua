-- configuration ---------
local princessSlot = 26
local droneSlot = 27
local otherSlot = 1
local chestDir = "up"
local redstoneSide = "top"
local wait = 5
--------------------------

local apiaries = {}

-- find apiaries
local sides = peripheral.getNames()
for _, side in ipairs(sides) do
  if peripheral.getType(side) == "apiculture_0" then
    table.insert(apiaries, peripheral.wrap(side))
  end
end
if #apiaries == 0 then
  error("No apiaries")
else
  print("Found ",#apiaries, " apiaries")
end

while true do
  rs.setOutput(redstoneSide, true)
  for i, apiary in ipairs(apiaries) do
    -- look for outputs
    local inv = apiary.getAllStacks()
    local foundDrone = false
    local foundPrincess = false
    for slot, beeData in pairs(inv) do
      if slot >= 3 and slot <= 9 then
        if beeData.rawName == "item.beeprincessge" then
          apiary.pushItemIntoSlot(chestDir, slot, 1, princessSlot)
          foundPrincess = true
        elseif foundDrone == false and beeData.rawName == "item.beedronege" then
          apiary.pushItemIntoSlot(chestDir, slot, 1, droneSlot)
          apiary.pushItemIntoSlot(chestDir, slot, 64)
          foundDrone = true
        else
          apiary.pushItemIntoSlot(chestDir, slot, 64)
        end
      end
    end
    -- breed princess and 1 drone
    if foundPrincess then
      apiary.pullItem(chestDir, princessSlot, 1, 1)
      apiary.pullItem(chestDir, droneSlot, 1, 2)
    end
  end
  rs.setOutput(redstoneSide, false)
  sleep(wait)
end