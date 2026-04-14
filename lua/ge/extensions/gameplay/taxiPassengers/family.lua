local M = {}
local logTag = "familyPassenger"

local FAMILY_CONFIG = {
  name = "Family",
  description = "Families prioritizing safe, smooth rides with more seats",
  baseMultiplier = 0.6,
  speedWeight = -0.2,
  distanceWeight = 1.1,
  selectionWeight = 3,
  seatRange = {4, 8},
  valueRange = {0.6, nil},
  fareWeights = {
    {min = 0.7, max = 1.0, weight = 5},
    {min = 1.0, max = 1.3, weight = 3},
    {min = 1.3, max = 1.6, weight = 1},
  },
  speedTolerance = 0.4,
}

-- ================================
-- PRIVATE HELPERS
-- ================================

local function clampRating(rating)
  return math.max(1, math.min(5, rating))
end

local function calculateSmoothnessScore(sensorData, rideData)
  if not sensorData then return nil end

  local gx = sensorData.gx
  local gy = sensorData.gy
  local gz = sensorData.gz or 0
  local totalGForce = math.sqrt(gx * gx + gy * gy + gz * gz)

  -- Track peak G-force
  if totalGForce > (rideData.peakG or 0) then
    rideData.peakG = totalGForce
  end

  local currentScore = rideData.smoothnessScore or 100

  if totalGForce > 2.0 then
    return math.max(0, currentScore - 20)
  elseif math.abs(gx) > 0.7 or math.abs(gy) > 0.6 then
    return math.max(0, currentScore - 2)
  else
    return math.min(100, currentScore + 0.5)
  end
end

-- ================================
-- PASSENGER TYPE CALLBACKS
-- ================================

local function calculateTipBreakdown(fare, elapsedTime, speedFactor, passengerType)
  local tipBreakdown = {}
  local baseFare = tonumber(fare.baseFare) or 0
  local smoothness = fare.rideQuality and fare.rideQuality.smoothness or 0

  if speedFactor < -0.05 then
    tipBreakdown["Safe Driving"] = 0.2 * baseFare
  end
  if smoothness > 0.75 then
    tipBreakdown["Smooth Ride"] = 0.15 * baseFare
  end
  return tipBreakdown
end

local function calculateDriverRating(fare, rideData, elapsedTime, speedFactor, passengerType)
  local smoothness = (fare.rideQuality and fare.rideQuality.smoothness) or 1.0
  local speedDeviation = tonumber(speedFactor) or 0
  local rating = 5.0

  rating = rating - (1 - smoothness) * 2.0

  if speedDeviation > 0 then
    rating = rating - math.min(1.0, speedDeviation) * 0.8
  elseif speedDeviation < -0.1 and smoothness > 0.85 then
    rating = rating + 0.2
  end

  return clampRating(rating)
end

local function onUpdate(fare, rideData, passengerType)
  local newScore = calculateSmoothnessScore(rideData.currentSensorData, rideData)

  if newScore then
    rideData.smoothnessScore = newScore
    fare.rideQuality = fare.rideQuality or {}
    fare.rideQuality.smoothness = rideData.smoothnessScore / 100
    fare.rideQuality.peakG = rideData.peakG
  end
end

local function getDescription(fare, passengerType)
  return string.format("%s (%d passengers) - Keep it safe", passengerType.name, fare.passengers)
end

local function getPaymentLabel(fare, speedFactor, passengerType)
  local label = speedFactor < 0 and "Safe Driving" or "Standard"
  local smoothness = fare.rideQuality and fare.rideQuality.smoothness
  if smoothness and smoothness > 0.8 then
    label = label .. " | Smooth Ride"
  end
  return label
end

-- ================================
-- LIFECYCLE
-- ================================

local function onExtensionLoaded()
  if not gameplay_taxi then
    log("W", logTag, "gameplay_taxi not loaded, skipping registration")
    return
  end

  gameplay_taxi.registerPassengerType("FAMILY", {
    -- Config
    name = FAMILY_CONFIG.name,
    description = FAMILY_CONFIG.description,
    baseMultiplier = FAMILY_CONFIG.baseMultiplier,
    speedWeight = FAMILY_CONFIG.speedWeight,
    distanceWeight = FAMILY_CONFIG.distanceWeight,
    selectionWeight = FAMILY_CONFIG.selectionWeight,
    seatRange = FAMILY_CONFIG.seatRange,
    valueRange = FAMILY_CONFIG.valueRange,
    fareWeights = FAMILY_CONFIG.fareWeights,
    speedTolerance = FAMILY_CONFIG.speedTolerance,
    -- Callbacks
    calculateTipBreakdown = calculateTipBreakdown,
    onUpdate = onUpdate,
    calculateDriverRating = calculateDriverRating,
    getDescription = getDescription,
    getPaymentLabel = getPaymentLabel,
  })
end

-- ================================
-- EXPORTS
-- ================================

M.onExtensionLoaded = onExtensionLoaded

return M