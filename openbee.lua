local apiarySide = "left"
local chestSide = "diamond_3"
local chestDir = "up"
local analyzerDir = "east"
local useReferenceBees = true

local traitPriority = {"speciesChance", "fertility", "speed", "nocturnal", "tolerantFlyer", "caveDwelling", "lifespan", "temperatureTolerance", "humidityTolerance", "effect", "flowering", "flowerProvider", "territory"}

local inv = peripheral.wrap(chestSide)
local invSize = inv.getInventorySize()

local apiary = peripheral.wrap(apiarySide)

local princesses = {}
local princessesBySpecies = {}
local drones = {}
local dronesBySpecies = {}
local queens = {}
local referenceDronesBySpecies = {}
local referencePrincessesBySpecies = {}

-- utility functions

function choose(list1, list2)
  local newList = {}
  if list2 then
    for i = 1, #list2 do
      for j = 1, #list1 do
        if list1[j] ~= list2[i] then
          table.insert(newList, {list1[j], list2[i]})
        end
      end
    end
  else
    for i = 1, #list1 do
      for j = i, #list1 do
        if list1[i] ~= list1[j] then
          table.insert(newList, {list1[i], list1[j]})
        end
      end
    end
  end
  return newList
end

-- fix for some versions returning bees.species.*
function fixName(name)
  return name:gsub("bees%.species%.",""):gsub("^.", string.upper)
end

-- mutation graph

local mutations = {}

function addMutateTo(parent1, parent2, offspring, chance)
  if mutations[parent1] then
    if mutations[parent1].mutateTo[offspring] then
      mutations[parent1].mutateTo[offspring][parent2] = chance
    else
      mutations[parent1].mutateTo[offspring] = {[parent2] = chance}
    end
  else
    mutations[parent1] = {
      mutateTo = {[offspring]={[parent2] = chance}}
    }
  end
end

-- build mutation graph
for _, mut in pairs(apiary.getBeeBreedingData()) do
  addMutateTo(mut.allele1, mut.allele2, mut.result, mut.chance)
  addMutateTo(mut.allele2, mut.allele1, mut.result, mut.chance)
end

-- percent chance of 2 species turning into a target species
function mutateSpeciesChance(species1, species2, targetSpecies)
  local chance = {}
  if species1 == species2 then
    chance[species1] = 100
  else
    chance[species1] = 50
    chance[species2] = 50
  end
  for species, mutates in pairs(mutations[species1].mutateTo) do
    local mutateChance = mutates[species2]
    if mutateChance ~= nil then
      chance[species] = mutateChance
      chance[species1] = chance[species1] - mutateChance / 2
      chance[species2] = chance[species2] - mutateChance / 2
    end
  end
  return chance[targetSpecies] or 0.0
end

-- percent chance of 2 bees turning into target species
function mutateBeeChance(princess, drone, targetSpecies)
  if princess.beeInfo.active then
    if drone.beeInfo.active then
      return (mutateSpeciesChance(princess.beeInfo.active.species, drone.beeInfo.active.species, targetSpecies) / 4
             +mutateSpeciesChance(princess.beeInfo.inactive.species, drone.beeInfo.active.species, targetSpecies) / 4
             +mutateSpeciesChance(princess.beeInfo.active.species, drone.beeInfo.inactive.species, targetSpecies) / 4
             +mutateSpeciesChance(princess.beeInfo.inactive.species, drone.beeInfo.inactive.species, targetSpecies) / 4)
    end
  elseif drone.beeInfo.active then
  else
    return mutateSpeciesChance(princess.beeInfo.displayName, drone.beeInfo.displayName, targetSpecies)
  end
end

-- scoring functions

function makeNumberScorer(trait, default)
  local function scorer(bee)
    if bee.beeInfo.active then
      return (bee.beeInfo.active[trait] + bee.beeInfo.inactive[trait]) / 2
    else
      return default
    end
  end
  return scorer
end

function makeBooleanScorer(trait)
  local function scorer(bee)
    if bee.beeInfo.active then
      return ((bee.beeInfo.active[trait] and 1 or 0) + (bee.beeInfo.inactive[trait] and 1 or 0)) / 2
    else
      return 0
    end
  end
  return scorer
end

function makeTableScorer(trait, default, lookup)
  local function scorer(bee)
    if bee.beeInfo.active then
      return ((lookup[bee.beeInfo.active[trait]] or default) + (lookup[bee.beeInfo.inactive[trait]] or default)) / 2
    else
      return default
    end
  end
  return scorer
end

local scoresTolerance = {
  ["None"]   = 0,
  ["Up 1"]   = 1,
  ["Up 2"]   = 2,
  ["Up 3"]   = 3,
  ["Up 4"]   = 4,
  ["Up 5"]   = 5,
  ["Down 1"] = 1,
  ["Down 2"] = 2,
  ["Down 3"] = 3,
  ["Down 4"] = 4,
  ["Down 5"] = 5,
  ["Both 1"] = 2,
  ["Both 2"] = 4,
  ["Both 3"] = 6,
  ["Both 4"] = 8,
  ["Both 5"] = 10
}

local scoresFlowerProvider = {
  ["None"] = 5,
  ["Rocks"] = 4,
  ["Flowers"] = 3,
  ["Mushroom"] = 2,
  ["Cacti"] = 1,
  ["Exotic Flowers"] = 0,
  ["Jungle"] = 0
}

local scoring = {
  ["fertility"] = makeNumberScorer("fertility", 1),
  ["flowering"] = makeNumberScorer("flowering", 1),
  ["speed"] = makeNumberScorer("speed", 1),
  ["lifespan"] = makeNumberScorer("lifespan", 1),
  ["nocturnal"] = makeBooleanScorer("nocturnal"),
  ["tolerantFlyer"] = makeBooleanScorer("tolerantFlyer"),
  ["caveDwelling"] = makeBooleanScorer("caveDwelling"),
  ["effect"] = makeBooleanScorer("effect"),
  ["temperatureTolerance"] = makeTableScorer("temperatureTolerance", 0, scoresTolerance),
  ["humidityTolerance"] = makeTableScorer("humidityTolerance", 0, scoresTolerance),
  ["flowerProvider"] = makeTableScorer("flowerProvider", 0, scoresFlowerProvider),
  ["territory"] = function(bee)
    if bee.beeInfo.active then
      return ((bee.beeInfo.active.territory[1] * bee.beeInfo.active.territory[2] * bee.beeInfo.active.territory[3]) +
                   (bee.beeInfo.inactive.territory[1] * bee.beeInfo.inactive.territory[2] * bee.beeInfo.inactive.territory[3])) / 2
    else
      return 0
    end
  end
}

function compareBees(a, b)
  for trait, scorer in pairs(scoring) do
    local aScore = scorer(a)
    local bScore = scorer(b)
    if aScore ~= bScore then
      return aScore > bScore
    end
  end
  return true
end

function compareMates(a, b)
  for i, trait in ipairs(traitPriority) do
    if a[trait] ~= b[trait] then
      return a[trait] > b[trait]
    end
  end
  return true
end

-- inventory functions

function addBySpecies(beesBySpecies, bee)
  if bee.beeInfo.isAnalyzed then
    if beesBySpecies[bee.beeInfo.active.species] == nil then
      beesBySpecies[bee.beeInfo.active.species] = {bee}
    else
      table.insert(beesBySpecies[bee.beeInfo.active.species], bee)
    end
    if bee.beeInfo.inactive.species ~= bee.beeInfo.active.species then
      if beesBySpecies[bee.beeInfo.inactive.species] == nil then
        beesBySpecies[bee.beeInfo.inactive.species] = {bee}
      else
        table.insert(beesBySpecies[bee.beeInfo.inactive.species], bee)
      end
    end
  else
    if beesBySpecies[bee.beeInfo.displayName] == nil then
      beesBySpecies[bee.beeInfo.displayName] = {bee}
    else
      table.insert(beesBySpecies[bee.beeInfo.displayName], bee)
    end
  end
end

function catalogBees()
  princesses = {}
  princessesBySpecies = {}
  drones = {}
  dronesBySpecies = {}
  queens = {}
  referenceDronesBySpecies = {}
  referencePrincessesBySpecies = {}

  inv.condenseItems()
  print(string.format("scanning %d slots", invSize))
  local referenceBeeCount = 0
  local freeSlot = 0
  for slot = 1, invSize do
    local bee = inv.getStackInSlot(slot)
    if bee ~= nil then
      if bee.beeInfo ~= nil then
        if bee.beeInfo.isAnalyzed == false then
          local newSlot = analyzeBee(slot)
          if newSlot ~= nil and newSlot ~= slot then
            inv.swapStacks(slot, newSlot)
          end
          bee = inv.getStackInSlot(slot)
        end
        -- fix for some versions returning mangled name
        bee.beeInfo.active.species = fixName(bee.beeInfo.active.species)
        bee.beeInfo.inactive.species = fixName(bee.beeInfo.active.species)
        bee.beeInfo.displayName = fixName(bee.beeInfo.active.species)
        if useReferenceBees then
          local referenceBySpecies = nil
          if bee.rawName == "item.beedronege" then -- drones
            referenceBySpecies = referenceDronesBySpecies
          elseif bee.rawName == "item.beeprincessge" then -- princess
            referenceBySpecies = referencePrincessesBySpecies
          end
          if referenceBySpecies ~= nil and bee.beeInfo.isAnalyzed == true then
            if bee.beeInfo.active.species == bee.beeInfo.inactive.species then
              local species = bee.beeInfo.active.species
              if referenceBySpecies[species] == nil or
                  compareBees(bee, referenceBySpecies[species]) then
                if referenceBySpecies[species] == nil then
                  referenceBeeCount = referenceBeeCount + 1
                  if slot ~= referenceBeeCount then
                    inv.swapStacks(slot, referenceBeeCount)
                  end
                  bee.slot = referenceBeeCount
                else
                  inv.swapStacks(slot, referenceBySpecies[species].slot)
                  bee.slot = referenceBySpecies[species].slot
                end
                referenceBySpecies[species] = bee
                if bee.qty > 1 then
                  -- drones stack, allowed to use some if more than one
                  table.insert(drones, bee)
                  addBySpecies(dronesBySpecies, bee)
                end
              end
            end
          end
        end
      end
    else
      freeSlot = slot
      break
    end
  end
  print(string.format("found %d reference bees", referenceBeeCount))
  for slot = 1 + referenceBeeCount, invSize do
    local bee = inv.getStackInSlot(slot)
    if bee ~= nil then
      bee.slot = slot
      if bee.beeInfo ~= nil then
        -- fix for some versions returning mangled name
        bee.beeInfo.active.species = fixName(bee.beeInfo.active.species)
        bee.beeInfo.inactive.species = fixName(bee.beeInfo.active.species)
        bee.beeInfo.displayName = fixName(bee.beeInfo.active.species)
      end
      -- check if reference bee
      if bee.rawName == "item.beedronege" then -- drones
        table.insert(drones, bee)
        addBySpecies(dronesBySpecies, bee)
      elseif bee.rawName == "item.beeprincessge" then -- princess
        table.insert(princesses, bee)
        addBySpecies(princessesBySpecies, bee)
      elseif bee.id == 13339 then -- queens
        table.insert(queens, bee)
      end
    end
  end
  print(string.format("found %d queens, %d princesses, %d drones",
      #queens, #princesses, #drones))
end

-- apiary functions

function clearApiary()
  local beeCount = 0
  local invSlot = 1
  for slot = 3, 9 do
    local stuff = apiary.getStackInSlot(slot)
    if stuff ~= nil then
      while inv.getStackInSlot(invSlot) ~= nil do
        invSlot = invSlot + 1
      end
      if stuff.rawName == "item.beedronege" or stuff.rawName == "item.beeprincessge" then
        beeCount = beeCount + 1
        apiary.pushItem(chestDir, slot, 64, invSlot)
      else
        local found = false
        local freeSlot = 0
        for productSlot = 1, invSize do
          local item = inv.getStackInSlot(productSlot)
          if item == nil then
            freeSlot = productSlot
          elseif stuff.name == item.name and (item.maxSize - item.qty) >= stuff.qty then
            apiary.pushItem(chestDir, slot, 64, productSlot)
            found = true
            break
          end
        end
        if not found then
          apiary.pushItem(chestDir, slot, 64, freeSlot)
        end
      end
    end
  end
  return beeCount
end

function clearAnalyzer()
  local invSlot = 1
  for analyzerSlot = 9, 12 do
    while inv.getStackInSlot(invSlot) ~= nil do
      invSlot = invSlot + 1
      if invSlot > invSize then
        error("chest is full")
      end
    end
    inv.pullItem(analyzerDir, analyzerSlot, 64, invSlot)
  end
end

function analyzeBee(slot)
  clearAnalyzer()
  write("analyzing bee ")
  write(slot)
  write(".")
  if inv.pushItem(analyzerDir, slot, 64, 3) > 0 then
    while inv.pullItem(analyzerDir, 9, 64, slot) == 0 do
      if inv.getStackInSlot(slot) ~= nil then
        slot = slot + 1
        if slot > invSize then
          error("chest is full")
        end
      end
      write(".")
      sleep(5)
    end
  else
    print("Missing Analyzer")
    return nil
  end
  printBee(inv.getStackInSlot(slot))
  return slot
end

function waitApiary()
  write("waiting for apiary")
  while apiary.getStackInSlot(1) ~= nil or apiary.getStackInSlot(2) ~= nil do
    write(".")
    sleep(5)
    if clearApiary() > 0 then
      -- breeding cycle done
      break
    end
  end
  clearApiary()
  print()
end

function breedBees(princess, drone)
  clearApiary()
  waitApiary()
  apiary.pullItem(chestDir, princess.slot, 1, 1)
  apiary.pullItem(chestDir, drone.slot, 1, 2)
  waitApiary()
end

function beeName(bee)
  if bee.beeInfo.active then
    return bee.slot .. "=" .. bee.beeInfo.active.species:sub(1,3) .. "-" ..
                              bee.beeInfo.inactive.species:sub(1,3)
  else
    return bee.slot .. "=" .. bee.beeInfo.displayName:sub(1,3)
  end
end

function printBee(bee)
  if bee.beeInfo.active then
    local active = bee.beeInfo.active
    local inactive = bee.beeInfo.inactive
    if active.species ~= inactive.species then
      write(string.format("%s-%s", active.species, inactive.species))
    else
      write(active.species)
    end
    if bee.rawName == "item.beedronege" then
      write(" Drone")
    elseif bee.rawName == "item.beeprincessge" then
      write(" Princess")
    else
      write(" Queen")
    end
    --write((active.nocturnal and " Nocturnal" or " "))
    --write((active.tolerantFlyer and " Flyer" or " "))
    --write((active.caveDwelling and " Cave" or " "))
    print()
    --print(string.format("Fert: %d  Speed: %d  Lifespan: %d", active.fertility, active.speed, active.lifespan))
  else
  end
end

function getMate(beeSpecies, targetSpecies)
  for i, parents in ipairs(apiary.getBeeParents(targetSpecies)) do
    if beeSpecies == parents.allele1 then
      return parents.allele2
    elseif beeSpecies == parents.allele2 then
      return parents.allele1
    end
  end
end

-- selects best pair for target species
--   or initiates breeding of lower species
function selectPair(targetSpecies)
  print("targetting "..targetSpecies)
  if #apiary.getBeeParents(targetSpecies) > 0 then
    for _, s in ipairs(apiary.getBeeParents(targetSpecies)[1].specialConditions) do
      print("    ", s)
    end
  end
  local mateCombos = choose(princesses, drones)
  local mates = {}
  for i, v in ipairs(mateCombos) do
    local chance = mutateBeeChance(v[1], v[2], targetSpecies)
    if chance > 0 then
      local newMates = {
        ["princess"] = v[1],
        ["drone"] = v[2],
        ["speciesChance"] = chance
      }
      for trait, scorer in pairs(scoring) do
        newMates[trait] = (scorer(v[1]) + scorer(v[2])) / 2
      end
      table.insert(mates, newMates)
    end
  end
  if #mates > 0 then
    table.sort(mates, compareMates)
    for i = math.min(#mates, 10), 1, -1 do
      local parents = mates[i]
      print(beeName(parents.princess), " ", beeName(parents.drone), " ", parents.speciesChance, " ", parents.fertility, " ",
            parents.flowering, " ", parents.nocturnal, " ", parents.tolerantFlyer, " ", parents.caveDwelling, " ",
            parents.lifespan, " ", parents.temperatureTolerance, " ", parents.humidityTolerance)
    end
    return mates[1]
  else
    -- check for reference bees and breed if drone count is 1
    if referencePrincessesBySpecies[targetSpecies] ~= nil and
        referenceDronesBySpecies[targetSpecies] ~= nil then
      return {
        ["princess"] = referencePrincessesBySpecies[targetSpecies],
        ["drone"] = referenceDronesBySpecies[targetSpecies]
      }
    end
    -- attempt lower tier bee
    print("try lower tier of "..targetSpecies)
    local parentss = apiary.getBeeParents(targetSpecies)
    if #parentss > 0 then
      table.sort(parentss, function(a, b) return a.chance > b.chance end)
      local trySpecies = {}
      for i, parents in ipairs(parentss) do
        if princessesBySpecies[parents.allele2] == nil and trySpecies[parents.allele2] == nil then
          table.insert(trySpecies, parents.allele2)
          trySpecies[parents.allele2] = true
        end
        if princessesBySpecies[parents.allele1] == nil and trySpecies[parents.allele1] == nil then
          table.insert(trySpecies, parents.allele1)
          trySpecies[parents.allele1] = true
        end
      end
      for _, species in ipairs(trySpecies) do
        local mates = selectPair(species)
        if mates ~= nil then
          return mates
        end
      end
    end
    return nil
  end
end

function isPureBred(bee1, bee2, targetSpecies)
  if bee1.beeInfo.active and bee2.beeInfo.active then
    if bee1.beeInfo.active.species == bee1.beeInfo.inactive.species and
        bee2.beeInfo.active.species == bee2.beeInfo.inactive.species and
        bee1.beeInfo.active.species == bee2.beeInfo.active.species and
        (targetSpecies == nil or bee1.beeInfo.active.species == targetSpecies) then
      return true
    end
  end
  return false
end

local tArgs = { ... }
if #tArgs ~= 1 then
  print("Enter target species")
  return
end

clearApiary()
clearAnalyzer()
catalogBees()
while true do
  if #princesses == 0 then
    write("Please add more princesses and press [Enter]")
    io.read("*l")
    catalogBees()
  elseif #drones == 0 and next(referenceDronesBySpecies) == nil then
    write("Please add more drones and press [Enter]")
    io.read("*l")
    catalogBees()
  else
    local mates = selectPair(tArgs[1])
    if mates ~= nil then
      if isPureBred(mates.princess, mates.drone, tArgs[1]) then
        break
      else
        breedBees(mates.princess, mates.drone)
        catalogBees()
      end
    else
      write("Please add more bee species and press [Enter]")
      io.read("*l")
      catalogBees()
    end
  end
end
print("Bees are purebred")
