local M = {}
local logTag = 'thrillPassenger'

-- ================================
-- CONSTANTS
-- ================================
local RATING = {
  BASE = 5.0,
  MIN = 1.0,
  MAX = 5.0,
  AVG_G_LOW_THRESHOLD = 0.4,
  MAX_G_LOW_THRESHOLD = 0.8,
  AVG_G_HIGH_THRESHOLD = 1.2,
  SPEED_SLOW_PENALTY = 0.6,
  SPEED_FAST_BONUS = 0.6,
  SPEED_THRESHOLD = 0.15,
  AVG_G_PENALTY_MULT = 2.0,
  MAX_G_PENALTY_MULT = 1.5,
  AVG_G_BONUS_MULT = 1.0
}

local TIP = {
  SPEED_RUSH_CAP = 0.5,
  ADRENALINE_CAP = 0.5,
  PEAK_THRILL_CAP = 0.4,
  ADRENALINE_THRESHOLD = 0.7,
  PEAK_THRESHOLD = 1.2
}

local GFORCE = {
  LOW_AVG_PENALTY = 0.4,
  LOW_MAX_PENALTY = 0.8
}

-- ================================
-- HELPER FUNCTIONS
-- ================================
local function getThrillData(fare)
  return fare.rideQuality and fare.rideQuality.thrillData
end

local function calcTotalGForce(sensorData)
  local gx = sensorData.gx or 0
  local gy = sensorData.gy or 0
  local gz = sensorData.gz or 0
  return math.sqrt(gx * gx + gy * gy + gz * gz)
end

local function initThrillData(rideData)
  if rideData.thrillData then return end
  rideData.thrillData = {
    avgG = 0,
    maxG = 0,
    currentG = 0,
    gForceSum = 0,
    gForceCount = 0
  }
end

-- ================================
-- CALLBACK FUNCTIONS
-- ================================
local function calculateTipBreakdown(fare, elapsedTime, speedFactor, passengerType)
  local tipBreakdown = {}
  local baseFare = tonumber(fare.baseFare) or 0
  local td = getThrillData(fare)

  -- Speed bonus
  if speedFactor > 0.05 then
    local rush = math.min(speedFactor * 0.5, TIP.SPEED_RUSH_CAP)
    tipBreakdown["Speed Rush"] = rush * baseFare
  end

  -- Adrenaline bonuses
  if td then
    if td.avgG and td.avgG > TIP.ADRENALINE_THRESHOLD then
      local adrenaline = math.min((td.avgG - TIP.ADRENALINE_THRESHOLD) * 0.8, TIP.ADRENALINE_CAP)
      tipBreakdown["Adrenaline Bonus"] = adrenaline * baseFare
    end
    if td.maxG and td.maxG > TIP.PEAK_THRESHOLD then
      local peak = math.min((td.maxG - TIP.PEAK_THRESHOLD) * 0.4, TIP.PEAK_THRILL_CAP)
      tipBreakdown["Peak Thrill"] = peak * baseFare
    end
  end

  return tipBreakdown
end

local function calculateDriverRating(fare, rideData, elapsedTime, speedFactor, passengerType)
  local td = getThrillData(fare) or {}
  local avgG = td.avgG or 0
  local maxG = td.maxG or 0
  local spd = tonumber(speedFactor) or 0
  local rating = RATING.BASE

  -- Penalize low G-forces
  if avgG < RATING.AVG_G_LOW_THRESHOLD then
    rating = rating - (RATING.AVG_G_LOW_THRESHOLD - avgG) * RATING.AVG_G_PENALTY_MULT
  end
  if maxG < RATING.MAX_G_LOW_THRESHOLD then
    rating = rating - (RATING.MAX_G_LOW_THRESHOLD - maxG) * RATING.MAX_G_PENALTY_MULT
  end

  -- Speed adjustments
  if spd <= 0 then
    rating = rating - math.min(1.0, -spd) * RATING.SPEED_SLOW_PENALTY
  elseif spd > RATING.SPEED_THRESHOLD then
    rating = rating + math.min(1.0, spd) * RATING.SPEED_FAST_BONUS
  end

  -- Penalize excessive G-forces
  if avgG > RATING.AVG_G_HIGH_THRESHOLD then
    rating = rating - (avgG - RATING.AVG_G_HIGH_THRESHOLD) * RATING.AVG_G_BONUS_MULT
  end

  return math.max(RATING.MIN, math.min(RATING.MAX, rating))
end

local function getDescription(fare, passengerType)
  local count = fare.passengers or 0
  local label = count == 1 and "passenger" or "passengers"
  return string.format("%s (%d %s) - Fast and wild", passengerType.name, count, label)
end

local function getPaymentLabel(fare, speedFactor, passengerType)
  local td = getThrillData(fare)
  local baseLabel = speedFactor > 0.1 and "Speed Rush" or "Too Slow"

  if td then
    if td.maxG and td.maxG > TIP.PEAK_THRESHOLD then
      return baseLabel .. " | Peak Thrill"
    elseif td.avgG and td.avgG > TIP.ADRENALINE_THRESHOLD then
      return baseLabel .. " | Adrenaline Bonus"
    end
  end

  return baseLabel
end

local function onUpdate(fare, rideData, passengerType)
  initThrillData(rideData)

  if not rideData.currentSensorData then return end

  local totalG = calcTotalGForce(rideData.currentSensorData)
  local td = rideData.thrillData

  -- Track G-force data with O(1) average calculation
  td.currentG = totalG
  td.maxG = math.max(td.maxG, totalG)
  td.gForceCount = td.gForceCount + 1
  td.gForceSum = td.gForceSum + totalG
  td.avgG = td.gForceSum / td.gForceCount

  -- Store reference in fare for tip calculation
  fare.rideQuality = fare.rideQuality or {}
  fare.rideQuality.thrillData = {
    avgG = td.avgG,
    maxG = td.maxG,
    currentG = td.currentG
  }
end

-- ================================
-- LIFECYCLE
-- ================================
local function onExtensionLoaded()
  if not gameplay_taxi then
    log('W', logTag, 'gameplay_taxi not loaded - passenger type not registered')
    return
  end

  gameplay_taxi.registerPassengerType("THRILL", {
    name = "Thrill Seeker",
    description = "Adrenaline junkies who love high G-forces and speed",
    baseMultiplier = 0.8,
    speedWeight = 2.0,
    distanceWeight = 1.0,
    selectionWeight = 2,
    seatRange = {nil, 5},
    valueRange = {0.0, 1.6},
    speedTolerance = 0.6,

    fareWeights = {
      {min = 0.9, max = 1.2, weight = 3},
      {min = 1.2, max = 1.6, weight = 5},
      {min = 1.6, max = 2.2, weight = 2}
    },

    calculateTipBreakdown = calculateTipBreakdown,
    onUpdate = onUpdate,
    calculateDriverRating = calculateDriverRating,
    getDescription = getDescription,
    getPaymentLabel = getPaymentLabel
  })

  log('I', logTag, 'Thrill Seeker passenger type registered')
end

-- ================================
-- MODULE EXPORTS
-- ================================
M.onExtensionLoaded = onExtensionLoaded
return M