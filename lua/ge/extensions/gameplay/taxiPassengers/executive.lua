local M = {}
local logTag = "executivePassenger"

local EXECUTIVE_CONFIG = {
  name = "Executive",
  description = "High-status clients expecting impeccable, quiet service",
  baseMultiplier = 0.9,
  speedWeight = 0.5,
  distanceWeight = 1.1,
  selectionWeight = 1,
  seatRange = {1, 4},
  valueRange = {1.5, nil},
  fareWeights = {
    {min = 1.0, max = 1.3, weight = 3},
    {min = 1.3, max = 1.7, weight = 5},
    {min = 1.7, max = 2.3, weight = 2},
  },
  speedTolerance = 0.3,
}

-- ================================
-- PRIVATE HELPERS
-- ================================

local function clampRating(rating)
  return math.max(1, math.min(5, rating))
end

local function calculateSmoothnessScore(sensorData, currentScore)
  if not sensorData then return currentScore, 0 end

  local gx, gy = sensorData.gx, sensorData.gy
  if math.abs(gx) > 0.6 or math.abs(gy) > 0.55 then
    return math.max(0, currentScore - 3), 0
  end
  return math.min(100, currentScore + 0.6), 1
end

-- ================================
-- PASSENGER TYPE CALLBACKS
-- ================================

local function calculateTipBreakdown(fare, elapsedTime, speedFactor, passengerType)
  local tipBreakdown = {}
  local baseFare = tonumber(fare.baseFare) or 0
  local smoothness = fare.rideQuality and fare.rideQuality.smoothness or 0

  if smoothness > 0.92 then
    tipBreakdown["White-Glove Service"] = 0.5 * baseFare
  elseif smoothness > 0.85 then
    tipBreakdown["Discreet Comfort"] = 0.3 * baseFare
  end
  return tipBreakdown
end

local function calculateDriverRating(fare, rideData, elapsedTime, speedFactor, passengerType)
  local smoothness = (fare.rideQuality and fare.rideQuality.smoothness) or 1.0
  local speedDeviation = tonumber(speedFactor) or 0
  local rating = 5.0

  rating = rating - (1 - smoothness) * 3.0

  if speedDeviation > 0.2 then
    rating = rating - math.min(1.0, speedDeviation) * 1.0
  elseif smoothness > 0.95 and speedDeviation <= 0.1 then
    rating = rating + 0.3
  end

  return clampRating(rating)
end

local function onUpdate(fare, rideData, passengerType)
  rideData.smoothnessScore = rideData.smoothnessScore or 100
  local newScore, delta = calculateSmoothnessScore(rideData.currentSensorData, rideData.smoothnessScore)

  if delta ~= 0 then
    rideData.smoothnessScore = newScore
    fare.rideQuality = fare.rideQuality or {}
    fare.rideQuality.smoothness = rideData.smoothnessScore / 100
  end
end

local function getDescription(fare, passengerType)
  return string.format("%s (%d passengers) - Premium client", passengerType.name, fare.passengers)
end

local function getPaymentLabel(fare, speedFactor, passengerType)
  local smoothness = fare.rideQuality and fare.rideQuality.smoothness
  return (smoothness and smoothness > 0.92) and "White-Glove Service" or "Standard"
end

-- ================================
-- LIFECYCLE
-- ================================

local function onExtensionLoaded()
  if not gameplay_buberTaxi then
    log("W", logTag, "gameplay_buberTaxi not loaded, skipping registration")
    return
  end

  gameplay_buberTaxi.registerPassengerType("EXECUTIVE", {
    -- Config
    name = EXECUTIVE_CONFIG.name,
    description = EXECUTIVE_CONFIG.description,
    baseMultiplier = EXECUTIVE_CONFIG.baseMultiplier,
    speedWeight = EXECUTIVE_CONFIG.speedWeight,
    distanceWeight = EXECUTIVE_CONFIG.distanceWeight,
    selectionWeight = EXECUTIVE_CONFIG.selectionWeight,
    seatRange = EXECUTIVE_CONFIG.seatRange,
    valueRange = EXECUTIVE_CONFIG.valueRange,
    fareWeights = EXECUTIVE_CONFIG.fareWeights,
    speedTolerance = EXECUTIVE_CONFIG.speedTolerance,
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