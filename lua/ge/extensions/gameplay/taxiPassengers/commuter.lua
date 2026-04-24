local M = {}
local logTag = "commuterPassenger"

local COMMUTER_CONFIG = {
  name = "Commuter",
  description = "Daily riders who value punctual, steady driving",
  baseMultiplier = 0.65,
  speedWeight = 0.9,
  distanceWeight = 1.0,
  selectionWeight = 5,
  seatRange = {1, 5},
  valueRange = {0.4, 1.8},
  fareWeights = {
    {min = 0.8, max = 1.1, weight = 5},
    {min = 1.1, max = 1.4, weight = 3},
    {min = 1.4, max = 1.7, weight = 1},
  },
  speedTolerance = 0.4,
}

-- ================================
-- PRIVATE HELPERS
-- ================================

local function getComfortBonus(comfort, passengers)
  local bonus = 0
  if comfort > 0.97 and passengers <= 2 then
    bonus = bonus + 0.1
  end
  return bonus
end

local function clampRating(rating)
  return math.max(1, math.min(5, rating))
end

local function calculateComfortScore(sensorData, currentScore)
  if not sensorData then return currentScore, 0 end

  local gx, gy = sensorData.gx, sensorData.gy
  if math.abs(gx) > 0.8 or math.abs(gy) > 0.8 then
    return math.max(0, currentScore - 2), 0
  end
  return math.min(100, currentScore + 0.5), 1
end

-- ================================
-- PASSENGER TYPE CALLBACKS
-- ================================

local function calculateTipBreakdown(fare, elapsedTime, speedFactor, passengerType)
  local tipBreakdown = {}
  local baseFare = tonumber(fare.baseFare) or 0
  if speedFactor > 0.05 then
    tipBreakdown["On-Time Bonus"] = math.min(speedFactor * baseFare * 0.35, 0.35 * baseFare)
  end
  if fare.rideQuality and fare.rideQuality.comfort and fare.rideQuality.comfort > 0.8 then
    tipBreakdown["Comfort"] = 0.1 * baseFare
  end
  return tipBreakdown
end

local function calculateDriverRating(fare, rideData, elapsedTime, speedFactor, passengerType)
  local comfort = (fare.rideQuality and fare.rideQuality.comfort) or 1.0
  local speedDeviation = tonumber(speedFactor) or 0
  local rating = 5.0

  -- Base comfort adjustment
  rating = rating - (1 - comfort) * 2.5

  -- Speed deviation penalty/reward
  if speedDeviation < 0 then
    rating = rating - math.min(1.0, -speedDeviation) * 1.0
  elseif speedDeviation > 0 then
    rating = rating + math.min(0.5, speedDeviation) * 0.5
  end

  -- On-time bonus
  if elapsedTime and elapsedTime > 0 and comfort > 0.95 and speedDeviation >= 0 then
    rating = rating + 0.1
  end

  -- Low passenger comfort bonus
  rating = rating + getComfortBonus(comfort, fare.passengers or 0)

  return clampRating(rating)
end

local function onUpdate(fare, rideData, passengerType)
  rideData.comfortScore = rideData.comfortScore or 100
  local newScore, delta = calculateComfortScore(rideData.currentSensorData, rideData.comfortScore)

  if delta ~= 0 then
    rideData.comfortScore = newScore
    fare.rideQuality = fare.rideQuality or {}
    fare.rideQuality.comfort = rideData.comfortScore / 100
  end
end

local function getDescription(fare, passengerType)
  return string.format("%s (%d passengers) - Routine trip", passengerType.name, fare.passengers)
end

local function getPaymentLabel(fare, speedFactor, passengerType)
  local label = speedFactor > 0 and "On-Time Bonus" or "Standard"
  local comfort = fare.rideQuality and fare.rideQuality.comfort
  if comfort and comfort > 0.85 then
    label = label .. " | Comfort"
  end
  return label
end

-- ================================
-- LIFECYCLE
-- ================================

local function onExtensionLoaded()
  if not gameplay_buberTaxi then
    log("W", logTag, "gameplay_buberTaxi not loaded, skipping registration")
    return
  end

  gameplay_buberTaxi.registerPassengerType("COMMUTER", {
    -- Config
    name = COMMUTER_CONFIG.name,
    description = COMMUTER_CONFIG.description,
    baseMultiplier = COMMUTER_CONFIG.baseMultiplier,
    speedWeight = COMMUTER_CONFIG.speedWeight,
    distanceWeight = COMMUTER_CONFIG.distanceWeight,
    selectionWeight = COMMUTER_CONFIG.selectionWeight,
    seatRange = COMMUTER_CONFIG.seatRange,
    valueRange = COMMUTER_CONFIG.valueRange,
    fareWeights = COMMUTER_CONFIG.fareWeights,
    speedTolerance = COMMUTER_CONFIG.speedTolerance,
    -- Callbacks
    calculateTipBreakdown = calculateTipBreakdown,
    calculateDriverRating = calculateDriverRating,
    onUpdate = onUpdate,
    getDescription = getDescription,
    getPaymentLabel = getPaymentLabel,
  })
end

-- ================================
-- EXPORTS
-- ================================

M.onExtensionLoaded = onExtensionLoaded

return M