local version = {
  ["major"] = 2,
  ["minor"] = 2,
  ["patch"] = 1
}

function loadFile(fileName)
  local f = fs.open(fileName, "r")
  if f ~= nil then
    local data = f.readAll()
    f.close()
    return textutils.unserialize(data)
  end
end

function saveFile(fileName, data)
  local f = fs.open(fileName, "w")
  f.write(textutils.serialize(data))
  f.close()
end

local config = loadFile("bee.config")
if config == nil then
  config = {
    ["apiarySide"] = "left",
    ["chestSide"] = "top",
    ["chestDir"] = "up",
    ["productDir"] = "down",
    ["analyzerDir"] = "east",
    ["ignoreSpecies"] = {
      "Leporine"
    }
  }
  saveFile("bee.config", config)
end

local BEE_DRONE = 'item.for.beedronege'
local BEE_PRINCESS = 'item.for.beeprincessge'
local BEE_QUEEN = 'item.for.beequeenge'

local useAnalyzer = true
local useReferenceBees = true

local traitPriority = {
  "speciesChance", 
  "speed", 
  "fertility", 
  "nocturnal", 
  "tolerantFlyer", 
  "caveDwelling", 
  "temperatureTolerance", 
  "humidityTolerance", 
  "effect", 
  "flowering", 
  "flowerProvider", 
  "territory"
}

function setPriorities(priority)
  local species = nil
  local priorityNum = 1
  for traitNum, trait in ipairs(priority) do
    local found = false
    for traitPriorityNum = 1, #traitPriority do
      if trait == traitPriority[traitPriorityNum] then
        found = true
        if priorityNum ~= traitPriorityNum then
          table.remove(traitPriority, traitPriorityNum)
          table.insert(traitPriority, priorityNum, trait)
        end
        priorityNum = priorityNum + 1
        break
      end
    end
    if not found then
      species = trait
    end
  end
  return species
end

-- logging ----------------------------

local logFile
function setupLog()
  local logCount = 0
  while fs.exists(string.format("bee.%d.log", logCount)) do
    logCount = logCount + 1
  end
  logFile = fs.open(string.format("bee.%d.log", logCount), "w")
  return string.format("bee.%d.log", logCount)
end

function log(msg)
  msg = msg or ""
  logFile.write(tostring(msg))
  logFile.flush()
  io.write(msg)
end

function logLine(...)
  for i, msg in ipairs(arg) do
    if msg == nil then
      msg = ""
    end
    logFile.write(msg)
    io.write(msg)
  end
  logFile.write("\n")
  logFile.flush()
  io.write("\n")
end

function getPeripherals()
  local names = table.concat(peripheral.getNames(), ", ")
  local chestPeripheral = peripheral.wrap(config.chestSide)
  if chestPeripheral == nil then
    error("Bee chest not found at " .. config.chestSide .. ".  Valid config values are " .. names .. ".")
  end
  local apiaryPeripheral = peripheral.wrap(config.apiarySide)
  if apiaryPeripheral == nil then
    error("Apiary not found at " .. config.apiarySide .. ".  Valid config values are " .. names .. ".")
  end
  -- check config directions
  if not pcall(function () chestPeripheral.pullItem(config.analyzerDir, 9) end) then
    logLine("Analyzer direction incorrect.  Direction should be relative to bee chest.")
    useAnalyzer = false
  end
  return chestPeripheral, apiaryPeripheral
end

-- utility functions ------------------

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

-- fix for yet another API change from openp
function getAllBees(inv)
  local notbees = inv.getAllStacks()
  local bees = {}
  for slot, bee in pairs(notbees) do
    bees[slot] = bee.all()
  end
  return bees
end

function getBeeInSlot(inv, slot)
  return inv.getStackInSlot(slot)
end

-- fix for some versions returning bees.species.*
local nameFix = {}
function fixName(name)
  if type(name) == "table" then
    name = name.name
  end
  local newName = name:gsub("bees%.species%.",""):gsub("^.", string.upper)
  if name ~= newName then
    nameFix[newName] = name
  end
  return newName
end

function fixBee(bee)
  if bee.individual ~= nil then
    bee.individual.displayName = fixName(bee.individual.displayName)
    if bee.individual.isAnalyzed then
      bee.individual.active.species.name = fixName(bee.individual.active.species.name)
      bee.individual.inactive.species.name = fixName(bee.individual.inactive.species.name)
    end
  end
  return bee
end

function fixParents(parents)
  parents.allele1 = fixName(parents.allele1)
  parents.allele2 = fixName(parents.allele2)
  if parents.result then
    parents.result = fixName(parents.result)
  end
  return parents
end

function beeName(bee)
  if bee.individual.active then
    return bee.slot .. "=" .. bee.individual.active.species.name:sub(1,3) .. "-" ..
                              bee.individual.inactive.species.name:sub(1,3)
  else
    return bee.slot .. "=" .. bee.individual.displayName:sub(1,3)
  end
end

function printBee(bee)
  if bee.individual.isAnalyzed then
    local active = bee.individual.active
    local inactive = bee.individual.inactive
    if active.species.name ~= inactive.species.name then
      log(string.format("%s-%s", active.species.name, inactive.species.name))
    else
      log(active.species.name)
    end
    if bee.raw_name == BEE_DRONE then
      log(" Drone")
    elseif bee.raw_name == BEE_PRINCESS then
      log(" Princess")
    elseif bee.raw_name == BEE_QUEEN then
      log(" Queen")
    else
      log(" ??Error")
    end
    --log((active.nocturnal and " Nocturnal" or " "))
    --log((active.tolerantFlyer and " Flyer" or " "))
    --log((active.caveDwelling and " Cave" or " "))
    logLine()
    --logLine(string.format("Fert: %d  Speed: %d  Lifespan: %d", active.fertility, active.speed, active.lifespan))
  else
  end
end

-- mutations and scoring --------------

-- build mutation graph
function buildMutationGraph(apiary)
  local mutations = {}
  local beeNames = {}
  function addMutateTo(parent1, parent2, offspring, chance)
    beeNames[parent1] = true
    beeNames[parent2] = true
    beeNames[offspring] = true
    if mutations[parent1] ~= nil then
      if mutations[parent1].mutateTo[offspring] ~= nil then
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
  for _, parents in pairs(apiary.getBeeBreedingData()) do
    fixParents(parents)
    addMutateTo(parents.allele1, parents.allele2, parents.result, parents.chance)
    addMutateTo(parents.allele2, parents.allele1, parents.result, parents.chance)
  end
  mutations.getBeeParents = function(name)
    return apiary.getBeeParents((nameFix[name] or name))
  end
  return mutations, beeNames
end

function buildTargetSpeciesList(catalog, apiary)
  local targetSpeciesList = {}
  local parentss = apiary.getBeeBreedingData()
  for _, parents in pairs(parentss) do
    local skip = false
    for i, ignoreSpecies in ipairs(config.ignoreSpecies) do
      if parents.result == ignoreSpecies then
        skip = true
        break
      end
    end
    if not skip and
        ( -- skip if reference pair exists
          catalog.referencePrincessesBySpecies[parents.result] == nil or
          catalog.referenceDronesBySpecies[parents.result] == nil
        ) and
        ( -- princess 1 and drone 2 available
          catalog.princessesBySpecies[parents.allele1] ~= nil and
          catalog.dronesBySpecies[parents.allele2] ~= nil
        ) or
        ( -- princess 2 and drone 1 available
          catalog.princessesBySpecies[parents.allele2] ~= nil and
          catalog.dronesBySpecies[parents.allele1] ~= nil
        ) then
      table.insert(targetSpeciesList, parents.result)
    end
  end
  return targetSpeciesList
end

-- percent chance of 2 species turning into a target species
function mutateSpeciesChance(mutations, species1, species2, targetSpecies)
  local chance = {}
  if species1 == species2 then
    chance[species1] = 100
  else
    chance[species1] = 50
    chance[species2] = 50
  end
  if mutations[species1] ~= nil then
    for species, mutates in pairs(mutations[species1].mutateTo) do
      local mutateChance = mutates[species2]
      if mutateChance ~= nil then
        chance[species] = mutateChance
        chance[species1] = chance[species1] - mutateChance / 2
        chance[species2] = chance[species2] - mutateChance / 2
      end
    end
  end
  return chance[targetSpecies] or 0.0
end

-- percent chance of 2 bees turning into target species
function mutateBeeChance(mutations, princess, drone, targetSpecies)
  if princess.individual.isAnalyzed then
    if drone.individual.isAnalyzed then
      return (mutateSpeciesChance(mutations, princess.individual.active.species.name, drone.individual.active.species.name, targetSpecies) / 4
             +mutateSpeciesChance(mutations, princess.individual.inactive.species.name, drone.individual.active.species.name, targetSpecies) / 4
             +mutateSpeciesChance(mutations, princess.individual.active.species.name, drone.individual.inactive.species.name, targetSpecies) / 4
             +mutateSpeciesChance(mutations, princess.individual.inactive.species.name, drone.individual.inactive.species.name, targetSpecies) / 4)
    end
  elseif drone.individual.isAnalyzed then
  else
    return mutateSpeciesChance(princess.individual.displayName, drone.individual.displayName, targetSpecies)
  end
end

function buildScoring()
  function makeNumberScorer(trait, default)
    local function scorer(bee)
      if bee.individual.isAnalyzed then
        return (bee.individual.active[trait] + bee.individual.inactive[trait]) / 2
      else
        return default
      end
    end
    return scorer
  end

  function makeBooleanScorer(trait)
    local function scorer(bee)
      if bee.individual.isAnalyzed then
        return ((bee.individual.active[trait] and 1 or 0) + (bee.individual.inactive[trait] and 1 or 0)) / 2
      else
        return 0
      end
    end
    return scorer
  end

  function makeTableScorer(trait, default, lookup)
    local function scorer(bee)
      if bee.individual.isAnalyzed then
        return ((lookup[bee.individual.active[trait]] or default) + (lookup[bee.individual.inactive[trait]] or default)) / 2
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

  return {
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
      if bee.individual.isAnalyzed then
        return ((bee.individual.active.territory[1] * bee.individual.active.territory[2] * bee.individual.active.territory[3]) +
                     (bee.individual.inactive.territory[1] * bee.individual.inactive.territory[2] * bee.individual.inactive.territory[3])) / 2
      else
        return 0
      end
    end
  }
end

function compareBees(scorers, a, b)
  for _, trait in ipairs(traitPriority) do
    local scorer = scorers[trait]
    if scorer ~= nil then
      local aScore = scorer(a)
      local bScore = scorer(b)
      if aScore ~= bScore then
        return aScore > bScore
      end
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

function betterTraits(scorers, a, b)
  local traits = {}
  for _, trait in ipairs(traitPriority) do
    local scorer = scorers[trait]
    if scorer ~= nil then
      local aScore = scorer(a)
      local bScore = scorer(b)
      if bScore > aScore then
        table.insert(traits, trait)
      end
    end
  end
  return traits
end

-- cataloging functions ---------------

function addBySpecies(beesBySpecies, bee)
  if bee.individual.isAnalyzed then
    if beesBySpecies[bee.individual.active.species.name] == nil then
      beesBySpecies[bee.individual.active.species.name] = {bee}
    else
      table.insert(beesBySpecies[bee.individual.active.species.name], bee)
    end
    if bee.individual.inactive.species.name ~= bee.individual.active.species.name then
      if beesBySpecies[bee.individual.inactive.species.name] == nil then
        beesBySpecies[bee.individual.inactive.species.name] = {bee}
      else
        table.insert(beesBySpecies[bee.individual.inactive.species.name], bee)
      end
    end
  else
    if beesBySpecies[bee.individual.displayName] == nil then
      beesBySpecies[bee.individual.displayName] = {bee}
    else
      table.insert(beesBySpecies[bee.individual.displayName], bee)
    end
  end
end

function catalogBees(inv, scorers)
  catalog = {}
  catalog.princesses = {}
  catalog.princessesBySpecies = {}
  catalog.drones = {}
  catalog.dronesBySpecies = {}
  catalog.queens = {}
  catalog.referenceDronesBySpecies = {}
  catalog.referencePrincessesBySpecies = {}
  catalog.referencePairBySpecies = {}

  -- phase 0 -- analyze bees and ditch product
  inv.condenseItems()
  logLine(string.format("scanning %d slots", inv.size))
  if useAnalyzer == true then
    local analyzeCount = 0
    local bees = getAllBees(inv)
    for slot, bee in pairs(bees) do
      if bee.individual == nil then
        inv.pushItem(config.chestDir, slot)
      elseif not bee.individual.isAnalyzed then
        analyzeBee(inv, slot)
        analyzeCount = analyzeCount + 1
      end
    end
    logLine(string.format("analyzed %d new bees", analyzeCount))
  end
  -- phase 1 -- mark reference bees
  inv.condenseItems()
  local referenceBeeCount = 0
  local referenceDroneCount = 0
  local referencePrincessCount = 0
  local isDrone = nil
  local bees = getAllBees(inv)
  if useReferenceBees then
    for slot = 1, #bees do
      local bee = bees[slot]
      if bee.individual ~= nil then
        fixBee(bee)
        local referenceBySpecies = nil
        if bee.raw_name == BEE_DRONE then -- drones
          isDrone = true
          referenceBySpecies = catalog.referenceDronesBySpecies
        elseif bee.raw_name == BEE_PRINCESS then -- princess
          isDrone = false
          referenceBySpecies = catalog.referencePrincessesBySpecies
        else
          isDrone = nil
        end
        if referenceBySpecies ~= nil and bee.individual.isAnalyzed and bee.individual.active.species.name == bee.individual.inactive.species.name then
          local species = bee.individual.active.species.name
          if referenceBySpecies[species] == nil or
              compareBees(scorers, bee, referenceBySpecies[species]) then
            if referenceBySpecies[species] == nil then
              referenceBeeCount = referenceBeeCount + 1
              if isDrone == true then
                referenceDroneCount = referenceDroneCount + 1
              elseif isDrone == false then
                referencePrincessCount = referencePrincessCount + 1
              end
              if slot ~= referenceBeeCount then
                inv.swapStacks(slot, referenceBeeCount)
              end
              bee.slot = referenceBeeCount
            else
              inv.swapStacks(slot, referenceBySpecies[species].slot)
              bee.slot = referenceBySpecies[species].slot
            end
            referenceBySpecies[species] = bee
            if catalog.referencePrincessesBySpecies[species] ~= nil and catalog.referenceDronesBySpecies[species] ~= nil then
              catalog.referencePairBySpecies[species] = true
            end
          end
        end
      end
    end
    logLine(string.format("found %d reference bees, %d princesses, %d drones", referenceBeeCount, referencePrincessCount, referenceDroneCount))
    log("reference pairs")
    for species, _ in pairs(catalog.referencePairBySpecies) do
      log(", ")
      log(species)
    end
    logLine()
  end
  -- phase 2 -- ditch obsolete drones
  bees = getAllBees(inv)
  local extraDronesBySpecies = {}
  local ditchSlot = 1
  for slot = 1 + referenceBeeCount, #bees do
    local bee = bees[slot]
    fixBee(bee)
    bee.slot = slot
    -- remove analyzed drones where both the active and inactive species have
    --   a both reference princess and drone
    if (
      bee.raw_name == BEE_DRONE and
      bee.individual.isAnalyzed and (
        catalog.referencePrincessesBySpecies[bee.individual.active.species.name] ~= nil and
        catalog.referenceDronesBySpecies[bee.individual.active.species.name] ~= nil and
        catalog.referencePrincessesBySpecies[bee.individual.inactive.species.name] ~= nil and
        catalog.referenceDronesBySpecies[bee.individual.inactive.species.name] ~= nil
      )
    ) then
      local activeDroneTraits = betterTraits(scorers, catalog.referenceDronesBySpecies[bee.individual.active.species.name], bee)
      local inactiveDroneTraits = betterTraits(scorers, catalog.referenceDronesBySpecies[bee.individual.inactive.species.name], bee)
      if #activeDroneTraits > 0 or #inactiveDroneTraits > 0 then
        -- keep current bee because it has some trait that is better
        -- manipulate reference bee to have better yet less important attribute
        -- this ditches more bees while keeping at least one with the attribute
        -- the cataloging step will fix the manipulation
        for i, trait in ipairs(activeDroneTraits) do
          catalog.referenceDronesBySpecies[bee.individual.active.species.name].individual.active[trait] = bee.individual.active[trait]
          catalog.referenceDronesBySpecies[bee.individual.active.species.name].individual.inactive[trait] = bee.individual.inactive[trait]
        end
        for i, trait in ipairs(inactiveDroneTraits) do
          catalog.referenceDronesBySpecies[bee.individual.inactive.species.name].individual.active[trait] = bee.individual.active[trait]
          catalog.referenceDronesBySpecies[bee.individual.inactive.species.name].individual.inactive[trait] = bee.individual.inactive[trait]
        end
      else
        -- keep 1 extra drone around if purebreed
        -- this speeds up breeding by not ditching drones you just breed from reference bees
        -- when the reference bee drone output is still mutating
        local ditchDrone = nil
        if bee.individual.active.species.name == bee.individual.inactive.species.name then
          if extraDronesBySpecies[bee.individual.active.species.name] == nil then
            extraDronesBySpecies[bee.individual.active.species.name] = bee
            bee = nil
          elseif compareBees(bee, extraDronesBySpecies[bee.individual.active.species.name]) then
            ditchDrone = extraDronesBySpecies[bee.individual.active.species.name]
            extraDronesBySpecies[bee.individual.active.species.name] = bee
            bee = ditchDrone
          end
        end
        -- ditch drone
        if bee ~= nil then
          if inv.pushItem(config.chestDir, bee.slot) == 0 then
            error("ditch chest is full")
          end
        end
      end
    end
  end
  -- phase 3 -- catalog bees
  bees = getAllBees(inv)
  for slot, bee in pairs(bees) do
    fixBee(bee)
    bee.slot = slot
    if slot > referenceBeeCount then
      if bee.raw_name == BEE_DRONE then -- drones
        table.insert(catalog.drones, bee)
        addBySpecies(catalog.dronesBySpecies, bee)
      elseif bee.raw_name == BEE_PRINCESS then -- princess
        table.insert(catalog.princesses, bee)
        addBySpecies(catalog.princessesBySpecies, bee)
      elseif bee.raw_name == BEE_QUEEN then -- queens
        table.insert(catalog.queens, bee)
      end
    else
      if bee.raw_name == BEE_DRONE and bee.qty > 1 then
        table.insert(catalog.drones, bee)
        addBySpecies(catalog.dronesBySpecies, bee)
      end
    end
  end
  logLine(string.format("found %d queens, %d princesses, %d drones",
      #catalog.queens, #catalog.princesses, #catalog.drones))
  return catalog
end

-- interaction functions --------------

function clearApiary(inv, apiary)
  local bees = getAllBees(apiary)
  -- wait for queen to die
  if (bees[1] ~= nil and bees[1].raw_name == BEE_QUEEN)
      or (bees[1] ~= nil and bees[2] ~= nil) then
    log("waiting for apiary")
    while true do
      sleep(5)
      bees = getAllBees(apiary)
      if bees[1] == nil then
        break
      end
      log(".")
    end
  end
  logLine()
  -- First two slots are assumed Princess/Drone.
  -- All other slots should be checked for bees.
  for slot = 3, apiary.getInventorySize() do
    local bee = bees[slot]
    if bee ~= nil then
      if bee.raw_name == BEE_DRONE or bee.raw_name == BEE_PRINCESS then
        apiary.pushItem(config.chestDir, slot, 64)
      else
        apiary.pushItem(config.productDir, slot, 64)
      end
    end
  end
end

function clearAnalyzer(inv)
  if not useAnalyzer then
    return
  end
  local bees = getAllBees(inv)
  if #bees == inv.size then
    error("chest is full")
  end
  for analyzerSlot = 9, 12 do
    if inv.pullItem(config.analyzerDir, analyzerSlot) == 0 then
      break
    end
  end
end

function analyzeBee(inv, slot)
  clearAnalyzer(inv)
  log("analyzing bee ")
  log(slot)
  log("...")
  local freeSlot
  if inv.pushItem(config.analyzerDir, slot, 64, 3) > 0 then
    while true do
      -- constantly check in case of inventory manipulation by player
      local bees = getAllBees(inv)
      freeSlot = nil
      for i = 1, inv.size do
        if bees[i] == nil then
          freeSlot = i
          break
        end
      end
      if inv.pullItem(config.analyzerDir, 9) > 0 then
        break
      end
      sleep(1)
    end
  else
    logLine("Missing Analyzer")
    useAnalyzer = false
    return nil
  end
  local bee = getBeeInSlot(inv, freeSlot)
  if bee ~= nil then
    printBee(fixBee(bee))
  end
  return freeSlot
end

function breedBees(inv, apiary, princess, drone)
  clearApiary(inv, apiary)
  apiary.pullItem(config.chestDir, princess.slot, 1, 1)
  apiary.pullItem(config.chestDir, drone.slot, 1, 2)
  clearApiary(inv, apiary)
end

function breedQueen(inv, apiary, queen)
  log("breeding queen")
  clearApiary(inv, apiary)
  apiary.pullItem(config.chestDir, queen.slot, 1, 1)
  clearApiary(inv, apiary)
end

-- selects best pair for target species
--   or initiates breeding of lower species
function selectPair(mutations, scorers, catalog, targetSpecies)
  logLine("targetting "..targetSpecies)
  local baseChance = 0
  if #mutations.getBeeParents(targetSpecies) > 0 then
    local parents = mutations.getBeeParents(targetSpecies)[1]
    baseChance = parents.chance
    for _, s in ipairs(parents.specialConditions) do
      logLine("    ", s)
    end
  end
  local mateCombos = choose(catalog.princesses, catalog.drones)
  local mates = {}
  local haveReference = (catalog.referencePrincessesBySpecies[targetSpecies] ~= nil and
      catalog.referenceDronesBySpecies[targetSpecies] ~= nil)
  for i, v in ipairs(mateCombos) do
    local chance = mutateBeeChance(mutations, v[1], v[2], targetSpecies) or 0
    if (not haveReference and chance >= baseChance / 2) or
        (haveReference and chance > 25) then
      local newMates = {
        ["princess"] = v[1],
        ["drone"] = v[2],
        ["speciesChance"] = chance
      }
      for trait, scorer in pairs(scorers) do
        newMates[trait] = (scorer(v[1]) + scorer(v[2])) / 2
      end
      table.insert(mates, newMates)
    end
  end
  if #mates > 0 then
    table.sort(mates, compareMates)
    for i = math.min(#mates, 10), 1, -1 do
      local parents = mates[i]
      logLine(beeName(parents.princess), " ", beeName(parents.drone), " ", parents.speciesChance, " ", parents.fertility, " ",
            parents.flowering, " ", parents.nocturnal, " ", parents.tolerantFlyer, " ", parents.caveDwelling, " ",
            parents.lifespan, " ", parents.temperatureTolerance, " ", parents.humidityTolerance)
    end
    return mates[1]
  else
    -- check for reference bees and breed if drone count is 1
    if catalog.referencePrincessesBySpecies[targetSpecies] ~= nil and
        catalog.referenceDronesBySpecies[targetSpecies] ~= nil then
      logLine("Breeding extra drone from reference bees")
      return {
        ["princess"] = catalog.referencePrincessesBySpecies[targetSpecies],
        ["drone"] = catalog.referenceDronesBySpecies[targetSpecies]
      }
    end
    -- attempt lower tier bee
    local parentss = mutations.getBeeParents(targetSpecies)
    if #parentss > 0 then
      logLine("lower tier")
      --print(textutils.serialize(catalog.referencePrincessesBySpecies))
      table.sort(parentss, function(a, b) return a.chance > b.chance end)
      local trySpecies = {}
      for i, parents in ipairs(parentss) do
        fixParents(parents)
        if (catalog.referencePairBySpecies[parents.allele2] == nil        -- no reference bee pair
            or catalog.referenceDronesBySpecies[parents.allele2].qty <= 1 -- no extra reference drone
            or catalog.princessesBySpecies[parents.allele2] == nil)       -- no converted princess
            and trySpecies[parents.allele2] == nil then
          table.insert(trySpecies, parents.allele2)
          trySpecies[parents.allele2] = true
        end
        if (catalog.referencePairBySpecies[parents.allele1] == nil
            or catalog.referenceDronesBySpecies[parents.allele1].qty <= 1
            or catalog.princessesBySpecies[parents.allele1] == nil)
            and trySpecies[parents.allele1] == nil then
          table.insert(trySpecies, parents.allele1)
          trySpecies[parents.allele1] = true
        end
      end
      for _, species in ipairs(trySpecies) do
        local mates = selectPair(mutations, scorers, catalog, species)
        if mates ~= nil then
          return mates
        end
      end
    end
    return nil
  end
end

function isPureBred(bee1, bee2, targetSpecies)
  if bee1.individual.isAnalyzed and bee2.individual.isAnalyzed then
    if bee1.individual.active.species.name == bee1.individual.inactive.species.name and
        bee2.individual.active.species.name == bee2.individual.inactive.species.name and
        bee1.individual.active.species.name == bee2.individual.active.species.name and
        (targetSpecies == nil or bee1.individual.active.species.name == targetSpecies) then
      return true
    end
  elseif bee1.individual.isAnalyzed == false and bee2.individual.isAnalyzed == false then
    if bee1.individual.displayName == bee2.individual.displayName then
      return true
    end
  end
  return false
end

function breedTargetSpecies(mutations, inv, apiary, scorers, targetSpecies)
  local catalog = catalogBees(inv, scorers)
  while true do
    if #catalog.princesses == 0 then
      log("Please add more princesses and press [Enter]")
      io.read("*l")
      catalog = catalogBees(inv, scorers)
    elseif #catalog.drones == 0 and next(catalog.referenceDronesBySpecies) == nil then
      log("Please add more drones and press [Enter]")
      io.read("*l")
      catalog = catalogBees(inv, scorers)
    else
      local mates = selectPair(mutations, scorers, catalog, targetSpecies)
      if mates ~= nil then
        if isPureBred(mates.princess, mates.drone, targetSpecies) then
          break
        else
          breedBees(inv, apiary, mates.princess, mates.drone)
          catalog = catalogBees(inv, scorers)
        end
      else
        log(string.format("Please add more bee species for %s and press [Enter]"), targetSpecies)
        io.read("*l")
        catalog = catalogBees(inv, scorers)
      end
    end
  end
  logLine("Bees are purebred")
end

function breedAllSpecies(mutations, inv, apiary, scorers, speciesList)
  if #speciesList == 0 then
    log("Please add more bee species and press [Enter]")
    io.read("*l")
  else
    for i, targetSpecies in ipairs(speciesList) do
      breedTargetSpecies(mutations, inv, apiary, scorers, targetSpecies)
    end
  end
end

function main(tArgs)
  logLine(string.format("openbee version %d.%d.%d", version.major, version.minor, version.patch))
  local targetSpecies = setPriorities(tArgs)
  log("priority:")
  for _, priority in ipairs(traitPriority) do
    log(" "..priority)
  end
  logLine("")
  local inv, apiary = getPeripherals()
  inv.size = inv.getInventorySize()
  local mutations, beeNames = buildMutationGraph(apiary)
  local scorers = buildScoring()
  clearApiary(inv, apiary)
  clearAnalyzer(inv)
  local catalog = catalogBees(inv, scorers)
  while #catalog.queens > 0 do
    breedQueen(inv, apiary, catalog.queens[1])
    catalog = catalogBees(inv, scorers)
  end
  if targetSpecies ~= nil then
    targetSpecies = tArgs[1]:sub(1,1):upper()..tArgs[1]:sub(2):lower()
    if beeNames[targetSpecies] == true then
      breedTargetSpecies(mutations, inv, apiary, scorers, targetSpecies)
    else
      logLine(string.format("Species '%s' not found.", targetSpecies))
    end
  else
    while true do
      breedAllSpecies(mutations, inv, apiary, scorers, buildTargetSpeciesList(catalog, apiary))
      catalog = catalogBees(inv, scorers)
    end
  end
end

local logFileName = setupLog()
local status, err = pcall(main, {...})
if not status then
  logLine(err)
end
print("Log file is "..logFileName)
