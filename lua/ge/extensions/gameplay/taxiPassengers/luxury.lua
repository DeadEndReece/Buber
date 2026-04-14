local M = {}
local logTag = "luxuryPassenger"

local LUXURY_CONFIG = {
  name = "Luxury",
  description = "High-paying passengers who value comfort over speed",
  baseMultiplier = 0.7,
  speedWeight = 0.2,
  distanceWeight = 1.2,
  selectionWeight = 2,
  seatRange = {nil, 5},
  valueRange = {1.2, nil},
  fareWeights = {
    {min = 0.5, max = 0.8, weight = 2},
    {min = 0.8, max = 1.2, weight = 6},
    {min = 1.6, max = 2.2, weight = 2},
  },
  speedTolerance = 0.9,
  suggestedSpeed = 18,
  minSpeedThreshold = 2,
}

local AGGRESSIVE_THRESHOLDS = {
  hardBrake = {gy = 0.5, smoothnessPenalty = 10, luxuryPenalty = 15},
  hardAccel = {gy = -0.45, smoothnessPenalty = 8, luxuryPenalty = 12},
  hardCorner = {gx = 0.65, smoothnessPenalty = 8, luxuryPenalty = 10},
}

-- ================================
-- PRIVATE HELPERS
-- ================================

local function clampRating(rating)
  return math.max(1, math.min(5, rating))
end

local function getSpeedTier(actualSpeed, suggestedSpeed)
  local threshold60 = suggestedSpeed * 0.6
  local threshold90 = suggestedSpeed * 0.9
  if actualSpeed <= threshold60 then
    return "Comfort Bonus", threshold60
  elseif actualSpeed <= threshold90 then
    return "Premium Service", threshold90
  else
    return "Speed Penalty", threshold90
  end
end

local function calculateSpeedBonus(actualSpeed, baseFare, suggestedSpeed)
  local threshold60 = suggestedSpeed * 0.6
  local threshold90 = suggestedSpeed * 0.9

  if actualSpeed <= threshold60 then
    local range = threshold60
    local bonus = (threshold60 - actualSpeed) / range * 0.25 * baseFare
    return bonus
  elseif actualSpeed <= threshold90 then
    local range = threshold90
    local bonus = (threshold90 - actualSpeed) / range * 0.15 * baseFare
    return bonus
  end
  return 0
end

local function calculateQualityTiers(smoothness, luxury, baseFare)
  if smoothness > 0.92 and luxury > 0.95 then
    return {tipName = "Immaculate Ride", multiplier = 0.6}
  elseif smoothness > 0.85 and luxury > 0.9 then
    return {tipName = "Premium Comfort", multiplier = 0.35}
  elseif smoothness > 0.75 then
    return {tipName = "Smooth Ride", multiplier = 0.15}
  end
  return nil
end

local function updateRideScores(sensorData, rideData)
  if not sensorData then return nil end

  -- Initialize defaults
  rideData.smoothnessScore = rideData.smoothnessScore or 100
  rideData.aggressiveEvents = rideData.aggressiveEvents or 0
  rideData.luxuryComfort = rideData.luxuryComfort or 100

  local gx, gy, gz = sensorData.gx, sensorData.gy, sensorData.gz or 0
  local totalGForce = math.sqrt(gx * gx + gy * gy + gz * gz)
  local penalties = {smoothness = 0, luxury = 0}

  -- Check aggressive events
  if gy > AGGRESSIVE_THRESHOLDS.hardBrake.gy then
    rideData.aggressiveEvents = rideData.aggressiveEvents + 1
    penalties.smoothness = AGGRESSIVE_THRESHOLDS.hardBrake.smoothnessPenalty
    penalties.luxury = AGGRESSIVE_THRESHOLDS.hardBrake.luxuryPenalty
  elseif gy < AGGRESSIVE_THRESHOLDS.hardAccel.gy then
    rideData.aggressiveEvents = rideData.aggressiveEvents + 1
    penalties.smoothness = AGGRESSIVE_THRESHOLDS.hardAccel.smoothnessPenalty
    penalties.luxury = AGGRESSIVE_THRESHOLDS.hardAccel.luxuryPenalty
  elseif math.abs(gx) > AGGRESSIVE_THRESHOLDS.hardCorner.gx then
    rideData.aggressiveEvents = rideData.aggressiveEvents + 1
    penalties.smoothness = AGGRESSIVE_THRESHOLDS.hardCorner.smoothnessPenalty
    penalties.luxury = AGGRESSIVE_THRESHOLDS.hardCorner.luxuryPenalty
  end

  -- Apply penalties
  if penalties.smoothness > 0 then
    rideData.smoothnessScore = math.max(0, rideData.smoothnessScore - penalties.smoothness)
    rideData.luxuryComfort = math.max(0, rideData.luxuryComfort - penalties.luxury)
  -- Apply recovery
  elseif totalGForce < 0.3 then
    rideData.luxuryComfort = math.min(100, rideData.luxuryComfort + 1)
  end

  return {
    smoothness = rideData.smoothnessScore / 100,
    aggressiveEvents = rideData.aggressiveEvents,
    luxury = rideData.luxuryComfort / 100,
  }
end

-- ================================
-- PASSENGER TYPE CALLBACKS
-- ================================

local function calculateTipBreakdown(fare, elapsedTime, speedFactor, passengerType)
  local tipBreakdown = {}
  local baseFare = tonumber(fare.baseFare) or 0
  local actualSpeed = (tonumber(fare.totalDistance) or 0) / math.max(1, elapsedTime) * 1000

  -- Speed-based tip
  if actualSpeed >= LUXURY_CONFIG.minSpeedThreshold then
    local bonus = calculateSpeedBonus(actualSpeed, baseFare, LUXURY_CONFIG.suggestedSpeed)
    local tier = getSpeedTier(actualSpeed, LUXURY_CONFIG.suggestedSpeed)
    if bonus > 0 then
      tipBreakdown[tier] = bonus
    end
  end

  -- Quality-based tip
  local smoothness = fare.rideQuality and fare.rideQuality.smoothness or 0
  local luxury = fare.rideQuality and fare.rideQuality.luxury or 0
  local qualityTier = calculateQualityTiers(smoothness, luxury, baseFare)
  if qualityTier then
    tipBreakdown[qualityTier.tipName] = qualityTier.multiplier * baseFare
  end

  return tipBreakdown
end

local function calculateDriverRating(fare, rideData, elapsedTime, speedFactor, passengerType)
  local rq = fare.rideQuality or {}
  local smoothness = rq.smoothness or 1.0
  local luxury = rq.luxury or 1.0
  local speedDeviation = tonumber(speedFactor) or 0
  local rating = 5.0

  rating = rating - (1 - smoothness) * 2.5
  rating = rating - (1 - luxury) * 1.5

  if speedDeviation > 0.2 then
    rating = rating - math.min(1.0, speedDeviation) * 1.0
  elseif smoothness > 0.95 and luxury > 0.95 and speedDeviation <= 0.1 then
    rating = rating + 0.4
  end

  return clampRating(rating)
end

local function onUpdate(fare, rideData, passengerType)
  local newQuality = updateRideScores(rideData.currentSensorData, rideData)
  if newQuality then
    fare.rideQuality = newQuality
  end
end

local function getDescription(fare, passengerType)
  return string.format("%s (%d passengers) - Premium fare", passengerType.name, fare.passengers)
end

local function getPaymentLabel(fare, speedFactor, passengerType)
  local elapsedTime = os.difftime(os.time(), fare.startTime or os.time())
  local totalDistance = tonumber(fare.totalDistance) or 0
  local distance = tonumber(fare.paidDistance) or tonumber(fare.chargedDistance) or tonumber(fare.estimatedDistance)
  if not distance then
    distance = totalDistance > 0 and totalDistance < 1000 and totalDistance * 1000 or totalDistance
  end

  local actualSpeed = distance / math.max(1, elapsedTime)
  local tier, _ = getSpeedTier(actualSpeed, LUXURY_CONFIG.suggestedSpeed)
  local label = tier

  local rq = fare.rideQuality
  if rq then
    if rq.luxury and rq.luxury > 0.95 and rq.smoothness and rq.smoothness > 0.92 then
      label = label .. " | Immaculate Ride"
    elseif rq.luxury and rq.luxury > 0.9 then
      label = label .. " | Premium Comfort"
    elseif rq.smoothness and rq.smoothness < 0.6 then
      label = label .. " | Unacceptable Service"
    elseif rq.aggressiveEvents and rq.aggressiveEvents > 2 then
      label = label .. " | Too Rough"
    end
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

  gameplay_taxi.registerPassengerType("LUXURY", {
    -- Config
    name = LUXURY_CONFIG.name,
    description = LUXURY_CONFIG.description,
    baseMultiplier = LUXURY_CONFIG.baseMultiplier,
    speedWeight = LUXURY_CONFIG.speedWeight,
    distanceWeight = LUXURY_CONFIG.distanceWeight,
    selectionWeight = LUXURY_CONFIG.selectionWeight,
    seatRange = LUXURY_CONFIG.seatRange,
    valueRange = LUXURY_CONFIG.valueRange,
    fareWeights = LUXURY_CONFIG.fareWeights,
    speedTolerance = LUXURY_CONFIG.speedTolerance,
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
