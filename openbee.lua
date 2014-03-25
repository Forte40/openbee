local apiarySide = "right"
local chestSide = "top"
local chestDir = "up"
local analyzerDir = "east"

local traitPriority = {"fertility", "speed", "nocturnal", "tolerantFlyer", "caveDwelling", "lifespan", "temperatureTolerance", "humidityTolerance", "effect", "flowerProvider", "territory"}

local inv = peripheral.wrap(chestSide)
local invSize = inv.getInventorySize()

local bees = {}
local princesses = {}
local drones = {}
local queens = {}


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
      mutateTo = {[offspring]={[parent2] = chance}},
      mutateFrom = {}
    }
  end
  if mutations[offspring] then
    table.insert(mutations[offspring].mutateFrom, {parent1, parent2})
  else
    mutations[offspring] = {mutateFrom = {{parent1, parent2}},
                            mutateTo = {}}
  end
end

function addOffspring(offspring, chance, parentss)
  for i, parents in ipairs(parentss) do
    addMutateTo(parents[1], parents[2], offspring, chance)
    addMutateTo(parents[2], parents[1], offspring, chance)
  end
end

addOffspring("Common", .15, choose({"Forest", "Meadows"}))
addOffspring("Cultivated", .12, choose({"Common"}, {"Forest", "Meadows"}))
addOffspring("Diligent", .10, {{"Cultivated", "Common"}})
addOffspring("Unweary", .08, {{"Diligent", "Cultivated"}})
addOffspring("Industrious", .08, {{"Unweary", "Diligent"}})
addOffspring("Noble", .10, {{"Cultivated", "Common"}})
addOffspring("Majestic", .08, {{"Noble", "Cultivated"}})
addOffspring("Imperial", .08, {{"Majestic", "Noble"}})

function catalogBees()
  bees = {}
  princesses = {}
  drones = {}
  queens = {}
  print(string.format("scanning %d slots", invSize))
  for i = 1, invSize do
    local bee = inv.getStackInSlot(i)
    if bee ~= nil then
      bee.slot = i
      bees[i] = bee
      if bee.id == 13340 then -- drones
        table.insert(drones, bee)
      elseif bee.id == 13341 then -- princess
        table.insert(princesses, bee)
      elseif bee.id == 13339 then -- queens
        table.insert(queens, bee)
      else -- error
        print(string.format("non-bee item in slot %d", i))
      end
    end
  end
  print(string.format("found %d queens, %d princesses, %d drones",
      #queens, #princesses, #drones))
end

function canMutateTo(bee, targetSpecies)
  if bee.beeInfo.active then
    if (bee.beeInfo.active.species == targetSpecies
            or mutations[bee.beeInfo.active.species].mutateTo[targetSpecies] ~= nil) then
      return bee.beeInfo.active.species
    elseif (bee.beeInfo.inactive.species == targetSpecies
            or mutations[bee.beeInfo.inactive.species].mutateTo[targetSpecies] ~= nil) then
      return bee.beeInfo.inactive.species
    end
  else
    if (bee.beeInfo.displayName == targetSpecies
            or mutations[bee.beeInfo.displayName].mutateTo[targetSpecies] ~= nil) then
      return bee.beeInfo.displayName
    end
  end
end

-- percent chance of 2 species turning into a target species
function mutationChance(species1, species2, targetSpecies)
  local chance = {}
  if species1 == species2 then
    chance[species1] = 1.0
  else
    chance[species1] = 0.5
    chance[species2] = 0.5
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
function mutateChance(princess, drone, targetSpecies)
  if princess.beeInfo.active then
    if drone.beeInfo.active then
      return (mutationChance(princess.beeInfo.active.species, drone.beeInfo.active.species, targetSpecies) / 4
             +mutationChance(princess.beeInfo.inactive.species, drone.beeInfo.active.species, targetSpecies) / 4
             +mutationChance(princess.beeInfo.active.species, drone.beeInfo.inactive.species, targetSpecies) / 4
             +mutationChance(princess.beeInfo.inactive.species, drone.beeInfo.inactive.species, targetSpecies) / 4)
    end
  elseif drone.beeInfo.active then
  else
    return mutationChance(princess.beeInfo.displayName, drone.beeInfo.displayName, targetSpecies)
  end
end

function beeName(bee)
  if bee.beeInfo.active then
    return bee.beeInfo.active.species.."-"..bee.beeInfo.inactive.species
  else
    return bee.beeInfo.displayName
  end
end

-- selects best pair for target species
--   or initiates breeding of lower species
function selectPair(targetSpecies)
  print("targetting "..targetSpecies)
  local selectPrincesses = {}
  local princessSpecies = {}
  for i, bee in ipairs(princesses) do
    local species = canMutateTo(bee, targetSpecies)
    if species ~= nil then
      table.insert(selectPrincesses, bee)
      table.insert(princessSpecies, species)
    end
  end
  local selectDrones = {}
  local droneSpecies = {}
  for i, bee in ipairs(drones) do
    local species = canMutateTo(bee, targetSpecies)
    if species ~= nil then
      table.insert(selectDrones, bee)
      table.insert(droneSpecies, species)
    end
  end
  if #selectPrincesses == 0 then
    print("missing princess")
    if #droneSpecies > 0 then
      for i, species in ipairs(droneSpecies) do
        for j, parents in ipairs(mutations[targetSpecies].mutateFrom) do
          if species == parents[1] then
            princessSpecies[parents[2]] = true
          end
        end
      end
    else
      for i, parents in ipairs(mutations[targetSpecies].mutateFrom) do
        princessSpecies[parents[1]] = true
        princessSpecies[parents[2]] = true
      end
    end
    print("need princess of type ", textutils.serialize(princessSpecies))
    for species, _ in pairs(princessSpecies) do
      selectPair(species)
      break
    end
  elseif #selectDrones == 0 then
    print("missing drone")
    if #selectPrincesses > 0 then
      for i, species in ipairs(selectPrincesses) do
        for j, parents in ipairs(mutations[targetSpecies].mutateFrom) do
          if species == parents[1] then
            droneSpecies[parents[2]] = true
          end
        end
      end
    else
      for i, parents in ipairs(mutations[targetSpecies].mutateFrom) do
        droneSpecies[parents[1]] = true
        droneSpecies[parents[2]] = true
      end
    end
    print("need drone of type ", textutils.serialize(princessSpecies))
    for species, _ in pairs(droneSpecies) do
      selectPair(species)
      break
    end
  else
    local mates = choose(selectPrincesses, selectDrones)
    for i, v in ipairs(mates) do
      print(beeName(v[1]), beeName(v[2]), mutateChance(v[1], v[2], targetSpecies))
    end
  end
end

local tArgs = { ... }
if #tArgs ~= 1 then
  print("Enter target species")
  return
end

catalogBees()
selectPair(tArgs[1])
