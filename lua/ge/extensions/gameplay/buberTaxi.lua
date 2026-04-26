--[[
  BUBER Taxi Service — BeamNG Career Mode Taxi Extension
  All tunable values live in gameplay/taxiConfig.lua
]]

local M = {}
M.dependencies = {
  'gameplay_taxiConfig',
  -- All other game extensions (gameplay_walk, gameplay_sites_sitesManager, etc.)
  -- are accessed with nil guards. They are NOT listed as hard dependencies because
  -- doing so forces the extension system to manage their lifecycle, which can
  -- conflict with BeamMP's beamling avatar mesh system (causing invisible players).
}

-- ================================
-- LOGGING
-- ================================
local logTag = 'buber'

-- ================================
-- CONFIG (loaded from taxiConfig.lua)
-- ================================
local config = gameplay_taxiConfig

-- Brand
local BRAND_NAME                    = config.brand.name
local RATING_SAVE_DIR               = config.brand.ratingSaveDir
local RATING_SAVE_FILE              = config.brand.ratingSaveFile

-- Timing
local JOB_OFFER_INTERVAL_MIN        = config.timing.jobOfferIntervalMin
local JOB_OFFER_INTERVAL_MAX        = config.timing.jobOfferIntervalMax
local JOB_OFFER_PREPARE_LEAD_TIME   = config.timing.jobOfferPrepareLeadTime
local JOB_ACCEPT_TIMEOUT_SECONDS    = config.timing.jobAcceptTimeout
local COMPLETED_FARE_DISPLAY_SECONDS = config.timing.completedFareDisplay
local UPDATE_INTERVAL                = config.timing.updateInterval
local ROUTE_RESTORE_COOLDOWN         = config.timing.routeRestoreCooldown
local RETURN_TO_VEHICLE_GRACE_SECONDS = config.timing.returnToVehicleGrace

-- Taxi zones
local TAXI_STOP_RADIUS               = config.zones.stopRadius
local TAXI_STOP_HEIGHT               = config.zones.stopHeight
local TAXI_ZONE_DRAW_RADIUS          = config.zones.drawRadius
local PICKUP_SEARCH_RADIUS           = config.zones.pickupSearchRadius
local MIN_PICKUP_DISTANCE            = config.zones.minPickupDistance
local PICKUP_CACHE_REFRESH_DISTANCE  = config.zones.pickupCacheRefreshDist
local MAX_TAXI_PICKUP_SAMPLES        = config.zones.maxPickupSamples
local MAX_TAXI_DROPOFF_SAMPLES       = config.zones.maxDropoffSamples

-- Passenger service
local PASSENGER_STOP_SERVICE_SECONDS = config.service.stopServiceSeconds
local PASSENGER_STOP_SPEED_THRESHOLD = config.service.stopSpeedThreshold
local BUS_PASSENGER_SERVICE_RATE     = config.service.busPassengerServiceRate

-- Multi-stop
local MULTI_STOP_VEHICLE_SEAT_THRESHOLD = config.multiStop.vehicleSeatThreshold
local MULTI_STOP_EMPTY_STOP_CHANCE      = config.multiStop.emptyStopChance
local MULTI_STOP_REQUIRED_RATING        = config.multiStop.requiredRating

-- Shared rides
local SHARED_RIDE_MIN_SEATS           = config.sharedRide.minSeats
local SHARED_RIDE_OFFER_CHANCE        = config.sharedRide.offerChance
local SHARED_RIDE_MIN_DROPOFF_DISTANCE = config.sharedRide.minDropoffDistance
local SHARED_RIDE_MAX_DROPOFFS        = config.sharedRide.maxDropoffs

-- Bus display
local BUS_DISPLAY_DEFAULT_ROUTE       = config.busDisplay.defaultRoute
local BUS_DISPLAY_DEFAULT_DIRECTION   = config.busDisplay.defaultDirection
local BUS_DISPLAY_DEFAULT_COLOR       = config.busDisplay.defaultColor

-- Fare calculation
local DISTANCE_MULTIPLIER            = config.fare.distanceMultiplier
local SUGGESTED_SPEED                 = config.fare.suggestedSpeed

-- Driver rating
local RATING_SUM_PER_LEVEL           = config.rating.sumPerLevel
local MAX_DRIVER_RATING              = config.rating.maxRating

-- Vehicle class pay tiers
local VEHICLE_CLASS_PAY_TIERS        = config.vehicle.classTiers

-- Rating-driven curves and milestones
local DRIVER_SEAT_CAP_CURVE          = config.rating.seatCapCurve
local PROGRESSION_MILESTONES         = config.rating.milestones

-- Visual
local TAXI_ZONE_COLORS               = config.visual.zoneColors
local TAXI_DEBUG_SPOT_COLORS          = config.visual.debugSpotColors

-- ================================
-- STATE
-- ================================
local state = {
  currentFare = nil,
  preparedFare = nil,
  availableSeats = 0,
  vehicleOpenSeats = 0,
  seatCap = 0,
  cumulativeReward = 0,
  fareStreak = 0,
  shiftAbandonCount = 0,
  playerRating = 0,
  ratingSum = 0,
  ratingCount = 0,
  lastPassengerRating = nil,
  lastCompletedFare = nil,
  returnToVehicleDeadline = nil,
  returnToVehicleStartedAt = nil,
  vehicleMultiplier = 1.0,
  vehicleClassName = "C",
  vehicleClassDescription = "Standard",
  vehiclePerformanceIndex = nil,
  rideData = {}
}

local machineState = "start" -- start, ready, accept, pickup, dropoff, complete, disabled
local timer = 0
local jobOfferTimer = 0
local jobOfferInterval = math.random(JOB_OFFER_INTERVAL_MIN, JOB_OFFER_INTERVAL_MAX)
local completedFareDisplayUntil = 0
local completedFareNextState = "ready"
local completedFareClearResultOnReturn = false
local lastRouteRestoreTime = 0

-- Location caches
local parkingSpots = nil
local allTaxiSpots = nil
local validPickupSpots = nil
local pickupCacheVehiclePos = nil
local cachedBusRoutes = nil
local cachedBusStopsByName = nil
local cachedBusLevelDir = nil
local taxiSpotDebug = {
  enabled = false,
  mode = "all"
}

-- Reservations
local currentReservationToken = nil
local reservedPickupSpot = nil
local reservedDropoffSpot = nil
local reservedDropoffSpots = {}

-- Bus stop state
local busStopVehicleFrozen = false
local busStopFrozenVehicle = nil

-- Async vehicle data
local currentVehiclePartsTree = nil
local partsTreePending = false
local lastCapacityDebug = {}

-- Passenger module loading
local PASSENGER_MODULES_PATH = config.passengerModules.path

-- ================================
-- PASSENGER TYPES
-- ================================
local defaultPax = config.defaultPassenger
local passengerTypes = {
  STANDARD = {
    name = defaultPax.name,
    description = defaultPax.description,
    baseMultiplier = defaultPax.baseMultiplier,
    speedWeight = defaultPax.speedWeight,
    distanceWeight = defaultPax.distanceWeight,
    selectionWeight = defaultPax.selectionWeight,
    seatRange = defaultPax.seatRange,
    valueRange = defaultPax.valueRange,
    fareWeights = defaultPax.fareWeights,
    speedTolerance = defaultPax.speedTolerance,
    calculateTipBreakdown = function(fare, elapsedTime, speedFactor, passengerType)
      local baseFare = tonumber(fare.baseFare) or 0
      if speedFactor > 0 then
        return {["Speed Bonus"] = speedFactor * baseFare * passengerType.speedWeight * 0.5}
      end
      return {}
    end,
    calculateDriverRating = function(fare, rideData, elapsedTime, speedFactor, passengerType)
      local rough = (rideData and rideData.roughEvents) or 0
      local rating = 5.0 - (rough * 0.3) + (math.max(-1, math.min(1, speedFactor or 0)) * 0.5)
      if fare and fare.passengers and fare.passengers > 3 then
        rating = rating + 0.2
      end
      return math.max(1, math.min(5, rating))
    end,
    getDescription = function(fare, passengerType)
      return string.format("%s (%d passengers)", passengerType.name, fare.passengers)
    end,
    getPaymentLabel = function(fare, speedFactor, passengerType)
      return speedFactor > 0 and "Speed Bonus" or "Time Penalty"
    end,
    onUpdate = function(fare, rideData, passengerType)
      local s = rideData.currentSensorData
      if s then
        local roughThreshold = defaultPax.roughGThreshold or 0.6
        local peak = math.max(math.abs(s.gx2 or 0), math.abs(s.gy2 or 0), math.abs(s.gz2 or 0))
        if peak > roughThreshold then
          rideData.roughEvents = (rideData.roughEvents or 0) + 1
        end
      end
    end
  }
}

-- ================================
-- PAYOUT LIMITS
-- ================================
-- copyDeep is needed here to snapshot the config tables so runtime
-- changes (e.g. setFarePayoutCap) don't mutate the shared config.
local function copyDeep(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do
    out[k] = copyDeep(v)
  end
  return out
end

local payoutLimits = {
  profiles = {
    direct = copyDeep(config.payout.direct),
    multistop = copyDeep(config.payout.multistop),
  }
}

-- ================================
-- UTILITY FUNCTIONS
-- ================================
local function clamp(value, minVal, maxVal)
  return math.max(minVal, math.min(maxVal, value))
end

local function getRatingCurveValue(curve, rating, fallback)
  if type(curve) ~= "table" or #curve <= 0 then return fallback end

  local driverRating = clamp(tonumber(rating) or 0, 0, MAX_DRIVER_RATING)
  local first = curve[1]
  local firstRating = tonumber(first.rating) or 0
  local firstValue = first.value

  if driverRating <= firstRating then
    return firstValue ~= nil and firstValue or fallback
  end

  for index = 2, #curve do
    local previous = curve[index - 1]
    local current = curve[index]
    local previousRating = tonumber(previous.rating) or 0
    local currentRating = tonumber(current.rating) or previousRating
    local previousValue = previous.value
    local currentValue = current.value

    if driverRating <= currentRating then
      if currentValue == math.huge then
        return driverRating >= currentRating and math.huge or previousValue
      end
      if previousValue == math.huge then
        return math.huge
      end

      previousValue = tonumber(previousValue)
      currentValue = tonumber(currentValue)
      if not previousValue or not currentValue then return fallback end
      if currentRating <= previousRating then return currentValue end

      local ratio = (driverRating - previousRating) / (currentRating - previousRating)
      return previousValue + ((currentValue - previousValue) * ratio)
    end
  end

  local lastValue = curve[#curve].value
  return lastValue ~= nil and lastValue or fallback
end




local function getPassengerModuleExtensionNames()
  local extensionNames = {}
  local files = FS:findFiles(PASSENGER_MODULES_PATH, "*.lua", -1, true, false) or {}

  table.sort(files)

  for _, filePath in ipairs(files) do
    local filename = string.match(filePath, "([^/\\]+)%.lua$")
    if filename then
      table.insert(extensionNames, "gameplay_taxiPassengers_" .. filename)
    end
  end

  return extensionNames
end

local function unloadPassengerModules()
  for _, extensionName in ipairs(getPassengerModuleExtensionNames()) do
    extensions.unload(extensionName)
  end
end

local function loadPassengerModules()
  local extensionNames = getPassengerModuleExtensionNames()
  if #extensionNames <= 0 then
    log('W', logTag, "No passenger modules found in " .. PASSENGER_MODULES_PATH)
    return
  end

  -- Load each passenger module individually instead of using
  -- loadManualUnloadExtensions() which reloads ALL manual extensions
  -- engine-wide and can break the base game's beamling mesh state.
  for _, extensionName in ipairs(extensionNames) do
    if extensions[extensionName] then
      extensions.unload(extensionName)
    end
    setExtensionUnloadMode(extensionName, "manual")
    extensions.load(extensionName)
  end
end

local function getPlayerVehicle()
  return be and be:getPlayerVehicle(0) or nil
end

local function serializeLuaLiteral(value)
  local serializer = serialize or dumps
  if type(serializer) ~= "function" then return nil end

  local ok, literal = pcall(serializer, value)
  if ok and literal then return literal end
  return nil
end

local function normalizeRouteColor(routeColor)
  if type(routeColor) ~= "string" then return nil end

  local hex = routeColor:match("^%s*#?([0-9a-fA-F]+)%s*$")
  if not hex then return nil end

  if #hex == 3 then
    hex = hex:sub(1, 1) .. hex:sub(1, 1) ..
      hex:sub(2, 2) .. hex:sub(2, 2) ..
      hex:sub(3, 3) .. hex:sub(3, 3)
  elseif #hex == 6 or #hex == 8 then
    hex = hex:sub(1, 6)
  else
    return nil
  end

  return "#" .. string.lower(hex)
end

local function routeColorToGroundMarkerColor(routeColor)
  local normalized = normalizeRouteColor(routeColor)
  if not normalized then return nil end

  local hex = normalized:sub(2)
  local red = tonumber("0x" .. hex:sub(1, 2))
  local green = tonumber("0x" .. hex:sub(3, 4))
  local blue = tonumber("0x" .. hex:sub(5, 6))
  if not red or not green or not blue then return nil end

  return {red / 255, green / 255, blue / 255}
end

local function queueCityBusGameplayEvent(eventName, eventData)
  local vehicle = getPlayerVehicle()
  if not vehicle or not vehicle.queueLuaCommand then return false end

  local eventNameLiteral = serializeLuaLiteral(eventName)
  local eventDataLiteral = serializeLuaLiteral(eventData or {})
  if not eventNameLiteral or not eventDataLiteral then
    log("W", logTag, "Could not serialize citybus display event: " .. tostring(eventName))
    return false
  end

  vehicle:queueLuaCommand(
    "local eventName = " .. eventNameLiteral .. "\n" ..
    "local eventData = " .. eventDataLiteral .. "\n" ..
    [[
local mainPartName = v and v.config and v.config.mainPartName or ""
if mainPartName == "citybus" and controller and controller.onGameplayEvent then
  controller.onGameplayEvent(eventName, eventData)
end
]]
  )

  return true
end

local function isActualCityBusRouteFare(fare)
  return fare and fare.routeMode == "multistop" and fare.routeType ~= "shared" and type(fare.stops) == "table" and #fare.stops >= 2
end

local function getCityBusRouteColor(fare)
  if not isActualCityBusRouteFare(fare) then return nil end
  return normalizeRouteColor(fare.routeColor)
end

local function stopPositionToDisplayTable(pos)
  if not pos then return {0, 0, 0} end
  return {
    tonumber(pos.x) or tonumber(pos[1]) or 0,
    tonumber(pos.y) or tonumber(pos[2]) or 0,
    tonumber(pos.z) or tonumber(pos[3]) or 0
  }
end

local function buildCityBusDisplayTasklist(stops, startIndex)
  local tasklist = {}
  local firstIndex = math.max(1, math.floor(tonumber(startIndex) or 1))
  for index = firstIndex, #(stops or {}) do
    local stop = stops[index]
    if stop and stop.pos then
      local triggerName = tostring(stop.name or stop.triggerName or stop.stopName or ("stop_" .. index))
      local stopName = tostring(stop.stopName or stop.name or triggerName)
      table.insert(tasklist, {triggerName, stopName, stopPositionToDisplayTable(stop.pos)})
    end
  end
  return tasklist
end

local function getCityBusDisplayStartIndex(fare)
  if machineState == "dropoff" then
    return math.min(#(fare.stops or {}), (tonumber(fare.currentStopIndex) or 1) + 1)
  end

  return math.max(1, tonumber(fare.currentStopIndex) or 1)
end

local function buildActualCityBusDisplayPayload(fare)
  if not isActualCityBusRouteFare(fare) then return nil end

  local routeID = tostring(fare.routeID or "")
  local variance = tostring(fare.routeVariance or fare.variance or "")
  if variance ~= "" and variance ~= "nil" then
    local upperVariance = string.upper(variance)
    if string.sub(string.upper(routeID), -#upperVariance) ~= upperVariance then
      routeID = routeID .. upperVariance
    end
  end

  return {
    routeID = routeID,
    direction = tostring(fare.routeDirection or fare.direction or ""),
    routeColor = getCityBusRouteColor(fare) or BUS_DISPLAY_DEFAULT_COLOR,
    tasklist = buildCityBusDisplayTasklist(fare.stops, getCityBusDisplayStartIndex(fare))
  }
end

local function syncCityBusDisplayWithFare(fare)
  local payload = buildActualCityBusDisplayPayload(fare)
  if not payload then return false end
  return queueCityBusGameplayEvent("bus_setLineInfo", payload)
end

local function resetCityBusDisplay()
  return queueCityBusGameplayEvent("bus_setLineInfo", {
    routeID = BUS_DISPLAY_DEFAULT_ROUTE,
    direction = BUS_DISPLAY_DEFAULT_DIRECTION,
    routeColor = BUS_DISPLAY_DEFAULT_COLOR,
    tasklist = {
      {"not_in_service", BUS_DISPLAY_DEFAULT_DIRECTION, {999999, 999999, 999999}}
    }
  })
end

local function notifyCityBusDepartedStop(fare, stop)
  if not isActualCityBusRouteFare(fare) or not stop then return false end

  local triggerName = stop.name or stop.triggerName
  if not triggerName or triggerName == "" then return false end

  return queueCityBusGameplayEvent("bus_onDepartedStop", {
    triggerName = tostring(triggerName)
  })
end

local function formatDistance(value, decimals)
  local distance, unit = translateDistance(tonumber(value) or 0, "auto")
  local precision = tonumber(decimals) or 1
  return string.format("%." .. precision .. "f %s", distance or 0, unit or "m")
end

local function makeColorF(colorValues)
  return ColorF(colorValues[1], colorValues[2], colorValues[3], colorValues[4])
end

local function isInsideArea(pos1, pos2, radius)
  return pos1:distance(pos2) < radius
end

-- ================================
-- DRIVER RATING
-- ================================
local function calculateRatingFromSum(sumValue)
  return clamp(tonumber(sumValue or 0) / RATING_SUM_PER_LEVEL, 0, MAX_DRIVER_RATING)
end

local function savePlayerRating(savePath)
  if not career_career or not career_career.isActive() then return end
  
  local currentSavePath = savePath
  if not currentSavePath then
    local _, path = career_saveSystem.getCurrentSaveSlot()
    currentSavePath = path
  end
  if not currentSavePath then return end

  local dirPath = currentSavePath .. "/career/" .. RATING_SAVE_DIR
  if not FS:directoryExists(dirPath) then
    FS:directoryCreate(dirPath)
  end

  career_saveSystem.jsonWriteFileSafe(dirPath .. "/" .. RATING_SAVE_FILE, {
    sum = state.ratingSum,
    count = state.ratingCount,
    average = state.playerRating
  }, true)
end

local function loadPlayerRating()
  if not career_career or not career_career.isActive() then return end
  
  local _, path = career_saveSystem.getCurrentSaveSlot()
  if not path then return end
  
  local data = jsonReadFile(path .. "/career/" .. RATING_SAVE_DIR .. "/" .. RATING_SAVE_FILE) or {}
  state.ratingSum = tonumber(data.sum or 0) or 0
  state.ratingCount = tonumber(data.count or 0) or 0
  state.playerRating = calculateRatingFromSum(state.ratingSum)
  if recalculateCapacity then recalculateCapacity() end
end

function M.getDriverRating()
  return state.playerRating
end

function M.setDriverRating(value)
  state.playerRating = clamp(tonumber(value) or 0, 0, MAX_DRIVER_RATING)
  state.ratingSum = state.playerRating * RATING_SUM_PER_LEVEL
  state.ratingCount = math.max(1, math.floor(state.playerRating * 5))
  state.lastPassengerRating = nil
  savePlayerRating()
  if recalculateCapacity then recalculateCapacity() end
  emitState()
  return state.playerRating
end

local function getDriverSeatCapForRating(rating)
  local cap = getRatingCurveValue(DRIVER_SEAT_CAP_CURVE, rating, 4)
  if cap == math.huge then return math.huge end
  return math.max(1, math.floor((tonumber(cap) or 4) + 0.5))
end

function M.getDriverSeatCap()
  return getDriverSeatCapForRating(state.playerRating)
end

local function isMultiStopUnlocked()
  return (tonumber(state.playerRating) or 0) >= MULTI_STOP_REQUIRED_RATING
end

-- ================================
-- TAXI STATE EMISSION
-- ================================
local function isTaxiDisabled()
  local disabled, reason = false, ""

  if gameplay_walk and gameplay_walk.isWalking() then
    return true, BRAND_NAME .. " service is not available while walking"
  end

  local vehicle = getPlayerVehicle()
  if vehicle then
    local vehId = vehicle:getID()
    if career_modules_loanerVehicles and career_modules_loanerVehicles.getLoaningOrgsOfVehicle then
      local loaningOrgs = career_modules_loanerVehicles.getLoaningOrgsOfVehicle(vehId)
      if loaningOrgs and next(loaningOrgs) then
        return true, BRAND_NAME .. " service is not available in loaned vehicles"
      end
    end
  end

  local taxiMultiplier = M.getEconomySectionMultiplier and M.getEconomySectionMultiplier("taxi") or 1.0
  if taxiMultiplier == 0 then
    return true, BRAND_NAME .. " multiplier is set to 0"
  end

  local activeChallenge = nil
  if career_challengeModes and career_challengeModes.isChallengeActive and career_challengeModes.isChallengeActive() then
    activeChallenge = career_challengeModes.getActiveChallenge()
  end
  if activeChallenge and activeChallenge.economyAdjuster and activeChallenge.economyAdjuster.taxi == 0 then
    return true, string.format("%s is disabled due to '%s' Challenge", BRAND_NAME, activeChallenge.name or "Unknown")
  end

  return disabled, reason
end

local function appendVehicleProfile(payload)
  payload.vehicleMultiplier = state.vehicleMultiplier
  payload.vehicleClassName = state.vehicleClassName
  payload.vehicleClassDescription = state.vehicleClassDescription
  payload.vehiclePerformanceIndex = state.vehiclePerformanceIndex
  payload.vehicleClassMultiplier = state.vehicleMultiplier
  return payload
end

local function roundedCap(value)
  if value == nil or value == math.huge then return nil end
  return math.floor((tonumber(value) or 0) + 0.5)
end

local function buildProgressionMilestones()
  local milestones = {}
  local rating = tonumber(state.playerRating) or 0

  for _, milestone in ipairs(PROGRESSION_MILESTONES) do
    local milestoneRating = tonumber(milestone.rating) or 0
    local seatCap = getDriverSeatCapForRating(milestoneRating)
    table.insert(milestones, {
      rating = milestoneRating,
      label = milestone.label,
      description = milestone.description,
      unlocked = rating >= milestoneRating,
      directCap = roundedCap(getRatingCurveValue(payoutLimits.profiles.direct.ratingHardCapCurve, milestoneRating, nil)),
      multiStopCap = roundedCap(getRatingCurveValue(payoutLimits.profiles.multistop.ratingHardCapCurve, milestoneRating, nil)),
      multiStopUnlocked = milestoneRating >= MULTI_STOP_REQUIRED_RATING,
      seatCap = seatCap == math.huge and nil or seatCap,
      seatCapUnlimited = seatCap == math.huge
    })
  end

  return milestones
end

local function getNextProgressionUnlock()
  local rating = tonumber(state.playerRating) or 0

  for _, milestone in ipairs(PROGRESSION_MILESTONES) do
    local milestoneRating = tonumber(milestone.rating) or 0
    if rating < milestoneRating then
      local seatCap = getDriverSeatCapForRating(milestoneRating)
      return {
        rating = milestoneRating,
        label = milestone.label,
        description = milestone.description,
        directCap = roundedCap(getRatingCurveValue(payoutLimits.profiles.direct.ratingHardCapCurve, milestoneRating, nil)),
        multiStopCap = roundedCap(getRatingCurveValue(payoutLimits.profiles.multistop.ratingHardCapCurve, milestoneRating, nil)),
        multiStopUnlocked = milestoneRating >= MULTI_STOP_REQUIRED_RATING,
        seatCap = seatCap == math.huge and nil or seatCap,
        seatCapUnlimited = seatCap == math.huge
      }
    end
  end

  return nil
end

local function buildProgressionData()
  local rating = clamp(tonumber(state.playerRating) or 0, 0, MAX_DRIVER_RATING)
  local seatCap = M.getDriverSeatCap()

  return {
    rating = rating,
    maxRating = MAX_DRIVER_RATING,
    directCap = roundedCap(getRatingCurveValue(payoutLimits.profiles.direct.ratingHardCapCurve, rating, nil)),
    multiStopCap = roundedCap(getRatingCurveValue(payoutLimits.profiles.multistop.ratingHardCapCurve, rating, nil)),
    multiStopRequiredRating = MULTI_STOP_REQUIRED_RATING,
    multiStopUnlocked = isMultiStopUnlocked(),
    seatCap = seatCap == math.huge and nil or seatCap,
    seatCapUnlimited = seatCap == math.huge,
    vehicleOpenSeats = state.vehicleOpenSeats,
    availableSeats = state.availableSeats,
    nextUnlock = getNextProgressionUnlock(),
    milestones = buildProgressionMilestones()
  }
end

function emitState()
  local taxiDisabled, disabledReason = isTaxiDisabled()
  local returnToVehicleActive = state.currentFare ~= nil and state.returnToVehicleDeadline ~= nil
  local returnToVehicleSeconds = returnToVehicleActive and math.max(0, state.returnToVehicleDeadline - os.time()) or nil
  local effectiveState = taxiDisabled and not returnToVehicleActive and "disabled" or machineState

  local data = appendVehicleProfile({
    state = effectiveState,
    currentFare = state.currentFare,
    lastCompletedFare = state.lastCompletedFare,
    resultNextState = machineState == "complete" and completedFareNextState or nil,
    availableSeats = state.availableSeats,
    vehicleOpenSeats = state.vehicleOpenSeats,
    seatCap = state.seatCap,
    cumulativeReward = state.cumulativeReward,
    fareStreak = state.fareStreak,
    currentPassengerType = state.currentFare and state.currentFare.passengerTypeName or nil,
    playerRating = state.playerRating,
    multiStopRequiredRating = MULTI_STOP_REQUIRED_RATING,
    multiStopUnlocked = isMultiStopUnlocked(),
    progression = buildProgressionData(),
    lastPassengerRating = state.lastPassengerRating,
    returnToVehicleActive = returnToVehicleActive,
    returnToVehicleSeconds = returnToVehicleSeconds,
    taxiDisabled = taxiDisabled and not returnToVehicleActive,
    disabledReason = returnToVehicleActive and "" or disabledReason
  })

  if guihooks then
    guihooks.trigger("buberState", data)
  end
end

-- ================================
-- UI HELPERS
-- ================================
local function showToast(title, message, toastType)
  if guihooks then
    guihooks.trigger("toastrMsg", {
      type = toastType or "info",
      title = title or BRAND_NAME,
      msg = message or "",
      config = {timeOut = 3000}
    })
  end
end

local function getReturnToVehicleSeconds()
  if not state.returnToVehicleDeadline then return nil end
  return math.max(0, state.returnToVehicleDeadline - os.time())
end

local function isReturnToVehicleTimerActive()
  return state.currentFare ~= nil and state.returnToVehicleDeadline ~= nil
end

local function clearReturnToVehicleTimer()
  state.returnToVehicleDeadline = nil
  state.returnToVehicleStartedAt = nil
end

local function startReturnToVehicleTimer()
  if not state.currentFare or machineState ~= "dropoff" then return false end
  if isReturnToVehicleTimerActive() then return true end

  state.returnToVehicleStartedAt = os.time()
  state.returnToVehicleDeadline = state.returnToVehicleStartedAt + RETURN_TO_VEHICLE_GRACE_SECONDS
  setBusStopVehicleFreeze(false)
  showToast(BRAND_NAME, string.format("Return to your vehicle within %ds or the passenger will abandon.", RETURN_TO_VEHICLE_GRACE_SECONDS), "warning")
  emitState()
  return true
end

-- ================================
-- LOCATION & PARKING
-- ================================
local function invalidateLocationCaches()
  parkingSpots = nil
  allTaxiSpots = nil
  validPickupSpots = nil
  pickupCacheVehiclePos = nil
  cachedBusRoutes = nil
  cachedBusStopsByName = nil
  cachedBusLevelDir = nil
end

local function rebuildTaxiSpotPool()
  local spotPool = {}
  for _, spot in pairs((parkingSpots and parkingSpots.objects) or {}) do
    if spot and spot.pos then
      table.insert(spotPool, spot)
    end
  end
  allTaxiSpots = spotPool
end

local function findParkingSpots()
  if parkingSpots and allTaxiSpots then
    return parkingSpots
  end

  if not gameplay_sites_sitesManager then return nil end

  local sitePath = gameplay_sites_sitesManager.getCurrentLevelSitesFileByName('city')
  if sitePath then
    local siteData = gameplay_sites_sitesManager.loadSites(sitePath, true, true)
    parkingSpots = siteData and siteData.parkingSpots
    rebuildTaxiSpotPool()
  end
  return parkingSpots
end

local function safeSpotPath(spot)
  if spot and spot.getPath then
    local ok, path = pcall(function() return spot:getPath() end)
    if ok then return path end
  end
  return nil
end

local function findValidPickupSpots()
  local vehicle = getPlayerVehicle()
  if not vehicle then return {} end
  
  local playerPos = vehicle:getPosition()

  if not parkingSpots or not allTaxiSpots or #allTaxiSpots == 0 then
    return {}
  end

  if pickupCacheVehiclePos and validPickupSpots and #validPickupSpots > 0 then
    local movedDistance = (playerPos - pickupCacheVehiclePos):length()
    if movedDistance < PICKUP_CACHE_REFRESH_DISTANCE then
      return validPickupSpots
    end
  end

  local nearby = {}
  for _, spot in ipairs(allTaxiSpots) do
    local distance = spot and spot.pos and (spot.pos - playerPos):length() or nil
    if distance and distance < PICKUP_SEARCH_RADIUS and distance >= MIN_PICKUP_DISTANCE then
      table.insert(nearby, spot)
    end
  end
  
  pickupCacheVehiclePos = vec3(playerPos.x, playerPos.y, playerPos.z)
  validPickupSpots = nearby
  return nearby
end

-- ================================
-- RESERVATION SYSTEM
-- ================================
local function makeReservationToken(prefix)
  return string.format("%s:%d:%d", prefix or "taxi", os.time(), math.random(100000, 999999))
end

local function shuffleSpots(spots)
  local shuffled = {}
  for i, spot in ipairs(spots or {}) do
    shuffled[i] = spot
  end
  for i = #shuffled, 2, -1 do
    local j = math.random(i)
    shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
  end
  return shuffled
end

local function isSpotEmpty(spot)
  if not spot or type(spot.hasAnyVehicles) ~= "function" then
    return true
  end
  local ok, hasVehicles = pcall(function() return spot:hasAnyVehicles() end)
  return not ok or not hasVehicles
end

local function reserveSpot(spot, token)
  if not spot or not token then return false end
  if spot.ignoreOthers and spot._buberReservationOwner ~= token then return true end
  if not isSpotEmpty(spot) then return false end
  spot.ignoreOthers = true
  spot._buberReservationOwner = token
  return true
end

local function releaseSpot(spot, token)
  if not spot or not token or spot._buberReservationOwner ~= token then return false end
  spot.ignoreOthers = nil
  spot._buberReservationOwner = nil
  return true
end

local function reserveTaxiSpots(pickupCandidates, dropoffCandidates, minDropoffDistance, maxDropoffAttempts)
  releaseReservations()
  currentReservationToken = makeReservationToken("taxi")

  local livePickup = nil
  for _, candidate in ipairs(pickupCandidates or {}) do
    if reserveSpot(candidate, currentReservationToken) then
      livePickup = candidate
      break
    end
  end

  if not livePickup then
    releaseReservations()
    return nil, nil
  end

  local pickupPath = safeSpotPath(livePickup)
  if not pickupPath then
    releaseSpot(livePickup, currentReservationToken)
    releaseReservations()
    return nil, nil
  end

  local attempts = 0
  local triedKeys = {}
  local dropoffCount = #(dropoffCandidates or {})
  local liveDropoff = nil

  while dropoffCount > 0 and attempts < math.min(maxDropoffAttempts or dropoffCount, dropoffCount) do
    attempts = attempts + 1
    local spot = dropoffCandidates[math.random(dropoffCount)]
    local candidateKey = safeSpotPath(spot) or tostring(spot and spot.name or attempts)
    
    if not triedKeys[candidateKey] then
      triedKeys[candidateKey] = true

      local spotPath = safeSpotPath(spot)
      local farEnough = spot and spot.pos and livePickup.pos and 
                        livePickup.pos:distance(spot.pos) >= (minDropoffDistance or 0)
      
      if spot and spotPath and spotPath ~= pickupPath and farEnough and reserveSpot(spot, currentReservationToken) then
        liveDropoff = spot
        break
      end
    end
  end

  if not liveDropoff then
    releaseSpot(livePickup, currentReservationToken)
    releaseReservations()
    return nil, nil
  end

  reservedPickupSpot = livePickup
  reservedDropoffSpot = liveDropoff
  reservedDropoffSpots = {liveDropoff}
  return livePickup, liveDropoff
end

function releaseReservations()
  if reservedPickupSpot and currentReservationToken then
    releaseSpot(reservedPickupSpot, currentReservationToken)
  end
  for _, spot in ipairs(reservedDropoffSpots or {}) do
    if spot and currentReservationToken then
      releaseSpot(spot, currentReservationToken)
    end
  end
  if reservedDropoffSpot and currentReservationToken and #(reservedDropoffSpots or {}) == 0 then
    releaseSpot(reservedDropoffSpot, currentReservationToken)
  end
  reservedPickupSpot = nil
  reservedDropoffSpot = nil
  reservedDropoffSpots = {}
  currentReservationToken = nil
end

-- ================================
-- VEHICLE CAPACITY
-- ================================
local function normalizePartName(partName)
  return tostring(partName or ""):lower()
end

local SEAT_PACK_CAPACITY_RULES = config.vehicle.seatPackRules
local CAPSULE_SEAT_PACK_CAPACITIES = config.vehicle.capsuleSeatPacks

local function getSeatPackCapacity(partName)
  partName = normalizePartName(partName)

  for _, rule in ipairs(SEAT_PACK_CAPACITY_RULES) do
    if partName:find(rule.pattern, 1, true) then
      return rule.total
    end
  end

  if partName:find("capsule") and partName:find("seats") then
    for _, rule in ipairs(CAPSULE_SEAT_PACK_CAPACITIES) do
      if partName:find(rule.pattern, 1, true) then
        return rule.total
      end
    end
  end

  return nil
end

local function countSeatsFromPartName(partName)
  partName = normalizePartName(partName)
  local packCapacity = getSeatPackCapacity(partName)
  if packCapacity then return packCapacity end
  
  if partName:find("seat") and not partName:find("cargo") and not partName:find("captains") then
    if partName:find("skin") then return 0 end
    if partName:find("seats") then
      return 3
    elseif partName:find("ext") or partName:match("(%d+)r") then
      return 2
    end
    return 1
  end

  return 0
end

local function cyclePartsTree(partData, seatingCapacity)
  for _, part in pairs(partData or {}) do
    local partName = normalizePartName(part.chosenPartName)
    seatingCapacity = seatingCapacity + countSeatsFromPartName(partName)
    
    if partName == "pickup" then
      seatingCapacity = math.max(seatingCapacity, 7)
    end
    
    if part.children then
      seatingCapacity = cyclePartsTree(part.children, seatingCapacity)
    end
  end

  return seatingCapacity
end

local function retrievePartsTree()
  local vehicle = getPlayerVehicle()
  if not vehicle then
    partsTreePending = false
    return
  end
  
  vehicle:queueLuaCommand([[
    local partsTree = v.config.partsTree
    local serializedPartsTree = serialize(partsTree)
    obj:queueGameEngineLua("if extensions and extensions.gameplay_buberTaxi and extensions.gameplay_buberTaxi.onPartsTreeReceived then extensions.gameplay_buberTaxi.onPartsTreeReceived(" .. serializedPartsTree .. ") elseif gameplay_buberTaxi and gameplay_buberTaxi.onPartsTreeReceived then gameplay_buberTaxi.onPartsTreeReceived(" .. serializedPartsTree .. ") end")
  ]])
end

function M.onPartsTreeReceived(partsTree)
  currentVehiclePartsTree = partsTree
  partsTreePending = false
  recalculateCapacity()
end

function recalculateCapacity()
  if not currentVehiclePartsTree then
    if not partsTreePending then
      partsTreePending = true
      retrievePartsTree()
    end
    return state.availableSeats
  end

  local vehicleId = nil
  local vehicle = getPlayerVehicle()
  if vehicle then
    vehicleId = vehicle:getID()
  end

  if career_career and career_career.isActive() and career_modules_inventory then
    local invId = M.getInventoryIdSafe(vehicleId)
    if not invId then
      state.availableSeats = 0
      state.vehicleOpenSeats = 0
      local seatCap = M.getDriverSeatCap()
      state.seatCap = seatCap == math.huge and nil or seatCap
      return 0
    end
  end

  local seatCap = M.getDriverSeatCap()
  local totalCapacity = cyclePartsTree({currentVehiclePartsTree}, 0)
  local vehicleOpenSeats = math.max((tonumber(totalCapacity) or 0) - 1, 0)
  local cappedOpenSeats = math.min(vehicleOpenSeats, seatCap)
  state.availableSeats = math.max(0, math.floor(cappedOpenSeats))
  state.vehicleOpenSeats = math.max(0, math.floor(vehicleOpenSeats))
  state.seatCap = seatCap == math.huge and nil or seatCap
  lastCapacityDebug = {
    vehicleId = vehicleId,
    seatCap = state.seatCap or "unlimited",
    totalCapacity = totalCapacity,
    vehicleOpenSeats = vehicleOpenSeats,
    cappedOpenSeats = cappedOpenSeats,
    availableSeats = state.availableSeats,
    hasPartsTree = currentVehiclePartsTree ~= nil
  }
  emitState()
  return state.availableSeats
end

function M.getCapacityDebug()
  return copyDeep(lastCapacityDebug)
end

function M.getInventoryIdSafe(vehicleId)
  if not vehicleId or not career_modules_inventory or not career_modules_inventory.getInventoryIdFromVehicleId then
    return nil
  end
  return career_modules_inventory.getInventoryIdFromVehicleId(vehicleId)
end

function M.isHardcoreModeEnabled()
  return career_modules_hardcore and career_modules_hardcore.isHardcoreMode and career_modules_hardcore.isHardcoreMode()
end

function M.getEconomySectionMultiplier(sectionName)
  if not career_economyAdjuster or not career_economyAdjuster.getSectionMultiplier then
    return 1.0
  end
  return career_economyAdjuster.getSectionMultiplier(sectionName) or 1.0
end

local function refreshVehiclePayProfile(vehicleId)
  state.vehicleMultiplier = 1.0
  state.vehicleClassName = "C"
  state.vehicleClassDescription = "Standard"
  state.vehiclePerformanceIndex = nil

  if not career_career or not career_career.isActive() then
    return state.vehicleMultiplier
  end

  if not vehicleId and be and be.getPlayerVehicleID then
    vehicleId = be:getPlayerVehicleID(0)
  end

  if not vehicleId or not gameplay_vehiclePerformance or not gameplay_vehiclePerformance.getClassFromVehId then
    return state.vehicleMultiplier
  end

  local result = gameplay_vehiclePerformance.getClassFromVehId(vehicleId)
  if not result or type(result) ~= "table" or type(result.class) ~= "table" then
    return state.vehicleMultiplier
  end

  local className = string.upper(tostring(result.class.name or "C"))
  if not VEHICLE_CLASS_PAY_TIERS[className] then
    className = "C"
  end
  
  local payTier = VEHICLE_CLASS_PAY_TIERS[className]
  local perfIndex = tonumber(result.performanceIndex)
  local normalizedPI = 0.5

  if perfIndex and payTier.maxPI > payTier.minPI then
    normalizedPI = clamp((perfIndex - payTier.minPI) / (payTier.maxPI - payTier.minPI), 0, 1)
  end

  state.vehicleClassName = className
  state.vehicleClassDescription = tostring(result.class.description or result.class.label or payTier.description or "Standard")
  state.vehiclePerformanceIndex = perfIndex and tonumber(string.format("%.1f", perfIndex)) or nil
  state.vehicleMultiplier = payTier.minMultiplier + ((payTier.maxMultiplier - payTier.minMultiplier) * normalizedPI)
  state.vehicleMultiplier = tonumber(string.format("%.2f", state.vehicleMultiplier)) or 1.0

  return state.vehicleMultiplier
end

-- ================================
-- PASSENGER TYPE SYSTEM
-- ================================
local function getPassengerType(typeKey)
  return passengerTypes[typeKey]
end

local function selectRandomPassengerType(valueMultiplier, availableSeats)
  local eligible = {}
  local totalWeight = 0
  
  for typeKey, pt in pairs(passengerTypes) do
    local minSeats = pt.seatRange and pt.seatRange[1] or 1
    local seatsValid = not availableSeats or availableSeats >= (minSeats or 1)
    local valueValid = not valueMultiplier or
                       (valueMultiplier >= (pt.valueRange[1] or 0.0) and valueMultiplier <= (pt.valueRange[2] or 999.0))
    local ratingValid = true
    if pt.driverRatingRange then
      local minR, maxR = pt.driverRatingRange[1], pt.driverRatingRange[2]
      ratingValid = (not minR or state.playerRating >= minR) and (not maxR or state.playerRating <= maxR)
    end

    if seatsValid and valueValid and ratingValid then
      eligible[typeKey] = pt
      totalWeight = totalWeight + pt.selectionWeight
    end
  end
  
  if totalWeight == 0 then return "STANDARD" end
  
  local random = math.random() * totalWeight
  local currentWeight = 0
  
  for typeKey, pt in pairs(eligible) do
    currentWeight = currentWeight + pt.selectionWeight
    if random <= currentWeight then
      return typeKey
    end
  end
  
  return "STANDARD"
end

function M.registerPassengerType(key, data)
  -- Set defaults
  data.baseMultiplier = data.baseMultiplier or 1.0
  data.speedWeight = data.speedWeight or 1.0
  data.distanceWeight = data.distanceWeight or 1.0
  data.selectionWeight = data.selectionWeight or 1
  data.speedTolerance = data.speedTolerance or 0.5
  data.seatRange = data.seatRange or {nil, nil}
  data.valueRange = data.valueRange or {nil, nil}
  data.driverRatingRange = data.driverRatingRange or {nil, nil}
  
  if not data.fareWeights and not data.fareRange then
    data.fareWeights = {
      {min = 0.5, max = 0.8, weight = 3},
      {min = 0.8, max = 1.2, weight = 5},
      {min = 1.2, max = 1.5, weight = 2}
    }
  end
  
  -- Default functions
  if not data.calculateTipBreakdown then
    data.calculateTipBreakdown = function(fare, elapsedTime, speedFactor, pt)
      local baseFare = tonumber(fare.baseFare) or 0
      if speedFactor > 0 then
        return {["Speed Bonus"] = speedFactor * baseFare * pt.speedWeight * 0.5}
      end
      return {}
    end
  end
  
  if not data.getDescription then
    data.getDescription = function(fare, pt)
      return string.format("%s (%d passengers)", pt.name, fare.passengers)
    end
  end
  
  if not data.getPaymentLabel then
    data.getPaymentLabel = function(fare, speedFactor, pt)
      return speedFactor > 0 and "Speed Bonus" or "Time Penalty"
    end
  end
  
  if not data.onUpdate then
    data.onUpdate = function(fare, rideData, pt)
      local s = rideData.currentSensorData
      if s then
        local peak = math.max(math.abs(s.gx2 or 0), math.abs(s.gy2 or 0), math.abs(s.gz2 or 0))
        if peak > 0.6 then
          rideData.roughEvents = (rideData.roughEvents or 0) + 1
        end
      end
    end
  end
  
  if not data.calculateDriverRating then
    data.calculateDriverRating = function(fare, rideData, elapsedTime, speedFactor, pt)
      local rough = (rideData and rideData.roughEvents) or 0
      local rating = 5.0 - (rough * 0.3) + (math.max(-1, math.min(1, speedFactor or 0)) * 0.5)
      if fare and fare.passengers and fare.passengers > 3 then
        rating = rating + 0.2
      end
      return math.max(1, math.min(5, rating))
    end
  end

  log('I', logTag, "Registered passenger type: " .. data.name)
  passengerTypes[key] = data
end

function M.getPassengerTypes()
  local types = {}
  for typeKey, pt in pairs(passengerTypes) do
    table.insert(types, {
      key = typeKey,
      name = pt.name,
      description = pt.description,
      baseMultiplier = pt.baseMultiplier,
      speedWeight = pt.speedWeight,
      selectionWeight = pt.selectionWeight,
      seatRange = pt.seatRange,
      valueRange = pt.valueRange,
      driverRatingRange = pt.driverRatingRange
    })
  end
  return types
end

function M.getCurrentPassengerType()
  if state.currentFare and state.currentFare.passengerType then
    return getPassengerType(state.currentFare.passengerType)
  end
  return nil
end

-- ================================
-- FARE CALCULATION
-- ================================
local function calculateWeightedPassengerCount(minPassengers, maxPassengers)
  minPassengers = math.max(1, math.floor(tonumber(minPassengers) or 1))
  maxPassengers = math.max(minPassengers, math.floor(tonumber(maxPassengers) or minPassengers))

  local totalWeight = 0
  local weights = {}
  for passengerCount = minPassengers, maxPassengers do
    local weight = passengerCount - minPassengers + 1
    weights[passengerCount] = weight
    totalWeight = totalWeight + weight
  end

  local roll = math.random(totalWeight)
  local cumulativeWeight = 0
  for passengerCount = minPassengers, maxPassengers do
    cumulativeWeight = cumulativeWeight + weights[passengerCount]
    if roll <= cumulativeWeight then
      return passengerCount
    end
  end

  return minPassengers
end

local function calculatePassengerCountForType(passengerType)
  if not passengerType or not state.availableSeats or state.availableSeats <= 0 then
    return 1
  end
  
  local minSeats = passengerType.seatRange and passengerType.seatRange[1] or 1
  local maxSeats = passengerType.seatRange and passengerType.seatRange[2] or state.availableSeats
  minSeats = clamp(minSeats or 1, 1, state.availableSeats)
  maxSeats = clamp(maxSeats or state.availableSeats, 1, state.availableSeats)

  return calculateWeightedPassengerCount(minSeats, maxSeats)
end

local function calculateMultiStopPassengerCount()
  local availableSeats = math.max(0, math.floor(tonumber(state.availableSeats) or 0))
  if availableSeats <= 0 then
    return 0
  end

  return calculateWeightedPassengerCount(math.min(2, availableSeats), availableSeats)
end

local function generateFareMultiplier(passengerTypeKey)
  local pt = getPassengerType(passengerTypeKey)
  if not pt then pt = getPassengerType("STANDARD") end
  
  if pt.fareWeights then
    local totalWeight = 0
    for _, tier in ipairs(pt.fareWeights) do
      totalWeight = totalWeight + tier.weight
    end
    
    local random = math.random(totalWeight)
    local currentWeight = 0
    local selectedTier = pt.fareWeights[1]
    
    for _, tier in ipairs(pt.fareWeights) do
      currentWeight = currentWeight + tier.weight
      if random <= currentWeight then
        selectedTier = tier
        break
      end
    end
    
    return math.random(selectedTier.min * 100, selectedTier.max * 100) / 100
  end
  
  local fareRange = pt.fareRange or {0.8, 1.2}
  return math.random(fareRange[1] * 100, fareRange[2] * 100) / 100
end

local function calculateOfferPassengerRating(passengerType, fareMultiplier)
  if not passengerType or not passengerType.fareWeights then
    return 3.0
  end

  local minFare = math.huge
  local maxFare = -math.huge
  for _, tier in ipairs(passengerType.fareWeights) do
    minFare = math.min(minFare, tier.min)
    maxFare = math.max(maxFare, tier.max)
  end

  if maxFare <= minFare then return 3.0 end

  local normalized = (fareMultiplier - minFare) / (maxFare - minFare)
  return 1 + (normalized * 4)
end

-- Direct fare calculation (used by payoutLimits)
local function calculateBaseFare(passengerCount, totalDistance, valueMultiplier, selectedPassengerType)
  valueMultiplier = tonumber(valueMultiplier) or 1.0
  local baseFare = 100 * (passengerCount ^ 0.5) * valueMultiplier * DISTANCE_MULTIPLIER * selectedPassengerType.baseMultiplier
  baseFare = baseFare * (totalDistance / 1000)

  if career_career and career_career.isActive() and M.isHardcoreModeEnabled() then
    baseFare = baseFare * 0.66
  end

  local taxiMultiplier = M.getEconomySectionMultiplier("taxi")
  baseFare = baseFare * taxiMultiplier
  baseFare = math.floor(baseFare + 0.5)

  return baseFare
end

-- ================================
-- PAYOUT LIMITS METHODS
-- ================================
function payoutLimits.getProfile(routeModeOrFare)
  local routeMode = type(routeModeOrFare) == "table" and routeModeOrFare.routeMode or routeModeOrFare
  routeMode = string.lower(tostring(routeMode or "direct"))
  
  if routeMode == "multistop" or routeMode == "multi-stop" or routeMode == "bus" then
    return payoutLimits.profiles.multistop
  end
  return payoutLimits.profiles.direct
end

function payoutLimits.getEffectivePassengers(routeModeOrFare, passengerCount)
  local profile = payoutLimits.getProfile(routeModeOrFare)
  local passengers = clamp(tonumber(passengerCount) or 0, 0, math.huge)
  local fullCount = tonumber(profile.fullPassengerCount)
  
  if fullCount and fullCount > 0 and passengers > fullCount then
    local extraRate = clamp(tonumber(profile.extraPassengerRate) or 1, 0, 1)
    passengers = fullCount + ((passengers - fullCount) * extraRate)
  end
  
  return passengers
end

function payoutLimits.getEffectiveDistance(routeModeOrFare, distanceMeters)
  local profile = payoutLimits.getProfile(routeModeOrFare)
  local distance = clamp(tonumber(distanceMeters) or 0, 0, math.huge)
  local fullDist = tonumber(profile.fullDistanceMeters)
  
  if fullDist and fullDist > 0 and distance > fullDist then
    local extraRate = clamp(tonumber(profile.extraDistanceRate) or 1, 0, 1)
    distance = fullDist + ((distance - fullDist) * extraRate)
  end
  
  return distance
end

function payoutLimits.getMultiplierStack(routeModeOrFare, valueMultiplier, fareMultiplier, streakMultiplier)
  local profile = payoutLimits.getProfile(routeModeOrFare)
  local rawStack = clamp(tonumber(valueMultiplier) or 1.0, 0, math.huge) *
                   clamp(tonumber(fareMultiplier) or 1.0, 0, math.huge) *
                   clamp(tonumber(streakMultiplier) or 1.0, 0, math.huge)
  local stackCap = tonumber(profile.multiplierStackCap)
  
  if stackCap and stackCap > 0 and rawStack > stackCap then
    return stackCap, rawStack, stackCap, rawStack - stackCap
  end
  
  return rawStack, rawStack, stackCap, 0
end

function payoutLimits.calculateBaseFare(routeModeOrFare, passengerCount, totalDistance, valueMultiplier, selectedPassengerType, fareMultiplier, streakMultiplier)
  local paidPassengers = payoutLimits.getEffectivePassengers(routeModeOrFare, passengerCount)
  local paidDistance = payoutLimits.getEffectiveDistance(routeModeOrFare, totalDistance)
  local effectiveStack, rawStack, stackCap, stackReduction = payoutLimits.getMultiplierStack(routeModeOrFare, valueMultiplier, fareMultiplier, streakMultiplier)
  
  return calculateBaseFare(paidPassengers, paidDistance, effectiveStack, selectedPassengerType), {
    originalPassengers = clamp(tonumber(passengerCount) or 0, 0, math.huge),
    originalDistance = clamp(tonumber(totalDistance) or 0, 0, math.huge),
    paidPassengers = paidPassengers,
    paidDistance = paidDistance,
    rawMultiplierStack = rawStack,
    effectiveMultiplierStack = effectiveStack,
    multiplierStackCap = stackCap,
    multiplierStackReduction = stackReduction
  }
end

function payoutLimits.applyFareInfo(fare, limitInfo)
  if not fare or not limitInfo then return end
  
  fare.paidPassengers = tonumber(string.format("%.2f", limitInfo.paidPassengers or fare.passengers or 0))
  fare.paidDistance = tonumber(string.format("%.2f", limitInfo.paidDistance or fare.estimatedDistance or 0))
  fare.rawMultiplierStack = tonumber(string.format("%.2f", limitInfo.rawMultiplierStack or 1))
  fare.effectiveMultiplierStack = tonumber(string.format("%.2f", limitInfo.effectiveMultiplierStack or 1))
  fare.multiplierStackCap = (limitInfo.multiplierStackCap and limitInfo.multiplierStackCap > 0) and tonumber(string.format("%.2f", limitInfo.multiplierStackCap)) or nil
  fare.multiplierStackCapped = (tonumber(limitInfo.multiplierStackReduction) or 0) > 0.001
  fare.passengerPayoutLimited = math.abs((limitInfo.originalPassengers or tonumber(fare.passengers) or 0) - (limitInfo.paidPassengers or 0)) > 0.001
  fare.distancePayoutLimited = math.abs((limitInfo.originalDistance or tonumber(fare.estimatedDistance) or 0) - (limitInfo.paidDistance or 0)) > 0.001
end

function payoutLimits.getDriverLevel()
  return math.floor(clamp(state.playerRating or 0, 0, MAX_DRIVER_RATING))
end

function payoutLimits.getLeveledProfileValue(values, fallback)
  if type(values) == "table" then
    local level = payoutLimits.getDriverLevel()
    return tonumber(values[level] or values[5] or fallback)
  end
  return tonumber(values or fallback)
end

function payoutLimits.applyTipCap(fare, baseFare, totalTips)
  local profile = payoutLimits.getProfile(fare)
  local rawTips = tonumber(totalTips) or 0
  local base = math.max(0, tonumber(baseFare) or 0)
  local softCap = payoutLimits.getLeveledProfileValue(profile.tipSoftCaps, 0) or 0
  local percentRate = payoutLimits.getLeveledProfileValue(profile.tipBasePercentCaps, 0) or 0
  local percentCap = percentRate > 0 and (base * percentRate) or 0
  local cappedTips = rawTips
  local softReduction = 0
  local percentReduction = 0
  local overflowRate = 1

  if rawTips <= 0 then
    return rawTips, {
      rawTips = rawTips, reduction = 0, softCap = softCap, percentCap = percentCap,
      percentRate = percentRate, softReduction = 0, percentReduction = 0,
      overflowRate = overflowRate, driverLevel = payoutLimits.getDriverLevel()
    }
  end

  if softCap > 0 and cappedTips > softCap then
    overflowRate = clamp(tonumber(profile.tipSoftCapOverflowRate) or 1, 0, 1)
    local softenedTips = softCap + ((cappedTips - softCap) * overflowRate)
    softReduction = cappedTips - softenedTips
    cappedTips = softenedTips
  end

  if percentCap > 0 and cappedTips > percentCap then
    percentReduction = cappedTips - percentCap
    cappedTips = percentCap
  end

  return cappedTips, {
    rawTips = rawTips,
    reduction = rawTips - cappedTips,
    softCap = softCap,
    percentCap = percentCap,
    percentRate = percentRate,
    softReduction = softReduction,
    percentReduction = percentReduction,
    overflowRate = overflowRate,
    driverLevel = payoutLimits.getDriverLevel()
  }
end

function payoutLimits.applySoftCap(fare, amount)
  local profile = payoutLimits.getProfile(fare)
  local payment = tonumber(amount) or 0
  local softCap = tonumber(profile.softCap) or 0
  local softCappedPayment = payment
  local softCapReduction = 0
  local overflowRate = 1

  if softCap > 0 and payment > softCap then
    overflowRate = clamp(tonumber(profile.softCapOverflowRate) or 1, 0, 1)
    softCappedPayment = softCap + ((payment - softCap) * overflowRate)
    softCapReduction = payment - softCappedPayment
  end

  local levelCap = payoutLimits.getLevelCap(fare)
  local finalPayment = softCappedPayment
  local levelCapReduction = 0

  if levelCap and levelCap > 0 and finalPayment > levelCap then
    levelCapReduction = finalPayment - levelCap
    finalPayment = levelCap
  end

  return finalPayment, softCap, softCapReduction, overflowRate, levelCap, levelCapReduction
end

function payoutLimits.applyOfferPreview(fare)
  if not fare then return end
  
  local initialBaseFare = tonumber(fare.initialBaseFare or fare.baseFare) or 0
  local previewFare, softCap, softCapReduction, overflowRate, levelCap, levelCapReduction = payoutLimits.applySoftCap(fare, initialBaseFare)
  
  fare.baseFare = previewFare
  fare.initialBaseFare = previewFare
  
  if softCapReduction > 0 then
    fare.uncappedInitialBaseFare = string.format("%.2f", initialBaseFare)
    fare.offerSoftCap = string.format("%.2f", softCap)
    fare.offerSoftCapReduction = string.format("%.2f", softCapReduction)
    fare.offerSoftCapOverflowRate = string.format("%.2f", overflowRate)
  end
  
  if levelCapReduction > 0 then
    fare.uncappedInitialBaseFare = fare.uncappedInitialBaseFare or string.format("%.2f", initialBaseFare)
    fare.offerLevelCap = string.format("%.2f", levelCap)
    fare.offerLevelCapReduction = string.format("%.2f", levelCapReduction)
  end
end

function payoutLimits.getFarePayoutCap(routeMode)
  return tonumber(payoutLimits.getProfile(routeMode).softCap) or 0
end

function payoutLimits.getLevelCap(routeMode)
  local profile = payoutLimits.getProfile(routeMode)
  if profile.ratingHardCapCurve then
    return getRatingCurveValue(profile.ratingHardCapCurve, state.playerRating, nil)
  end
  return payoutLimits.getLeveledProfileValue(profile.levelHardCaps, nil)
end

function payoutLimits.setFarePayoutCap(amount, routeMode)
  local cap = math.max(0, tonumber(amount) or 0)
  if routeMode ~= nil then
    payoutLimits.getProfile(routeMode).softCap = cap
  else
    payoutLimits.profiles.direct.softCap = cap
    payoutLimits.profiles.multistop.softCap = cap
  end
end

-- ================================
-- BUS ROUTES (Multi-stop)
-- ================================
local function getSurfaceHeightAtPosition(pos)
  if not pos or not be or not be.getSurfaceHeightBelow then
    return pos and pos.z or 0
  end

  local topPos = vec3(pos.x, pos.y, pos.z + 2)
  local height = be:getSurfaceHeightBelow(topPos)
  if height and height > -1e10 then return height end

  topPos.z = 1e5
  height = be:getSurfaceHeightBelow(topPos)
  if height and height > -1e10 then return height end

  return pos.z
end

local function formatBusStop(stopData)
  if not stopData or not stopData.pos then return nil end
  
  local scale = stopData.scale or {8, 8, 8}
  local width = tonumber(scale[1]) or tonumber(scale.x) or 8
  local length = tonumber(scale[2]) or tonumber(scale.y) or 8
  local height = tonumber(scale[3]) or tonumber(scale.z) or 8
  local centerPos = vec3(stopData.pos.x, stopData.pos.y, stopData.pos.z)
  local fallbackGroundZ = centerPos.z - (height * 0.5)
  local snappedGroundZ = getSurfaceHeightAtPosition(vec3(centerPos.x, centerPos.y, fallbackGroundZ))
  
  return {
    name = stopData.name,
    stopName = stopData.stopName or stopData.name or "Bus Stop",
    pos = vec3(centerPos.x, centerPos.y, snappedGroundZ + 0.05),
    scale = {width, length, height},
    arrivalRadius = math.max(6, math.max(width, length) * 0.6)
  }
end

local function upcastSimObject(object)
  if object and Sim and Sim.upcast then
    local ok, upcastObject = pcall(Sim.upcast, object)
    if ok and upcastObject then return upcastObject end
  end

  return object
end

local function readObjectVec3(object, methodName, fallback)
  if not object then return fallback end

  local method = object[methodName]
  if type(method) == "function" then
    local ok, value = pcall(method, object)
    if ok and value then
      local vecOk, result = pcall(vec3, value)
      if vecOk and result then return result end
    end
  end

  return fallback
end

local function buildBusStopLookup()
  local stopLookup = {}
  local triggerFolder = scenetree and scenetree.findObject and scenetree.findObject("busstops")
  if not triggerFolder or triggerFolder:getClassName() ~= "SimGroup" then
    return stopLookup
  end

  for index = 0, triggerFolder:getCount() - 1 do
    local trigger = upcastSimObject(triggerFolder:getObject(index))
    if trigger and trigger:getClassName() == "BeamNGTrigger" and trigger.type == "busstop" then
      local pos = readObjectVec3(trigger, "getPosition")
      if pos then
        local scale = readObjectVec3(trigger, "getScale", vec3(8, 8, 8))
        local triggerName = tostring(trigger.name or "")
        local stopEntry = {
          name = triggerName,
          stopName = trigger.stopName or triggerName,
          pos = vec3(pos.x, pos.y, pos.z),
          scale = {scale.x, scale.y, scale.z}
        }
        stopLookup[triggerName] = copyDeep(stopEntry)
        
        local baseName = triggerName:gsub("_b$", "")
        if baseName ~= triggerName and not stopLookup[baseName] then
          stopLookup[baseName] = copyDeep(stopEntry)
        end
      end
    end
  end

  return stopLookup
end

local function getCurrentMissionLevelDir()
  local missionFile = getMissionFilename and getMissionFilename() or nil
  if missionFile and missionFile ~= "" then
    local levelDir = missionFile:match("(.*/)")
    if levelDir and levelDir ~= "" then
      return levelDir
    end
  end

  local levelName = getCurrentLevelIdentifier and getCurrentLevelIdentifier() or nil
  if levelName and levelName ~= "" then
    if core_levels and core_levels.getLevelByName then
      local levelInfo = core_levels.getLevelByName(levelName)
      if levelInfo and levelInfo.dir and levelInfo.dir ~= "" then
        return levelInfo.dir .. "/"
      end
    end
    return "/levels/" .. tostring(levelName) .. "/"
  end
end

local function loadBusRoutes()
  local levelDir = getCurrentMissionLevelDir()
  if not levelDir then return {} end

  if cachedBusRoutes and cachedBusStopsByName and cachedBusLevelDir == levelDir then
    return cachedBusRoutes
  end

  cachedBusLevelDir = levelDir
  cachedBusStopsByName = buildBusStopLookup()
  cachedBusRoutes = {}

  local routeFiles = FS:findFiles(levelDir .. "buslines/", "*.buslines.json", -1, true, false) or {}
  for _, routeFile in ipairs(routeFiles) do
    local data = jsonReadFile(routeFile)
    if data and data.version == 1 and type(data.routes) == "table" then
      for _, route in ipairs(data.routes) do
        local resolvedStops = {}
        for _, stopId in ipairs(route.tasklist or {}) do
          local stopData = cachedBusStopsByName[stopId]
          if stopData then
            table.insert(resolvedStops, formatBusStop(stopData))
          end
        end

        if #resolvedStops >= 2 then
          table.insert(cachedBusRoutes, {
            routeID = tostring(route.routeID or "?"),
            variance = tostring(route.variance or "a"),
            direction = route.direction or "City Loop",
            routeColor = normalizeRouteColor(route.routeColor),
            tasklist = resolvedStops
          })
        end
      end
    end
  end

  return cachedBusRoutes
end

local function chooseMultiStopRouteSegment()
  if state.availableSeats < MULTI_STOP_VEHICLE_SEAT_THRESHOLD then
    return nil
  end

  local routes = loadBusRoutes()
  if not routes or #routes == 0 then return nil end

  local vehicle = getPlayerVehicle()
  if not vehicle then return nil end

  local vehiclePos = vehicle:getPosition()
  local candidates = {}

  for _, route in ipairs(routes) do
    local stops = route.tasklist or {}
    local firstStop = stops[1]
    local distanceToFirstStop = firstStop and firstStop.pos and (firstStop.pos - vehiclePos):length() or nil
    if firstStop and firstStop.pos and #stops >= 2 and distanceToFirstStop and distanceToFirstStop >= MIN_PICKUP_DISTANCE then
      table.insert(candidates, {
        route = route,
        stops = stops,
        distanceToFirstStop = distanceToFirstStop
      })
    end
  end

  if #candidates == 0 then return nil end

  table.sort(candidates, function(left, right)
    return left.distanceToFirstStop < right.distanceToFirstStop
  end)

  local candidate = candidates[math.random(math.min(#candidates, 6))]
  return {
    routeID = candidate.route.routeID,
    variance = candidate.route.variance,
    direction = candidate.route.direction,
    routeColor = candidate.route.routeColor,
    routeLabel = string.format("Line %s%s", tostring(candidate.route.routeID or "?"), string.upper(tostring(candidate.route.variance or "a"))),
    stops = copyDeep(candidate.stops)
  }
end

-- ================================
-- FARE GENERATION
-- ================================
local function estimateOfferDistance(startPos, endPos)
  if not startPos or not endPos then return 0 end
  return startPos:distance(endPos) * 1.2
end

local function estimateStopSequenceDistance(stops, startIndex, endIndex)
  local distance = 0
  for i = startIndex, endIndex - 1 do
    local fromStop = stops[i]
    local toStop = stops[i + 1]
    if fromStop and toStop and fromStop.pos and toStop.pos then
      distance = distance + estimateOfferDistance(fromStop.pos, toStop.pos)
    end
  end
  return distance
end

local function buildMultiStopPassengerPlan(passengerCount, stopCount)
  local plan = {}
  local remaining = math.max(1, tonumber(passengerCount) or 1)
  local totalStops = math.max(1, tonumber(stopCount) or 1)

  for stopIndex = 1, totalStops do
    local stopsLeftAfter = totalStops - stopIndex
    if remaining <= 0 then
      plan[stopIndex] = 0
    elseif stopsLeftAfter <= 0 then
      plan[stopIndex] = remaining
    else
      if math.random() < MULTI_STOP_EMPTY_STOP_CHANCE then
        plan[stopIndex] = 0
      else
        local avgDrop = math.max(1, math.ceil(remaining / (stopsLeftAfter + 1)))
        local maxDrop = math.min(remaining, avgDrop + math.random(0, avgDrop))
        local dropped = math.random(1, math.max(1, maxDrop))
        plan[stopIndex] = dropped
        remaining = remaining - dropped
      end
    end
  end

  return plan
end

local function buildSharedRidePassengerPlan(passengerCount, dropoffCount)
  local plan = {}
  local remaining = math.max(1, tonumber(passengerCount) or 1)
  local totalDropoffs = math.max(1, tonumber(dropoffCount) or 1)

  for dropoffIndex = 1, totalDropoffs do
    local stopsLeftAfter = totalDropoffs - dropoffIndex
    if stopsLeftAfter <= 0 then
      plan[dropoffIndex] = remaining
    else
      local maxDrop = math.max(1, remaining - stopsLeftAfter)
      local dropped = math.random(1, maxDrop)
      plan[dropoffIndex] = dropped
      remaining = remaining - dropped
    end
  end

  return plan
end

local function taxiSpotToStop(spot, fallbackName)
  if not spot or not spot.pos then return nil end
  local spotPath = safeSpotPath(spot)
  local spotName = spot.name or spotPath or fallbackName or "Taxi Stop"

  return {
    name = tostring(spotName),
    stopName = tostring(fallbackName or spotName),
    pos = vec3(spot.pos.x, spot.pos.y, spot.pos.z),
    spotPath = spotPath,
    arrivalRadius = TAXI_STOP_RADIUS
  }
end

local function reserveSharedRideStops(pickupSpot, firstDropoffSpot, dropoffCount)
  local dropoffs = {firstDropoffSpot}
  local usedPaths = {}

  usedPaths[safeSpotPath(pickupSpot) or tostring(pickupSpot)] = true
  usedPaths[safeSpotPath(firstDropoffSpot) or tostring(firstDropoffSpot)] = true

  for _, candidate in ipairs(shuffleSpots(allTaxiSpots or {})) do
    if #dropoffs >= dropoffCount then break end
    local candidatePath = safeSpotPath(candidate) or tostring(candidate)
    local previousDropoff = dropoffs[#dropoffs]
    local farFromPickup = pickupSpot and candidate and pickupSpot.pos and candidate.pos and
                          pickupSpot.pos:distance(candidate.pos) >= SHARED_RIDE_MIN_DROPOFF_DISTANCE
    local farFromPrevious = previousDropoff and candidate and previousDropoff.pos and candidate.pos and
                            previousDropoff.pos:distance(candidate.pos) >= SHARED_RIDE_MIN_DROPOFF_DISTANCE

    if not usedPaths[candidatePath] and farFromPickup and farFromPrevious and reserveSpot(candidate, currentReservationToken) then
      usedPaths[candidatePath] = true
      table.insert(dropoffs, candidate)
      table.insert(reservedDropoffSpots, candidate)
    end
  end

  if #dropoffs < dropoffCount then
    return nil
  end

  return dropoffs
end

local function buildDirectFare(valueMultiplier)
  validPickupSpots = findValidPickupSpots()
  if not validPickupSpots or #validPickupSpots == 0 then
    log('W', logTag, "No nearby pickup locations found")
    return nil
  end

  local pickupSpot, dropoffSpot
  local shuffledPickups = shuffleSpots(validPickupSpots)
  local pickupAttempts = math.min(#shuffledPickups, MAX_TAXI_PICKUP_SAMPLES)

  for index = 1, pickupAttempts do
    local candidatePickup = shuffledPickups[index]
    if candidatePickup.pos then
      pickupSpot, dropoffSpot = reserveTaxiSpots({candidatePickup}, allTaxiSpots, config.fare.minDropoffDistance, MAX_TAXI_DROPOFF_SAMPLES)
      if pickupSpot and dropoffSpot then break end
    end
  end

  if not pickupSpot or not dropoffSpot then
    log('W', logTag, "No reservable taxi pickup/dropoff pair found")
    return nil
  end

  local ptKey = selectRandomPassengerType(valueMultiplier, state.availableSeats)
  local pt = getPassengerType(ptKey)
  local passengerCount = calculatePassengerCountForType(pt)
  local fareMultiplier = generateFareMultiplier(ptKey)
  local streakMultiplier = (state.fareStreak + 1) ^ 0.5
  local offeredDistance = estimateOfferDistance(pickupSpot.pos, dropoffSpot.pos)
  local baseFare, limitInfo = payoutLimits.calculateBaseFare("direct", passengerCount, offeredDistance, valueMultiplier, pt, fareMultiplier, streakMultiplier)
  local passengerRating = calculateOfferPassengerRating(pt, fareMultiplier)

  local fare = {
    routeMode = "direct",
    pickup = {pos = pickupSpot.pos, spotPath = safeSpotPath(pickupSpot)},
    destination = {pos = dropoffSpot.pos, spotPath = safeSpotPath(dropoffSpot)},
    baseFare = baseFare,
    initialBaseFare = baseFare,
    estimatedDistance = offeredDistance,
    valueMultiplier = valueMultiplier,
    fareMultiplier = fareMultiplier,
    streakMultiplier = streakMultiplier,
    passengers = passengerCount,
    passengerRating = string.format("%.1f", passengerRating),
    passengerType = ptKey,
    passengerTypeName = pt.name,
    passengerDescription = pt.description,
    vehicleClassName = state.vehicleClassName,
    vehicleClassDescription = state.vehicleClassDescription,
    vehiclePerformanceIndex = state.vehiclePerformanceIndex,
    vehicleClassMultiplier = state.vehicleMultiplier
  }

  payoutLimits.applyFareInfo(fare, limitInfo)
  payoutLimits.applyOfferPreview(fare)
  return fare
end

local function buildSharedRideFare(valueMultiplier)
  validPickupSpots = findValidPickupSpots()
  if not validPickupSpots or #validPickupSpots == 0 then return nil end

  local availableSeats = math.max(0, math.floor(tonumber(state.availableSeats) or 0))
  if availableSeats < SHARED_RIDE_MIN_SEATS then return nil end

  local ptKey = selectRandomPassengerType(valueMultiplier, availableSeats)
  local pt = getPassengerType(ptKey)
  local passengerCount = math.max(2, calculatePassengerCountForType(pt))
  passengerCount = math.min(passengerCount, availableSeats)
  if passengerCount < 2 then return nil end

  local dropoffCount = math.min(passengerCount, math.random(2, SHARED_RIDE_MAX_DROPOFFS))
  if dropoffCount < 2 then return nil end

  local pickupSpot, firstDropoffSpot
  local shuffledPickups = shuffleSpots(validPickupSpots)
  local pickupAttempts = math.min(#shuffledPickups, MAX_TAXI_PICKUP_SAMPLES)

  for index = 1, pickupAttempts do
    local candidatePickup = shuffledPickups[index]
    if candidatePickup.pos then
      pickupSpot, firstDropoffSpot = reserveTaxiSpots({candidatePickup}, allTaxiSpots, SHARED_RIDE_MIN_DROPOFF_DISTANCE, MAX_TAXI_DROPOFF_SAMPLES)
      if pickupSpot and firstDropoffSpot then break end
    end
  end

  if not pickupSpot or not firstDropoffSpot then return nil end

  local dropoffSpots = reserveSharedRideStops(pickupSpot, firstDropoffSpot, dropoffCount)
  if not dropoffSpots then
    releaseReservations()
    return nil
  end

  local stops = {taxiSpotToStop(pickupSpot, "Shared pickup")}
  for index, spot in ipairs(dropoffSpots) do
    table.insert(stops, taxiSpotToStop(spot, string.format("Drop-off %d", index)))
  end

  local fareMultiplier = generateFareMultiplier(ptKey)
  local streakMultiplier = (state.fareStreak + 1) ^ 0.5
  local stopCount = #stops
  local offeredDistance = estimateStopSequenceDistance(stops, 1, stopCount)
  local baseFare, limitInfo = payoutLimits.calculateBaseFare("multistop", passengerCount, offeredDistance, valueMultiplier, pt, fareMultiplier, streakMultiplier)
  local dropoffPlan = buildSharedRidePassengerPlan(passengerCount, dropoffCount)
  local passengerRating = calculateOfferPassengerRating(pt, fareMultiplier)

  local fare = {
    routeMode = "multistop",
    routeType = "shared",
    routeID = "shared",
    routeDirection = "Shared ride",
    routeLabel = "Shared Ride",
    stops = stops,
    totalStops = stopCount,
    totalDropoffStops = dropoffCount,
    currentStopIndex = 1,
    completedStopCount = 0,
    completedDropoffStops = 0,
    dropoffPlan = dropoffPlan,
    remainingPassengers = passengerCount,
    pickup = copyDeep(stops[1]),
    destination = stops[2] and copyDeep(stops[2]) or nil,
    baseFare = baseFare,
    initialBaseFare = baseFare,
    estimatedDistance = offeredDistance,
    totalRouteDistance = offeredDistance,
    remainingRouteDistance = offeredDistance,
    valueMultiplier = valueMultiplier,
    fareMultiplier = fareMultiplier,
    streakMultiplier = streakMultiplier,
    passengers = passengerCount,
    passengerRating = string.format("%.1f", passengerRating),
    passengerType = ptKey,
    passengerTypeName = pt.name,
    passengerDescription = string.format("Shared ride with %d passengers and %d drop-offs.", passengerCount, dropoffCount),
    vehicleClassName = state.vehicleClassName,
    vehicleClassDescription = state.vehicleClassDescription,
    vehiclePerformanceIndex = state.vehiclePerformanceIndex,
    vehicleClassMultiplier = state.vehicleMultiplier,
    nextStopName = stops[1] and stops[1].stopName or "Shared pickup"
  }

  payoutLimits.applyFareInfo(fare, limitInfo)
  payoutLimits.applyOfferPreview(fare)
  return fare
end

local function buildMultiStopFare(valueMultiplier)
  local routeSegment = chooseMultiStopRouteSegment()
  if not routeSegment then return nil end

  local ptKey = selectRandomPassengerType(valueMultiplier, state.availableSeats)
  local pt = getPassengerType(ptKey)
  local fareMultiplier = generateFareMultiplier(ptKey)
  local streakMultiplier = (state.fareStreak + 1) ^ 0.5
  local stopCount = #routeSegment.stops
  local passengerCount = calculateMultiStopPassengerCount()
  if passengerCount <= 0 then return nil end
  local offeredDistance = estimateStopSequenceDistance(routeSegment.stops, 1, stopCount)
  local baseFare, limitInfo = payoutLimits.calculateBaseFare("multistop", passengerCount, offeredDistance, valueMultiplier, pt, fareMultiplier, streakMultiplier)
  local dropoffPlan = buildMultiStopPassengerPlan(passengerCount, math.max(1, stopCount - 1))
  local passengerRating = calculateOfferPassengerRating(pt, fareMultiplier)

  local fare = {
    routeMode = "multistop",
    routeID = routeSegment.routeID,
    routeVariance = routeSegment.variance,
    routeDirection = routeSegment.direction,
    routeColor = routeSegment.routeColor,
    routeLabel = routeSegment.routeLabel,
    stops = routeSegment.stops,
    totalStops = stopCount,
    totalDropoffStops = math.max(1, stopCount - 1),
    currentStopIndex = 1,
    completedStopCount = 0,
    completedDropoffStops = 0,
    dropoffPlan = dropoffPlan,
    remainingPassengers = passengerCount,
    pickup = copyDeep(routeSegment.stops[1]),
    destination = routeSegment.stops[2] and copyDeep(routeSegment.stops[2]) or nil,
    baseFare = baseFare,
    initialBaseFare = baseFare,
    estimatedDistance = offeredDistance,
    totalRouteDistance = offeredDistance,
    remainingRouteDistance = offeredDistance,
    valueMultiplier = valueMultiplier,
    fareMultiplier = fareMultiplier,
    streakMultiplier = streakMultiplier,
    passengers = passengerCount,
    passengerRating = string.format("%.1f", passengerRating),
    passengerType = ptKey,
    passengerTypeName = pt.name,
    passengerDescription = string.format("%s to %s with %d scheduled stops.", routeSegment.routeLabel, routeSegment.direction, math.max(1, stopCount - 1)),
    vehicleClassName = state.vehicleClassName,
    vehicleClassDescription = state.vehicleClassDescription,
    vehiclePerformanceIndex = state.vehiclePerformanceIndex,
    vehicleClassMultiplier = state.vehicleMultiplier,
    nextStopName = routeSegment.stops[1] and routeSegment.stops[1].stopName or routeSegment.direction
  }

  payoutLimits.applyFareInfo(fare, limitInfo)
  payoutLimits.applyOfferPreview(fare)
  return fare
end

local function generateJob(options)
  options = options or {}
  
  local taxiDisabled, reason = isTaxiDisabled()
  if taxiDisabled then
    log('W', logTag, "Taxi is disabled: " .. reason)
    return nil
  end

  local vehicle = getPlayerVehicle()
  if not vehicle then return nil end

  recalculateCapacity()
  local valueMultiplier = refreshVehiclePayProfile(vehicle:getID())

  local fare = nil

  if isMultiStopUnlocked() then
    if state.availableSeats >= MULTI_STOP_VEHICLE_SEAT_THRESHOLD then
      fare = buildMultiStopFare(valueMultiplier)
    elseif state.availableSeats >= SHARED_RIDE_MIN_SEATS and math.random() < SHARED_RIDE_OFFER_CHANCE then
      fare = buildSharedRideFare(valueMultiplier)
    end
  end

  if not fare then
    fare = buildDirectFare(valueMultiplier)
  end

  if not fare then return nil end

  if options.assignCurrentFare ~= false then
    state.currentFare = fare
  end
  return fare
end

-- ================================
-- ROUTE PLANNING
-- ================================
function M.getLiveRoutePlannerDistance()
  if not core_groundMarkers or not core_groundMarkers.routePlanner then return nil end
  local firstPath = core_groundMarkers.routePlanner.path and core_groundMarkers.routePlanner.path[1]
  return firstPath and tonumber(firstPath.distToTarget)
end

local function hasActiveTaxiRoute()
  if not core_groundMarkers then return false end
  local routeDistance = M.getLiveRoutePlannerDistance()
  if routeDistance and routeDistance > 1 then return true end
  routeDistance = core_groundMarkers.getPathLength and core_groundMarkers.getPathLength() or 0
  return routeDistance and routeDistance > 1
end

local function setTaxiRouteToTarget(targetPos, fallbackFromPos, routeColor)
  if not targetPos then return 0 end
  if not core_groundMarkers or not core_groundMarkers.setPath then return 0 end

  local pathOptions = {clearPathOnReachingTarget = true}
  local markerColor = routeColorToGroundMarkerColor(routeColor)
  if markerColor then
    pathOptions.color = markerColor
  end

  core_groundMarkers.setPath(targetPos, pathOptions)
  local routeDistance = M.getLiveRoutePlannerDistance() or (core_groundMarkers.getPathLength and core_groundMarkers.getPathLength() or 0)
  if routeDistance and routeDistance > 0 then return routeDistance end
  
  if fallbackFromPos then
    return estimateOfferDistance(fallbackFromPos, targetPos)
  end
  return 0
end

local function ensureTaxiRouteToTarget(target, fallbackFromPos)
  local targetPos = target and target.pos or target
  if not targetPos or hasActiveTaxiRoute() then return nil end

  local vehicle = getPlayerVehicle()
  if vehicle then
    local directDistance = (vehicle:getPosition() - targetPos):length()
    local arrivalRadius = math.max(TAXI_STOP_RADIUS, tonumber(target and target.arrivalRadius) or TAXI_STOP_RADIUS)
    if directDistance <= arrivalRadius then return nil end
  end

  local now = os.clock()
  if now - lastRouteRestoreTime < ROUTE_RESTORE_COOLDOWN then return nil end
  lastRouteRestoreTime = now

  return setTaxiRouteToTarget(targetPos, fallbackFromPos, getCityBusRouteColor(state.currentFare))
end

local function restoreActiveFareRoute(vehicle)
  if not state.currentFare then return nil end

  local target = nil
  if machineState == "pickup" then
    target = state.currentFare.pickup
  elseif machineState == "dropoff" then
    target = state.currentFare.destination
  end

  if not target then return nil end
  local fallbackFromPos = vehicle and vehicle:getPosition() or nil
  return ensureTaxiRouteToTarget(target, fallbackFromPos)
end

local function getLiveRemainingDistance(targetPos)
  if not targetPos then return 0 end
  
  local vehicle = getPlayerVehicle()
  if not vehicle then return 0 end
  
  local directDistance = (vehicle:getPosition() - targetPos):length()
  local routeDistance = M.getLiveRoutePlannerDistance() or (core_groundMarkers.getPathLength and core_groundMarkers.getPathLength() or 0)
  
  if directDistance <= 30 then
    return directDistance
  end
  
  return (routeDistance and routeDistance > 0) and routeDistance or directDistance
end

-- ================================
-- SENSOR DATA
-- ================================
local function updateSensorData()
  if not state.currentFare or machineState ~= "dropoff" then return end
  
  local vehicle = getPlayerVehicle()
  if not vehicle then return end
  
  vehicle:queueLuaCommand([[
    local sensors = require('sensors')
    if sensors then
      obj:queueGameEngineLua('gameplay_buberTaxi.onSensorData('..
        (sensors.gx or 0)..','..(sensors.gy or 0)..','..(sensors.gz or 0)..','..
        (sensors.gx2 or 0)..','..(sensors.gy2 or 0)..','..(sensors.gz2 or 0)..')')
    end
  ]])
end

function M.onSensorData(gx, gy, gz, gx2, gy2, gz2)
  local grav = 9.81
  state.rideData.currentSensorData = {
    gx = gx / grav, gy = gy / grav, gz = gz / grav,
    gx2 = gx2 / grav, gy2 = gy2 / grav, gz2 = gz2 / grav,
    timestamp = os.time()
  }
  
  if state.currentFare and state.currentFare.passengerType then
    local pt = getPassengerType(state.currentFare.passengerType)
    if pt and pt.onUpdate then
      pt.onUpdate(state.currentFare, state.rideData, pt)
    end
  end
end

-- ================================
-- BUS STOP SERVICE
-- ================================
local function getTaxiArrivalRadius(target)
  return math.max(TAXI_STOP_RADIUS, tonumber(target and target.arrivalRadius) or TAXI_STOP_RADIUS)
end

local function getVehicleSpeedMps()
  local vehicle = getPlayerVehicle()
  if not vehicle or not vehicle.getVelocity then return 0 end
  local vel = vehicle:getVelocity()
  return vel and vec3(vel.x, vel.y, vel.z):length() or 0
end

local function requestBusStopVehicleState(fare, vehicle)
  if not fare or fare.routeMode ~= "multistop" or fare.routeType == "shared" or not vehicle or not vehicle.queueLuaCommand then
    return
  end

  vehicle:queueLuaCommand([[
    local doorOpenElectrics = 0
    local mainPartName = v and v.config and v.config.mainPartName or ""
    local frontDoorState, rearDoorState, genericDoorState = nil, nil, nil
    
    if electrics and electrics.values then
      doorOpenElectrics = tonumber(electrics.values.dooropen) or 0
      frontDoorState = electrics.values.doorsF_state
      rearDoorState = electrics.values.doorsR_state
      genericDoorState = electrics.values.doors_state
    end
    
    local trackedDoorState = math.max(doorOpenElectrics, tonumber(frontDoorState) or 0, tonumber(rearDoorState) or 0, tonumber(genericDoorState) or 0)
    local isCityBus = mainPartName == 'citybus'
    local busController = isCityBus and controller.getControllerSafe('bus') or nil
    
    obj:queueGameEngineLua('gameplay_buberTaxi.onBusStopVehicleState(' .. serialize({
      capable = isCityBus or frontDoorState ~= nil or rearDoorState ~= nil or genericDoorState ~= nil or (electrics and electrics.values and electrics.values.dooropen ~= nil),
      doorsOpen = (busController and busController.doorsOpen == true) or trackedDoorState > 0.1
    }) .. ')')
  ]])
end

function M.onBusStopVehicleState(busStopState)
  if type(busStopState) ~= "table" or not state.currentFare or state.currentFare.routeMode ~= "multistop" then
    setBusStopVehicleFreeze(false)
    return
  end

  state.currentFare.busStopVehicleState = {
    capable = busStopState.capable == true,
    doorsOpen = busStopState.doorsOpen == true,
    updatedAt = os.clock()
  }
end

function setBusStopVehicleFreeze(shouldFreeze)
  local shouldFreezeState = shouldFreeze == true
  if busStopVehicleFrozen == shouldFreezeState and not shouldFreezeState then return end

  local veh = shouldFreezeState and getPlayerVehicle() or (busStopFrozenVehicle or getPlayerVehicle())
  if not veh then
    busStopVehicleFrozen = false
    busStopFrozenVehicle = nil
    return
  end

  if core_vehicleBridge and core_vehicleBridge.executeAction then
    core_vehicleBridge.executeAction(veh, 'setFreeze', shouldFreezeState)
  end

  busStopVehicleFrozen = shouldFreezeState
  busStopFrozenVehicle = shouldFreezeState and veh or nil
end

local function getCurrentStopPassengerCount(fare, stage)
  if not fare then return 0 end
  if fare.routeMode ~= "multistop" then
    return math.max(0, tonumber(fare.passengers) or 0)
  end
  if stage == "pickup" then
    return math.max(0, tonumber(fare.passengers) or 0)
  end
  local dropoffPlan = fare.dropoffPlan or {}
  local dropoffIndex = math.max(1, math.min(#dropoffPlan, tonumber(fare.currentStopIndex) or 1))
  local remainingPassengers = math.max(0, tonumber(fare.remainingPassengers) or tonumber(fare.passengers) or 0)
  return math.min(remainingPassengers, math.max(0, tonumber(dropoffPlan[dropoffIndex]) or 0))
end

local function getStopServiceOnboardPassengers(fare, stage, passengersAtStop, processedPassengers)
  local totalPassengers = math.max(0, tonumber(fare and fare.passengers) or 0)
  local remainingPassengers = math.max(0, tonumber(fare and fare.remainingPassengers) or totalPassengers)
  local clampedPassengersAtStop = math.max(0, tonumber(passengersAtStop) or 0)
  local processed = clamp(math.floor(tonumber(processedPassengers) or 0), 0, clampedPassengersAtStop)

  if stage == "pickup" then
    return totalPassengers
  end

  return math.max(0, remainingPassengers - processed)
end

local function updateFareStopService(fare, stage, target, vehicle)
  if not fare or not target or not vehicle then return false end
  
  local speedMps = getVehicleSpeedMps()
  local isMultiStop = fare.routeMode == "multistop"
  local busCapable = isMultiStop and fare.routeType ~= "shared" and fare.busStopVehicleState and fare.busStopVehicleState.capable
  local passengersAtStop = getCurrentStopPassengerCount(fare, stage)

  -- Initialize stop service state
  fare.stopService = fare.stopService or {
    requiredSeconds = PASSENGER_STOP_SERVICE_SECONDS,
    remaining = PASSENGER_STOP_SERVICE_SECONDS,
    startedAt = nil,
    active = false,
    serviceComplete = false
  }
  fare.stopService.stage = stage
  fare.stopService.targetName = target.stopName or target.name
  fare.stopService.passengerTotal = passengersAtStop
  
  if busCapable then
    if passengersAtStop <= 0 then
      setBusStopVehicleFreeze(false)
      fare.stopService = nil
      return true
    end

    if speedMps > PASSENGER_STOP_SPEED_THRESHOLD then
      fare.stopService.instructionStep = "stop"
      fare.stopService.instructionHtml = "Stop the bus"
      fare.stopService.startedAt = nil
      fare.stopService.active = false
      fare.stopService.remaining = PASSENGER_STOP_SERVICE_SECONDS
      fare.stopService.waitingPassengers = passengersAtStop
      fare.stopService.onboardPassengers = getStopServiceOnboardPassengers(fare, stage, passengersAtStop, 0)
      setBusStopVehicleFreeze(false)
      return false
    end

    if fare.stopService.serviceComplete then
      if fare.busStopVehicleState.doorsOpen then
        fare.stopService.instructionStep = "close"
        fare.stopService.instructionHtml = "Close the doors"
        fare.stopService.active = false
        fare.stopService.remaining = 0
        fare.stopService.waitingPassengers = 0
        fare.stopService.onboardPassengers = getStopServiceOnboardPassengers(fare, stage, passengersAtStop, passengersAtStop)
        setBusStopVehicleFreeze(true)
        return false
      end

      setBusStopVehicleFreeze(false)
      fare.stopService = nil
      return true
    end

    if not fare.busStopVehicleState.doorsOpen then
      fare.stopService.instructionStep = "open"
      fare.stopService.instructionHtml = "Open the doors"
      fare.stopService.startedAt = nil
      fare.stopService.active = false
      fare.stopService.waitingPassengers = passengersAtStop
      fare.stopService.onboardPassengers = getStopServiceOnboardPassengers(fare, stage, passengersAtStop, 0)
      setBusStopVehicleFreeze(true)
      return false
    end

    if not fare.stopService.startedAt then
      fare.stopService.startedAt = os.clock()
    end

    fare.stopService.active = true
    local elapsed = os.clock() - fare.stopService.startedAt
    local processedPassengers = math.floor(elapsed * BUS_PASSENGER_SERVICE_RATE)
    local waitingPassengers = math.max(0, passengersAtStop - processedPassengers)
    fare.stopService.remaining = waitingPassengers
    fare.stopService.waitingPassengers = waitingPassengers
    fare.stopService.instructionStep = "wait"
    fare.stopService.instructionHtml = stage == "pickup" and
      string.format("Wait for %d passenger(s) to board", waitingPassengers) or
      string.format("Wait for %d passenger(s) to exit", waitingPassengers)
    fare.stopService.onboardPassengers = getStopServiceOnboardPassengers(fare, stage, passengersAtStop, processedPassengers)

    if waitingPassengers <= 0 then
      fare.stopService.serviceComplete = true
      fare.stopService.active = false
      fare.stopService.startedAt = nil
      fare.stopService.remaining = 0
      fare.stopService.waitingPassengers = 0
      fare.stopService.onboardPassengers = getStopServiceOnboardPassengers(fare, stage, passengersAtStop, passengersAtStop)
      fare.stopService.instructionStep = "close"
      fare.stopService.instructionHtml = "Close the doors"
      setBusStopVehicleFreeze(true)
    else
      setBusStopVehicleFreeze(true)
    end
    return false
  end

  -- Regular taxi service
  if speedMps <= PASSENGER_STOP_SPEED_THRESHOLD then
    if not fare.stopService.startedAt then
      fare.stopService.startedAt = os.clock()
    end
    fare.stopService.active = true
    fare.stopService.remaining = math.max(0, PASSENGER_STOP_SERVICE_SECONDS - (os.clock() - fare.stopService.startedAt))
    
    if fare.stopService.remaining <= 0 then
      fare.stopService = nil
      return true
    end
  else
    fare.stopService.startedAt = nil
    fare.stopService.active = false
    fare.stopService.remaining = PASSENGER_STOP_SERVICE_SECONDS
    fare.stopService.serviceComplete = false
    if isMultiStop then
      fare.stopService.instructionStep = "stop"
      fare.stopService.instructionHtml = fare.routeType == "shared" and "Stop for passenger service" or "Stop the bus"
    end
  end
  return false
end

-- ================================
-- MULTI-STOP FARE PROGRESSION
-- ================================
local function getMultiStopTotalStops(fare)
  if not fare then return 0 end
  return math.max(0, tonumber(fare.totalStops) or #(fare.stops or {}))
end

local function getMultiStopDropoffStopCount(fare)
  return math.max(0, getMultiStopTotalStops(fare) - 1)
end

local function setMultiStopDestinationForIndex(fare, reachedStopIndex)
  if fare.routeMode ~= "multistop" then return false end
  
  local stops = fare.stops or {}
  local totalStops = getMultiStopTotalStops(fare)
  if totalStops < 2 then return false end

  local currentIndex = clamp(tonumber(reachedStopIndex) or 1, 1, totalStops)
  fare.currentStopIndex = currentIndex
  fare.completedStopCount = currentIndex
  fare.completedDropoffStops = math.max(0, currentIndex - 1)
  fare.totalDropoffStops = getMultiStopDropoffStopCount(fare)

  if currentIndex >= totalStops then
    fare.destination = nil
    fare.nextStopName = nil
    fare.remainingRouteDistance = 0
    fare.remainingDistance = 0
    return false
  end

  local currentStop = stops[currentIndex]
  local nextStop = stops[currentIndex + 1]
  fare.destination = nextStop and copyDeep(nextStop) or nil
  fare.nextStopName = nextStop and nextStop.stopName or fare.routeLabel
  fare.remainingRouteDistance = estimateStopSequenceDistance(stops, currentIndex, totalStops)

  local legDistance = 0
  if nextStop and nextStop.pos then
    legDistance = setTaxiRouteToTarget(nextStop.pos, currentStop and currentStop.pos or nil, getCityBusRouteColor(fare))
  end

  fare.currentLegDistance = legDistance or 0
  fare.remainingDistance = legDistance or 0
  return nextStop ~= nil
end

local function advanceMultiStopFare(fare)
  if fare.routeMode ~= "multistop" then return false end
  
  local totalStops = getMultiStopTotalStops(fare)
  if totalStops < 2 then return false end

  local arrivedStopIndex = math.min(totalStops, (tonumber(fare.currentStopIndex) or 1) + 1)
  local dropoffIndex = math.max(1, arrivedStopIndex - 1)
  local remainingBeforeStop = math.max(0, tonumber(fare.remainingPassengers) or tonumber(fare.passengers) or 0)
  local droppedPassengers = math.min(remainingBeforeStop, math.max(0, tonumber(fare.dropoffPlan and fare.dropoffPlan[dropoffIndex]) or 0))

  fare.lastStopName = fare.destination and fare.destination.stopName or nil
  fare.lastStopDroppedPassengers = droppedPassengers
  fare.remainingPassengers = math.max(0, remainingBeforeStop - droppedPassengers)

  if arrivedStopIndex >= totalStops then
    fare.currentStopIndex = arrivedStopIndex
    fare.completedStopCount = arrivedStopIndex
    fare.completedDropoffStops = getMultiStopDropoffStopCount(fare)
    fare.totalDropoffStops = getMultiStopDropoffStopCount(fare)
    fare.destination = nil
    fare.nextStopName = nil
    fare.remainingRouteDistance = 0
    fare.remainingDistance = 0
    return false
  end

  return setMultiStopDestinationForIndex(fare, arrivedStopIndex)
end

-- ================================
-- SPEED FACTOR
-- ================================
local function calculateSpeedFactor()
  if not state.currentFare then return 0 end
  local elapsedTime = os.difftime(os.time(), state.currentFare.startTime)
  if elapsedTime <= 0 then return 0 end
  local travelDistance = state.currentFare.chargedDistance or state.currentFare.totalDistance or 0
  local actualSpeed = travelDistance / elapsedTime
  return (actualSpeed - SUGGESTED_SPEED) / SUGGESTED_SPEED
end

-- ================================
-- JOB LIFECYCLE
-- ================================
local function beginFareResultDisplay(fareData, nextState, clearResultOnReturn)
  state.lastCompletedFare = copyDeep(fareData)
  machineState = "complete"
  completedFareDisplayUntil = os.clock() + COMPLETED_FARE_DISPLAY_SECONDS
  completedFareNextState = nextState or "ready"
  completedFareClearResultOnReturn = clearResultOnReturn == true
  emitState()
end

local function calculateAbandonmentPenalty()
  return math.min(config.rating.abandonMaxPenalty, config.rating.abandonBasePenalty + ((state.shiftAbandonCount - 1) * config.rating.abandonScalePenalty))
end

local function applyAbandonmentPenalty(fare)
  state.shiftAbandonCount = state.shiftAbandonCount + 1
  
  local previousRating = state.playerRating
  local intendedPenalty = calculateAbandonmentPenalty()

  state.ratingSum = math.max(0, state.ratingSum - (intendedPenalty * RATING_SUM_PER_LEVEL))
  state.playerRating = calculateRatingFromSum(state.ratingSum)
  savePlayerRating()
  if recalculateCapacity then recalculateCapacity() end
  state.lastPassengerRating = nil

  local actualPenalty = math.max(0, previousRating - state.playerRating)
  local abandonedFare = copyDeep(fare or {})
  local totalDistanceMeters = tonumber(abandonedFare.totalDistance) or tonumber(abandonedFare.estimatedDistance) or 0

  abandonedFare.resultType = "abandoned"
  abandonedFare.totalFare = "0.00"
  abandonedFare.totalDistance = string.format("%.2f", totalDistanceMeters / 1000)
  abandonedFare.ratingPenalty = actualPenalty
  abandonedFare.shiftOffenceCount = state.shiftAbandonCount

  return abandonedFare, actualPenalty, state.shiftAbandonCount
end

local function completeRide()
  if not state.currentFare then return end

  local completedFare = state.currentFare
  local elapsedTime = os.difftime(os.time(), state.currentFare.startTime)
  local speedFactor = calculateSpeedFactor()
  local pt = getPassengerType(completedFare.passengerType) or passengerTypes.STANDARD

  state.fareStreak = state.fareStreak + 1

  local chargeDistance = completedFare.chargedDistance or completedFare.estimatedDistance or completedFare.totalDistance
  local baseFare, limitInfo = payoutLimits.calculateBaseFare(
    completedFare,
    completedFare.passengers,
    chargeDistance,
    completedFare.valueMultiplier or 1.0,
    pt,
    tonumber(completedFare.fareMultiplier) or 1.0,
    tonumber(completedFare.streakMultiplier) or 1.0
  )
  payoutLimits.applyFareInfo(completedFare, limitInfo)
  completedFare.baseFare = string.format("%.2f", baseFare)

  -- Calculate tips
  local tipBreakdown = pt.calculateTipBreakdown and pt.calculateTipBreakdown(completedFare, elapsedTime, speedFactor, pt) or {}
  local rawTotalTips = 0
  for _, tipAmount in pairs(tipBreakdown) do
    rawTotalTips = rawTotalTips + tipAmount
  end
  
  local totalTips, tipLimitInfo = payoutLimits.applyTipCap(completedFare, baseFare, rawTotalTips)
  local tipCapReduction = tonumber(tipLimitInfo.reduction) or 0

  local uncappedPayment = baseFare + totalTips
  local finalPayment, payoutCapValue, payoutCapReduction, payoutOverflowRate, payoutLevelCapValue, payoutLevelCapReduction = payoutLimits.applySoftCap(completedFare, uncappedPayment)

  state.cumulativeReward = state.cumulativeReward + finalPayment

  completedFare.totalTips = string.format("%.2f", totalTips)
  completedFare.tipBreakdown = tipBreakdown
  
  if tipCapReduction > 0 then
    completedFare.rawTotalTips = string.format("%.2f", rawTotalTips)
    completedFare.tipCapReduction = string.format("%.2f", tipCapReduction)
    completedFare.tipSoftCap = string.format("%.2f", tipLimitInfo.softCap or 0)
    completedFare.tipBasePercentCap = string.format("%.2f", tipLimitInfo.percentCap or 0)
    completedFare.tipBasePercentRate = string.format("%.2f", tipLimitInfo.percentRate or 0)
    completedFare.tipSoftCapOverflowRate = string.format("%.2f", tipLimitInfo.overflowRate or 1)
    completedFare.tipCapDriverLevel = tipLimitInfo.driverLevel
  end

  completedFare.totalFare = string.format("%.2f", finalPayment)
  completedFare.uncappedTotalFare = string.format("%.2f", uncappedPayment)
  
  if payoutCapReduction > 0 then
    completedFare.payoutSoftCap = string.format("%.2f", payoutCapValue)
    completedFare.payoutSoftCapReduction = string.format("%.2f", payoutCapReduction)
    completedFare.payoutSoftCapOverflowRate = string.format("%.2f", payoutOverflowRate)
  end
  
  if payoutLevelCapReduction > 0 then
    completedFare.payoutLevelCap = string.format("%.2f", payoutLevelCapValue)
    completedFare.payoutLevelCapReduction = string.format("%.2f", payoutLevelCapReduction)
  end

  completedFare.timeMultiplier = string.format("%.1f", 1 + speedFactor)
  completedFare.totalDistance = string.format("%.2f", (tonumber(completedFare.totalDistance) or 0) / 1000)

  -- Update driver rating
  local passengerGivenRating = pt.calculateDriverRating and pt.calculateDriverRating(completedFare, state.rideData, elapsedTime, speedFactor, pt) or 5.0
  state.lastPassengerRating = passengerGivenRating
  state.ratingSum = state.ratingSum + passengerGivenRating
  state.ratingCount = state.ratingCount + 1
  state.playerRating = calculateRatingFromSum(state.ratingSum)
  savePlayerRating()
  if recalculateCapacity then recalculateCapacity() end

  completedFare.resultType = "completed"
  resetCityBusDisplay()
  beginFareResultDisplay(completedFare, "ready", false)
  setBusStopVehicleFreeze(false)
  clearReturnToVehicleTimer()
  state.currentFare = nil
  state.preparedFare = nil
  jobOfferTimer = 0
  jobOfferInterval = math.random(JOB_OFFER_INTERVAL_MIN, JOB_OFFER_INTERVAL_MAX)
  showToast(BRAND_NAME, "Fare completed. Waiting for next passenger.", "success")
  core_groundMarkers.resetAll()
  releaseReservations()
  emitState()

  -- Build reward label
  local fareDescription = pt.getDescription(completedFare, pt)
  local paymentLabel = pt.getPaymentLabel(completedFare, speedFactor, pt)
  local completedDistanceMeters = tonumber(completedFare.totalDistance) or 0
  local label = string.format("%s fare: %s: $%s | Distance: %s | %s: x %.2f",
    BRAND_NAME, fareDescription, completedFare.totalFare, formatDistance(completedDistanceMeters * 1000, 1), paymentLabel, completedFare.timeMultiplier)

  if completedFare.multiplierStackCapped then
    label = label .. string.format("\nMultiplier stack limited to x%.2f.", tonumber(completedFare.effectiveMultiplierStack) or 0)
  end
  if completedFare.passengerPayoutLimited or completedFare.distancePayoutLimited then
    label = label .. "\nMulti-stop payout smoothing applied."
  end
  if tipCapReduction > 0 then
    label = label .. string.format("\nTip cap reduced excess tips by $%d.", math.floor(tipCapReduction))
  end
  if payoutCapReduction > 0 then
    label = label .. string.format("\nSoft payout cap reduced excess earnings by $%d.", math.floor(payoutCapReduction))
  end
  if payoutLevelCapReduction > 0 then
    label = label .. string.format("\nDriver rating payout cap applied: $%d max.", math.floor(payoutLevelCapValue))
  end

  if career_career and career_career.isActive() then
    if M.isHardcoreModeEnabled() then
      label = label .. "\nHardcore mode is enabled, all rewards lowered."
    end

    if career_modules_playerAttributes and career_modules_playerAttributes.addAttributes then
      career_modules_playerAttributes.addAttributes({money = math.floor(finalPayment)}, {label = BRAND_NAME .. " Fare Reward", description = label, tags = {"transport", "taxi", "reward"}}, true)
    elseif career_modules_payment and career_modules_payment.reward then
      career_modules_payment.reward({money = {amount = math.floor(finalPayment)}}, {label = BRAND_NAME .. " Fare Reward", description = label, tags = {"transport", "taxi", "reward"}}, true)
    end

    if career_modules_inventory and career_modules_inventory.addTaxiDropoff then
      local playerVehicleId = be and be:getPlayerVehicleID(0) or nil
      local inventoryId = M.getInventoryIdSafe(playerVehicleId)
      if inventoryId then
        career_modules_inventory.addTaxiDropoff(inventoryId, completedFare.passengers)
      end
    end

    M.saveCareerAfterDropoff()
  end
end

function M.saveCareerAfterDropoff()
  if not career_career or not career_career.isActive() then return end
  if not career_saveSystem or not career_saveSystem.saveCurrent then return end

  local success, err = pcall(career_saveSystem.saveCurrent)
  if not success then
    log('E', logTag, "Failed to auto-save after dropoff: " .. tostring(err))
  end
end

-- ================================
-- STATE TRANSITIONS
-- ================================
function M.acceptJob()
  local taxiDisabled, reason = isTaxiDisabled()
  if taxiDisabled then
    log('W', logTag, "Taxi is disabled: " .. reason)
    return
  end
  if not state.currentFare then
    log('W', logTag, "No current fare to accept")
    return
  end

  setBusStopVehicleFreeze(false)
  clearReturnToVehicleTimer()
  state.preparedFare = nil
  state.currentFare.startTime = os.time()
  machineState = "pickup"
  state.rideData = {}
  
  local vehicle = getPlayerVehicle()
  local vehiclePos = vehicle and vehicle:getPosition() or nil
  local pickupDistance = setTaxiRouteToTarget(state.currentFare.pickup.pos, vehiclePos, getCityBusRouteColor(state.currentFare))
  state.currentFare.totalDistance = pickupDistance or 0
  state.currentFare.remainingDistance = pickupDistance or 0
  
  if state.currentFare.routeMode == "multistop" then
    state.currentFare.completedStopCount = 0
    state.currentFare.completedDropoffStops = 0
    state.currentFare.totalDropoffStops = getMultiStopDropoffStopCount(state.currentFare)
    state.currentFare.remainingPassengers = tonumber(state.currentFare.remainingPassengers) or tonumber(state.currentFare.passengers) or 0
    state.currentFare.nextStopName = state.currentFare.pickup and state.currentFare.pickup.stopName or state.currentFare.routeLabel
  end

  if not syncCityBusDisplayWithFare(state.currentFare) then
    resetCityBusDisplay()
  end
  
  emitState()
end

function M.rejectJob()
  resetCityBusDisplay()
  releaseReservations()
  setBusStopVehicleFreeze(false)
  clearReturnToVehicleTimer()
  state.currentFare = nil
  state.preparedFare = nil
  core_groundMarkers.resetAll()
  machineState = "ready"
  state.fareStreak = 0
  jobOfferTimer = 0
  jobOfferInterval = math.random(JOB_OFFER_INTERVAL_MIN, JOB_OFFER_INTERVAL_MAX)
  emitState()
end

function M.abandonCurrentJob()
  if not state.currentFare then return end

  local abandonedFare = nil
  local ratingPenalty = 0
  local offenceCount = 0

  if machineState == "dropoff" then
    abandonedFare, ratingPenalty, offenceCount = applyAbandonmentPenalty(state.currentFare)
  end

  resetCityBusDisplay()
  releaseReservations()
  setBusStopVehicleFreeze(false)
  clearReturnToVehicleTimer()
  state.currentFare = nil
  state.preparedFare = nil
  core_groundMarkers.resetAll()
  machineState = "ready"
  jobOfferTimer = 0
  jobOfferInterval = math.random(JOB_OFFER_INTERVAL_MIN, JOB_OFFER_INTERVAL_MAX)
  state.fareStreak = 0
  emitState()

  if abandonedFare then
    beginFareResultDisplay(abandonedFare, "ready", true)
    showToast(BRAND_NAME, string.format("Passenger abandoned. Driver rating -%.2f. Offence #%d this shift.", ratingPenalty, offenceCount), "warning")
  else
    showToast(BRAND_NAME, "Fare abandoned. Waiting for the next passenger.", "warning")
  end
end

local function cancelCurrentFareForVehicleExit()
  if not state.currentFare and not state.preparedFare then return end

  resetCityBusDisplay()
  releaseReservations()
  setBusStopVehicleFreeze(false)
  clearReturnToVehicleTimer()
  state.currentFare = nil
  state.preparedFare = nil
  core_groundMarkers.resetAll()
  machineState = (gameplay_walk and gameplay_walk.isWalking()) and "start" or "ready"
  jobOfferTimer = 0
  jobOfferInterval = math.random(JOB_OFFER_INTERVAL_MIN, JOB_OFFER_INTERVAL_MAX)
  state.fareStreak = 0
  emitState()
  showToast(BRAND_NAME, "Fare cancelled. Return to your vehicle to keep driving.", "warning")
end

function M.setAvailable()
  local taxiDisabled, reason = isTaxiDisabled()
  if taxiDisabled then
    log('W', logTag, "Taxi is disabled: " .. reason)
    return
  end

  machineState = "ready"
  state.shiftAbandonCount = 0
  jobOfferTimer = 0
  jobOfferInterval = math.random(JOB_OFFER_INTERVAL_MIN, JOB_OFFER_INTERVAL_MAX)
  resetCityBusDisplay()
  setBusStopVehicleFreeze(false)
  clearReturnToVehicleTimer()
  state.preparedFare = nil
  emitState()
end

function M.stopTaxiJob()
  local abandonedFare = nil
  local ratingPenalty = 0
  local offenceCount = 0

  if state.currentFare and machineState == "dropoff" then
    abandonedFare, ratingPenalty, offenceCount = applyAbandonmentPenalty(state.currentFare)
  end

  resetCityBusDisplay()
  releaseReservations()
  setBusStopVehicleFreeze(false)
  clearReturnToVehicleTimer()
  state.currentFare = nil
  state.preparedFare = nil
  core_groundMarkers.resetAll()
  machineState = "start"
  jobOfferTimer = 0
  jobOfferInterval = math.random(JOB_OFFER_INTERVAL_MIN, JOB_OFFER_INTERVAL_MAX)
  state.cumulativeReward = 0
  state.fareStreak = 0
  emitState()

  if abandonedFare then
    beginFareResultDisplay(abandonedFare, "start", true)
    showToast(BRAND_NAME, string.format("Passenger abandoned. Driver rating -%.2f. Offence #%d this shift.", ratingPenalty, offenceCount), "warning")
  else
    state.lastCompletedFare = nil
    state.shiftAbandonCount = 0
  end
end

-- ================================
-- TAXI ZONE VISUALIZATION
-- ================================
local function drawDebugSpotCylinder(spot, colorValues, radius, height)
  if not spot or not spot.pos then return end

  local bottomPos = vec3(spot.pos.x, spot.pos.y, spot.pos.z)
  local topPos = bottomPos + vec3(0, 0, height or 2)
  debugDrawer:drawCylinder(bottomPos:toPoint3F(), topPos:toPoint3F(), radius or 1, makeColorF(colorValues))
end

local function getDebugBusStops()
  loadBusRoutes()

  local stops = {}
  local seen = {}
  for key, stop in pairs(cachedBusStopsByName or {}) do
    if stop and stop.pos then
      local posKey = string.format("%.1f:%.1f:%.1f", stop.pos.x, stop.pos.y, stop.pos.z)
      if not seen[posKey] then
        seen[posKey] = true
        local formatted = formatBusStop(stop) or stop
        formatted.debugName = stop.stopName or stop.name or tostring(key)
        table.insert(stops, formatted)
      end
    end
  end

  return stops
end

local function drawDebugTaxiSpots()
  if not taxiSpotDebug.enabled or not debugDrawer then return end

  findParkingSpots()
  local mode = tostring(taxiSpotDebug.mode or "all"):lower()

  if mode == "all" then
    for _, spot in ipairs(allTaxiSpots or {}) do
      drawDebugSpotCylinder(spot, TAXI_DEBUG_SPOT_COLORS.all, 0.85, 1.6)
    end
  end

  if mode == "all" or mode == "nearby" then
    local pickupSpots = findValidPickupSpots()
    for _, spot in ipairs(pickupSpots or {}) do
      drawDebugSpotCylinder(spot, TAXI_DEBUG_SPOT_COLORS.pickup, 1.05, 2.25)
    end
  end

  if mode == "all" or mode == "bus" then
    for _, stop in ipairs(getDebugBusStops()) do
      drawDebugSpotCylinder(stop, TAXI_DEBUG_SPOT_COLORS.bus, 1.35, 3.25)
    end
  end

  drawDebugSpotCylinder(reservedPickupSpot, TAXI_DEBUG_SPOT_COLORS.reserved, 1.25, 3.0)
  drawDebugSpotCylinder(reservedDropoffSpot, TAXI_DEBUG_SPOT_COLORS.reserved, 1.25, 3.0)
end

local function getTaxiSpotDebugStats()
  findParkingSpots()
  local pickupSpots = findValidPickupSpots()
  local busStops = getDebugBusStops()

  return {
    enabled = taxiSpotDebug.enabled,
    mode = taxiSpotDebug.mode,
    allSpots = #(allTaxiSpots or {}),
    nearbyPickupSpots = #(pickupSpots or {}),
    busStops = #(busStops or {})
  }
end

function M.debugDrawTaxiSpots(enabled, mode)
  taxiSpotDebug.enabled = enabled ~= false
  taxiSpotDebug.mode = tostring(mode or "all"):lower()
  if taxiSpotDebug.mode ~= "all" and taxiSpotDebug.mode ~= "nearby" and taxiSpotDebug.mode ~= "bus" then
    taxiSpotDebug.mode = "all"
  end

  pickupCacheVehiclePos = nil
  validPickupSpots = nil

  local stats = getTaxiSpotDebugStats()
  log("I", logTag, string.format("Taxi spot debug draw %s. Mode: %s, all spots: %d, nearby pickups: %d, bus stops: %d",
    stats.enabled and "enabled" or "disabled", stats.mode, stats.allSpots, stats.nearbyPickupSpots, stats.busStops))
  return stats
end

function M.debugShowAllTaxiSpots(enabled)
  return M.debugDrawTaxiSpots(enabled, "all")
end

function M.debugListTaxiSpots()
  findParkingSpots()
  pickupCacheVehiclePos = nil
  validPickupSpots = nil

  local pickupSpots = findValidPickupSpots()
  local busStops = getDebugBusStops()
  local pickupLookup = {}
  for _, spot in ipairs(pickupSpots or {}) do
    pickupLookup[spot] = true
  end

  local vehicle = getPlayerVehicle()
  local vehiclePos = vehicle and vehicle:getPosition() or nil
  local total = #(allTaxiSpots or {})

  log("I", logTag, string.format("BUBER taxi spots: %d all spots, %d nearby pickup candidates, %d bus stops.", total, #(pickupSpots or {}), #(busStops or {})))

  for index, spot in ipairs(allTaxiSpots or {}) do
    local pos = spot and spot.pos
    local spotPath = safeSpotPath(spot) or tostring(spot and spot.name or ("spot_" .. index))
    local distance = (vehiclePos and pos) and (pos - vehiclePos):length() or 0
    local pickupText = pickupLookup[spot] and "yes" or "no"
    local emptyText = isSpotEmpty(spot) and "yes" or "no"

    if pos then
      log("I", logTag, string.format("#%03d pickup=%s empty=%s dist=%.1fm pos=(%.2f, %.2f, %.2f) %s",
        index, pickupText, emptyText, distance, pos.x, pos.y, pos.z, spotPath))
    else
      log("I", logTag, string.format("#%03d pickup=%s empty=%s %s", index, pickupText, emptyText, spotPath))
    end
  end

  for index, stop in ipairs(busStops or {}) do
    local pos = stop and stop.pos
    local stopName = tostring(stop and (stop.debugName or stop.stopName or stop.name) or ("bus_stop_" .. index))
    local distance = (vehiclePos and pos) and (pos - vehiclePos):length() or 0

    if pos then
      log("I", logTag, string.format("BUS #%03d dist=%.1fm pos=(%.2f, %.2f, %.2f) %s",
        index, distance, pos.x, pos.y, pos.z, stopName))
    else
      log("I", logTag, string.format("BUS #%03d %s", index, stopName))
    end
  end

  return {
    allSpots = total,
    nearbyPickupSpots = #(pickupSpots or {}),
    busStops = #(busStops or {})
  }
end

local function drawActiveTaxiZone()
  if not debugDrawer or not state.currentFare then return end

  local markerKind, targetPos
  if machineState == "accept" or machineState == "pickup" then
    markerKind = "pickup"
    targetPos = state.currentFare.pickup and state.currentFare.pickup.pos or nil
  elseif machineState == "dropoff" then
    markerKind = "dropoff"
    targetPos = state.currentFare.destination and state.currentFare.destination.pos or nil
  else
    return
  end

  if not targetPos then return end

  local vehicle = getPlayerVehicle()
  local inRange = false
  if vehicle then
    local vehiclePos = vehicle:getPosition()
    local targetData = markerKind == "pickup" and state.currentFare.pickup or state.currentFare.destination
    inRange = isInsideArea(vec3(vehiclePos.x, vehiclePos.y, vehiclePos.z), targetPos, getTaxiArrivalRadius(targetData))
  end

  local colorValues = inRange and TAXI_ZONE_COLORS[markerKind].active or TAXI_ZONE_COLORS[markerKind].inactive
  local bottomPos = vec3(targetPos.x, targetPos.y, targetPos.z)
  local topPos = bottomPos + vec3(0, 0, TAXI_STOP_HEIGHT)
  debugDrawer:drawCylinder(bottomPos:toPoint3F(), topPos:toPoint3F(), TAXI_ZONE_DRAW_RADIUS, makeColorF(colorValues))
end

local function teardownTaxiMarkers()
  taxiSpotDebug.enabled = false
end

-- ================================
-- MAIN UPDATE LOOP
-- ================================
local function update(dt)
  drawDebugTaxiSpots()
  drawActiveTaxiZone()

  -- Handle completed fare display timeout
  if machineState == "complete" and completedFareDisplayUntil > 0 and os.clock() >= completedFareDisplayUntil then
    local nextState = completedFareNextState or "ready"
    local clearResult = completedFareClearResultOnReturn
    completedFareDisplayUntil = 0
    completedFareNextState = "ready"
    completedFareClearResultOnReturn = false
    machineState = nextState
    if clearResult then
      state.lastCompletedFare = nil
      if nextState == "start" then
        state.shiftAbandonCount = 0
      end
    end
    emitState()
  end

  timer = timer + dt
  if timer < UPDATE_INTERVAL then return end
  timer = 0

  local walking = gameplay_walk and gameplay_walk.isWalking()
  local activeVehicle = getPlayerVehicle()
  local awayFromVehicle = walking or not activeVehicle
  if state.currentFare then
    if awayFromVehicle then
      if machineState == "dropoff" then
        startReturnToVehicleTimer()
        if (getReturnToVehicleSeconds() or 0) <= 0 then
          M.abandonCurrentJob()
          return
        end
        emitState()
        return
      elseif machineState == "accept" or machineState == "pickup" then
        cancelCurrentFareForVehicleExit()
        return
      end
    elseif isReturnToVehicleTimerActive() then
      clearReturnToVehicleTimer()
      restoreActiveFareRoute(activeVehicle)
      syncCityBusDisplayWithFare(state.currentFare)
      showToast(BRAND_NAME, "Trip resumed.", "success")
      emitState()
    end
  end

  -- Handle fare offer expiration
  if state.currentFare and machineState == "accept" and state.currentFare.offerExpiresAt then
    if os.time() >= state.currentFare.offerExpiresAt then
      M.rejectJob()
      showToast(BRAND_NAME, string.format("Fare offer expired after %ds.", JOB_ACCEPT_TIMEOUT_SECONDS), "warning")
      emitState()
      return
    end
  end

  -- PICKUP state
  if state.currentFare and machineState == "pickup" then
    local vehicle = getPlayerVehicle()
    if vehicle then
      requestBusStopVehicleState(state.currentFare, vehicle)
      local vehiclePos = vehicle:getPosition()
      local restoredDistance = ensureTaxiRouteToTarget(state.currentFare.pickup, vehiclePos)
      local distToPickup = (vehiclePos - state.currentFare.pickup.pos):length()
      state.currentFare.remainingDistance = math.max(restoredDistance or getLiveRemainingDistance(state.currentFare.pickup.pos), 0)

      if distToPickup < getTaxiArrivalRadius(state.currentFare.pickup) then
        if updateFareStopService(state.currentFare, "pickup", state.currentFare.pickup, vehicle) then
          releaseSpot(reservedPickupSpot, currentReservationToken)
          reservedPickupSpot = nil
          machineState = "dropoff"
          state.currentFare.startTime = os.time()
          state.rideData = {}

          if state.currentFare.routeMode == "multistop" then
            notifyCityBusDepartedStop(state.currentFare, state.currentFare.pickup)
            state.currentFare.totalDistance = state.currentFare.totalRouteDistance or state.currentFare.estimatedDistance or 0
            state.currentFare.chargedDistance = state.currentFare.totalRouteDistance or state.currentFare.estimatedDistance or 0
            if not setMultiStopDestinationForIndex(state.currentFare, 1) then
              completeRide()
              return
            end
          else
            local dropoffDistance = setTaxiRouteToTarget(state.currentFare.destination.pos, state.currentFare.pickup and state.currentFare.pickup.pos or nil, getCityBusRouteColor(state.currentFare))
            state.currentFare.totalDistance = (state.currentFare.totalDistance or 0) + (dropoffDistance or 0)
            state.currentFare.remainingDistance = dropoffDistance or 0
            state.currentFare.chargedDistance = dropoffDistance or state.currentFare.estimatedDistance or 0
          end
          emitState()
        end
      else
        state.currentFare.stopService = nil
      end
    else
      setBusStopVehicleFreeze(false)
    end
    emitState()
  end

  -- DROPOFF state
  if state.currentFare and machineState == "dropoff" then
    updateSensorData()
    
    local vehicle = getPlayerVehicle()
    if vehicle then
      requestBusStopVehicleState(state.currentFare, vehicle)
      local vehiclePos = vehicle:getPosition()
      local restoredDistance = ensureTaxiRouteToTarget(state.currentFare.destination, vehiclePos)
      state.currentFare.remainingDistance = math.max(restoredDistance or getLiveRemainingDistance(state.currentFare.destination.pos), 0)
      local destDist = (vehiclePos - state.currentFare.destination.pos):length()

      if destDist < getTaxiArrivalRadius(state.currentFare.destination) then
        local stopServiceStage = state.currentFare.routeMode == "multistop" and "stop" or "dropoff"
        if updateFareStopService(state.currentFare, stopServiceStage, state.currentFare.destination, vehicle) then
          if state.currentFare.routeMode == "multistop" then
            local servedStop = state.currentFare.destination
            notifyCityBusDepartedStop(state.currentFare, servedStop)
            if advanceMultiStopFare(state.currentFare) then
              emitState()
            else
              completeRide()
            end
          else
            completeRide()
          end
        else
          emitState()
        end
      else
        state.currentFare.stopService = nil
        emitState()
      end
    else
      setBusStopVehicleFreeze(false)
    end
  end

  -- READY state - waiting for job offers
  if machineState == "ready" then
    local taxiDisabled, reason = isTaxiDisabled()
    if taxiDisabled then
      log('W', logTag, "Taxi became disabled: " .. reason)
      state.preparedFare = nil
      machineState = "start"
      emitState()
      return
    end

    jobOfferTimer = jobOfferTimer + 1
    local prepareThreshold = math.max(jobOfferInterval - JOB_OFFER_PREPARE_LEAD_TIME, 0)

    if not state.preparedFare and jobOfferTimer >= prepareThreshold then
      state.preparedFare = generateJob({assignCurrentFare = false})
    end

    if jobOfferTimer >= jobOfferInterval then
      local newFare = state.preparedFare
      state.preparedFare = nil

      if not newFare then
        newFare = generateJob({assignCurrentFare = false})
      end

      if newFare then
        newFare.offerExpiresAt = os.time() + JOB_ACCEPT_TIMEOUT_SECONDS
        state.currentFare = newFare
        machineState = "accept"
      else
        jobOfferTimer = 0
        jobOfferInterval = math.random(JOB_OFFER_INTERVAL_MIN, JOB_OFFER_INTERVAL_MAX)
      end
      emitState()
    end
  end
end

-- ================================
-- LIFECYCLE HOOKS
-- ================================
local function onEnterVehicleFinished()
  validPickupSpots = nil
  pickupCacheVehiclePos = nil
  findParkingSpots()
  loadPlayerRating()
end

local function onVehicleSwitched()
  currentVehiclePartsTree = nil
  partsTreePending = false
  local walking = gameplay_walk and gameplay_walk.isWalking()
  local vehicle = getPlayerVehicle()
  local awayFromVehicle = walking or not vehicle

  if state.currentFare then
    if awayFromVehicle then
      if machineState == "dropoff" then
        startReturnToVehicleTimer()
        emitState()
        return
      end
      cancelCurrentFareForVehicleExit()
      return
    end

    if isReturnToVehicleTimerActive() then
      clearReturnToVehicleTimer()
      if vehicle then
        recalculateCapacity()
        refreshVehiclePayProfile(vehicle:getID())
      end
      restoreActiveFareRoute(vehicle)
      syncCityBusDisplayWithFare(state.currentFare)
      showToast(BRAND_NAME, "Trip resumed.", "success")
      emitState()
      return
    end

    if vehicle and (machineState == "pickup" or machineState == "dropoff") then
      recalculateCapacity()
      refreshVehiclePayProfile(vehicle:getID())
      restoreActiveFareRoute(vehicle)
      syncCityBusDisplayWithFare(state.currentFare)
      emitState()
      return
    end
  end

  machineState = "start"
  
  if state.currentFare then
    core_groundMarkers.resetAll()
  end
  
  resetCityBusDisplay()
  releaseReservations()
  setBusStopVehicleFreeze(false)
  clearReturnToVehicleTimer()
  state.currentFare = nil
  state.lastCompletedFare = nil
  state.preparedFare = nil
  jobOfferTimer = 0
  jobOfferInterval = math.random(JOB_OFFER_INTERVAL_MIN, JOB_OFFER_INTERVAL_MAX)
  state.cumulativeReward = 0
  state.fareStreak = 0
  state.shiftAbandonCount = 0
  state.availableSeats = 0
  state.vehicleOpenSeats = 0
  state.seatCap = 0
  state.vehicleMultiplier = 1.0
  state.vehicleClassName = "C"
  state.vehicleClassDescription = "Standard"
  state.vehiclePerformanceIndex = nil
  validPickupSpots = nil
  pickupCacheVehiclePos = nil
  
  if vehicle and not walking then
    recalculateCapacity()
    refreshVehiclePayProfile(vehicle:getID())
  end
  
  emitState()
end

local function onExtensionLoaded()
  -- Refresh config reference in case it was reloaded
  config = gameplay_taxiConfig or config
  log('I', logTag, BRAND_NAME .. " module loaded")
  loadPassengerModules()
  invalidateLocationCaches()
  findParkingSpots()
  loadPlayerRating()
end

local function onExtensionUnloaded()
  -- Clean shutdown: unload passenger modules so they don't linger
  -- and interfere with the base game's extension system on rejoin.
  log('I', logTag, BRAND_NAME .. " module unloading")
  unloadPassengerModules()
  invalidateLocationCaches()
  setBusStopVehicleFreeze(false)
  clearReturnToVehicleTimer()
  core_groundMarkers.resetAll()
end

local function onSaveCurrentSaveSlot(currentSavePath)
  savePlayerRating(currentSavePath)
end

function M.isTaxiJobActive()
  return machineState ~= "start"
end

-- ================================
-- EXPORTS
-- ================================
M.onExtensionLoaded = onExtensionLoaded
M.onExtensionUnloaded = onExtensionUnloaded
M.onEnterVehicleFinished = onEnterVehicleFinished
M.onUpdate = update
M.onVehicleSwitched = onVehicleSwitched
M.onSaveCurrentSaveSlot = onSaveCurrentSaveSlot

M.acceptJob = M.acceptJob
M.rejectJob = M.rejectJob
M.abandonCurrentJob = M.abandonCurrentJob
M.setAvailable = M.setAvailable
M.stopTaxiJob = M.stopTaxiJob

M.getDriverRating = M.getDriverRating
M.setDriverRating = M.setDriverRating
M.getDriverSeatCap = M.getDriverSeatCap
M.getCapacityDebug = M.getCapacityDebug
M.returnPartsTree = M.onPartsTreeReceived

M.registerPassengerType = M.registerPassengerType
M.getPassengerTypes = M.getPassengerTypes
M.getCurrentPassengerType = M.getCurrentPassengerType

M.setFarePayoutCap = payoutLimits.setFarePayoutCap
M.getFarePayoutCap = payoutLimits.getFarePayoutCap

M.getInventoryIdSafe = M.getInventoryIdSafe
M.isHardcoreModeEnabled = M.isHardcoreModeEnabled
M.getEconomySectionMultiplier = M.getEconomySectionMultiplier
M.isTaxiJobActive = M.isTaxiJobActive
M.debugDrawTaxiSpots = M.debugDrawTaxiSpots
M.debugShowAllTaxiSpots = M.debugShowAllTaxiSpots
M.debugListTaxiSpots = M.debugListTaxiSpots

M.saveCareerAfterDropoff = M.saveCareerAfterDropoff

-- Config access
M.getConfig = function() return config end

return M
