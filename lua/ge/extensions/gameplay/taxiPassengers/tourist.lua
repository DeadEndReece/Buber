local M = {}
local logTag = 'touristPassenger'

-- ================================
-- CONSTANTS
-- ================================
local TIP = {
  SCENIC_BONUS_CAP = 0.5,
  PERFECT_PACE_CAP = 0.35,
  GOOD_PACE_CAP = 0.15,
  COMFORTABLE_TOUR_MULT = 0.5,
  SMOOTH_EXPERIENCE_MULT = 0.25,
  WONDERFUL_TOUR = 0.25
}

local THRESHOLDS = {
  SUGGESTED_SPEED = 18,
  MIN_SPEED = 1.5,
  GY_HIGH = 0.65,
  GY_LOW = -0.55,
  GX_AGGRESSIVE = 0.8,
  TOTAL_G_GENTLE = 0.4,
  GENTLE_RIDE_TIME = 20,
  SMOOTHNESS_EXCELLENT = 0.8,
  SMOOTHNESS_GOOD = 0.6,
  SMOOTHNESS_SCORE_THRESHOLD = 80,
  SMOOTHNESS_SCORE_MAX = 100,
  SCENIC_EXPERIENCE_MAX = 100
}

local PENALTIES = {
  GY_HIGH_SMOOTHNESS = 8,
  GY_HIGH_SCENIC = 12,
  GY_LOW_SMOOTHNESS = 6,
  GY_LOW_SCENIC = 10,
  GX_SMOOTHNESS = 6,
  GX_SCENIC = 8,
  GENTLE_SCENIC_BONUS = 1
}

local RATING = {
  BASE = 5.0,
  MIN = 1.0,
  MAX = 5.0,
  SMOOTHNESS_MULT = 2.0,
  SPEED_PENALTY_MULT = 0.8,
  SCENIC_BONUS = 0.4
}

local SPEED_ZONES = {
  {maxMult = 0.6, label = "Scenic Bonus", tipKey = "Scenic Bonus"},
  {maxMult = 0.8, label = "Perfect Pace", tipKey = "Perfect Pace"},
  {maxMult = 1.0, label = "Good Pace", tipKey = "Good Pace"},
  {label = "Too Fast", tipKey = nil}
}

-- ================================
-- HELPER FUNCTIONS
-- ================================
local function getRideQuality(fare)
  return fare.rideQuality
end

local function calcActualSpeed(fare, elapsedTime)
  local distance = tonumber(fare.totalDistance) or 0
  return distance / math.max(1, elapsedTime) * 1000
end

local function getSpeedZone(actualSpeed)
  local suggested = THRESHOLDS.SUGGESTED_SPEED
  for _, zone in ipairs(SPEED_ZONES) do
    local threshold = zone.maxMult and suggested * zone.maxMult
    if not threshold or actualSpeed <= threshold then
      return zone
    end
  end
  return SPEED_ZONES[#SPEED_ZONES]
end

local function initTouristData(rideData)
  if rideData.smoothnessScore then return end
  rideData.smoothnessScore = THRESHOLDS.SMOOTHNESS_SCORE_MAX
  rideData.aggressiveEvents = 0
  rideData.scenicExperience = THRESHOLDS.SCENIC_EXPERIENCE_MAX
  rideData.gentleRideTime = 0
end

local function processGForce(rideData)
  if not rideData.currentSensorData then return end

  local gx = rideData.currentSensorData.gx or 0
  local gy = rideData.currentSensorData.gy or 0
  local gz = rideData.currentSensorData.gz or 0
  local totalG = math.sqrt(gx * gx + gy * gy + gz * gz)

  -- Aggressive events (acceleration/braking)
  if gy > THRESHOLDS.GY_HIGH then
    rideData.aggressiveEvents = rideData.aggressiveEvents + 1
    rideData.smoothnessScore = math.max(0, rideData.smoothnessScore - PENALTIES.GY_HIGH_SMOOTHNESS)
    rideData.scenicExperience = math.max(0, rideData.scenicExperience - PENALTIES.GY_HIGH_SCENIC)

  elseif gy < THRESHOLDS.GY_LOW then
    rideData.aggressiveEvents = rideData.aggressiveEvents + 1
    rideData.smoothnessScore = math.max(0, rideData.smoothnessScore - PENALTIES.GY_LOW_SMOOTHNESS)
    rideData.scenicExperience = math.max(0, rideData.scenicExperience - PENALTIES.GY_LOW_SCENIC)

  elseif math.abs(gx) > THRESHOLDS.GX_AGGRESSIVE then
    rideData.aggressiveEvents = rideData.aggressiveEvents + 1
    rideData.smoothnessScore = math.max(0, rideData.smoothnessScore - PENALTIES.GX_SMOOTHNESS)
    rideData.scenicExperience = math.max(0, rideData.scenicExperience - PENALTIES.GX_SCENIC)
  end

  -- Gentle driving bonus
  if totalG < THRESHOLDS.TOTAL_G_GENTLE then
    rideData.gentleRideTime = rideData.gentleRideTime + 1
    rideData.scenicExperience = math.min(THRESHOLDS.SCENIC_EXPERIENCE_MAX,
      rideData.scenicExperience + PENALTIES.GENTLE_SCENIC_BONUS)
  end
end

local function buildRideQuality(rideData)
  local isScenic = rideData.gentleRideTime > THRESHOLDS.GENTLE_RIDE_TIME
    and rideData.smoothnessScore > THRESHOLDS.SMOOTHNESS_SCORE_THRESHOLD

  return {
    smoothness = rideData.smoothnessScore / THRESHOLDS.SMOOTHNESS_SCORE_MAX,
    aggressiveEvents = rideData.aggressiveEvents,
    scenic = isScenic,
    experience = rideData.scenicExperience / THRESHOLDS.SCENIC_EXPERIENCE_MAX
  }
end

-- ================================
-- CALLBACK FUNCTIONS
-- ================================
local function calculateTipBreakdown(fare, elapsedTime, speedFactor, passengerType)
  local tipBreakdown = {}
  local baseFare = tonumber(fare.baseFare) or 0
  local actualSpeed = calcActualSpeed(fare, elapsedTime)
  local rq = getRideQuality(fare)
  local suggested = THRESHOLDS.SUGGESTED_SPEED
  local minSpeed = THRESHOLDS.MIN_SPEED

  -- Speed-based tips (tourists enjoy slower, scenic drives)
  if actualSpeed >= minSpeed then
    if actualSpeed <= suggested * 0.6 then
      local bonus = (suggested * 0.6 - actualSpeed) / (suggested * 0.6) * 0.5
      tipBreakdown["Scenic Bonus"] = math.min(bonus, TIP.SCENIC_BONUS_CAP) * baseFare

    elseif actualSpeed <= suggested * 0.8 then
      local bonus = (suggested * 0.8 - actualSpeed) / (suggested * 0.8) * 0.35
      tipBreakdown["Perfect Pace"] = math.min(bonus, TIP.PERFECT_PACE_CAP) * baseFare

    elseif actualSpeed <= suggested then
      local bonus = (suggested - actualSpeed) / suggested * 0.15
      tipBreakdown["Good Pace"] = math.min(bonus, TIP.GOOD_PACE_CAP) * baseFare
    end
  end

  -- Experience bonuses
  if rq then
    if rq.smoothness and rq.smoothness > THRESHOLDS.SMOOTHNESS_EXCELLENT then
      tipBreakdown["Comfortable Tour"] = rq.smoothness * TIP.COMFORTABLE_TOUR_MULT * baseFare
    elseif rq.smoothness and rq.smoothness > THRESHOLDS.SMOOTHNESS_GOOD then
      tipBreakdown["Smooth Experience"] = rq.smoothness * TIP.SMOOTH_EXPERIENCE_MULT * baseFare
    end

    if rq.scenic then
      tipBreakdown["Wonderful Tour"] = TIP.WONDERFUL_TOUR * baseFare
    end
  end

  return tipBreakdown
end

local function calculateDriverRating(fare, rideData, elapsedTime, speedFactor, passengerType)
  local rq = getRideQuality(fare) or {}
  local smooth = rq.smoothness or 1.0
  local spd = tonumber(speedFactor) or 0
  local rating = RATING.BASE

  rating = rating - (1 - smooth) * RATING.SMOOTHNESS_MULT

  if spd > 0 then
    rating = rating - math.min(1.0, spd) * RATING.SPEED_PENALTY_MULT
  end

  if rq.scenic then
    rating = rating + RATING.SCENIC_BONUS
  end

  return math.max(RATING.MIN, math.min(RATING.MAX, rating))
end

local function getDescription(fare, passengerType)
  local count = fare.passengers or 0
  local label = count == 1 and "passenger" or "passengers"
  return string.format("%s (%d %s) - Scenic route", passengerType.name, count, label)
end

local function getPaymentLabel(fare, speedFactor, passengerType)
  local elapsedTime = os.difftime(os.time(), fare.startTime or os.time())
  local actualSpeed = calcActualSpeed(fare, math.max(1, elapsedTime))
  local zone = getSpeedZone(actualSpeed)
  local rq = getRideQuality(fare)

  local label = zone.label

  if rq then
    if rq.scenic then
      label = label .. " | Wonderful Tour"
    elseif rq.aggressiveEvents and rq.aggressiveEvents > 3 then
      label = label .. " | Ruined Experience"
    elseif rq.smoothness and rq.smoothness < THRESHOLDS.SMOOTHNESS_GOOD then
      label = label .. " | Uncomfortable Ride"
    end
  end

  return label
end

local function onUpdate(fare, rideData, passengerType)
  initTouristData(rideData)
  processGForce(rideData)

  fare.rideQuality = buildRideQuality(rideData)
end

-- ================================
-- LIFECYCLE
-- ================================
local function onExtensionLoaded()
  if not gameplay_buberTaxi then
    log('W', logTag, 'gameplay_buberTaxi not loaded - passenger type not registered')
    return
  end

  gameplay_buberTaxi.registerPassengerType("TOURIST", {
    name = "Tourist",
    description = "Tourists who enjoy the journey and scenery",
    baseMultiplier = 0.85,
    speedWeight = -0.25,
    distanceWeight = 0.9,
    selectionWeight = 3,
    seatRange = {4, nil},
    valueRange = {0.6, nil},
    speedTolerance = 1.2,

    fareWeights = {
      {min = 0.5, max = 0.75, weight = 4},
      {min = 0.75, max = 1.05, weight = 5},
      {min = 1.05, max = 1.4, weight = 2}
    },

    calculateTipBreakdown = calculateTipBreakdown,
    onUpdate = onUpdate,
    calculateDriverRating = calculateDriverRating,
    getDescription = getDescription,
    getPaymentLabel = getPaymentLabel
  })

  log('I', logTag, 'Tourist passenger type registered')
end

-- ================================
-- MODULE EXPORTS
-- ================================
M.onExtensionLoaded = onExtensionLoaded
return M