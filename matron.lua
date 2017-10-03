-- configuration ---------
local princessSlot = 26
local droneSlot = 27
local otherSlot = 1
local chestDir = "up"
local redstoneSide = "top"
local wait = 5
--------------------------

local apiaries = {}
local stats = {["Generations"] = 0}
local apiaryHeuristic = 'apiculture'

function printStats()
  term.clear()
  term.setCursorPos(1, 1)
  print(string.format("Watching %d apiaries", #apiaries))
  print()
  for stat, value in pairs(stats) do
    print(string.format("%s : %d", stat, value))
  end
end

-- fix for yet another API change from openp
function getAllBees(inv)
  local notbees = inv.getAllStacks()
  local bees = {}
  for slot, bee in pairs(notbees) do
    bees[slot] = bee.all()
  end
  return bees
end

-- find apiaries
local sides = peripheral.getNames()
for _, side in ipairs(sides) do
  if peripheral.getType(side):find(apiaryHeuristic) then
    table.insert(apiaries, peripheral.wrap(side))
  end
end
if #apiaries == 0 then
  error("No apiaries")
else
  printStats()
end

while true do
  local statChange = false
  rs.setOutput(redstoneSide, true)
  for i, apiary in ipairs(apiaries) do
    -- look for outputs
    local inv = getAllBees(apiary)
    local foundDrone = false
    if inv[2] ~= nil then
      foundDrone = true
    end
    local foundPrincess = false
    for slot, bee in pairs(inv) do
      if slot >= 3 and slot <= 9 then
        if bee.raw_name == "item.for.beeprincessge" then
          apiary.pushItemIntoSlot(chestDir, slot, 1, princessSlot)
          foundPrincess = true
        elseif foundDrone == false and bee.raw_name == "item.for.beedronege" then
          apiary.pushItemIntoSlot(chestDir, slot, 1, droneSlot)
          apiary.pushItemIntoSlot(chestDir, slot, 64)
          foundDrone = true
        else
          apiary.pushItemIntoSlot(chestDir, slot, 64)
          if bee.raw_name ~= "item.for.beedronege" then
            statChange = true
            if stats[bee.name] ~= nil then
              stats[bee.name] = stats[bee.name] + bee.qty
            else
              stats[bee.name] = bee.qty
            end
          end
        end
      end
    end
    -- breed princess and 1 drone
    if apiary.getStackInSlot(1) == nil then
      if apiary.pullItem(chestDir, princessSlot, 1, 1) > 0 then
        stats["Generations"] = stats["Generations"] + 1
      end
      apiary.pullItem(chestDir, droneSlot, 1, 2)
    end
  end
  rs.setOutput(redstoneSide, false)
  if statChange then
    printStats()
  end
  sleep(wait)
end
