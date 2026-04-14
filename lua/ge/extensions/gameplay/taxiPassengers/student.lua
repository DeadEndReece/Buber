local M = {}
local logTag = 'studentPassenger'

-- ================================
-- CONSTANTS
-- ================================
local RATING = {
  BASE = 5.0,
  MIN = 1.0,
  MAX = 5.0,
  POSITIVE_SPEED_BONUS = 0.8,
  NEGATIVE_SPEED_PENALTY = 1.2,
  ON_TIME_BONUS = 0.1,
  MAX_POSITIVE_BOOST = 0.6,
  MAX_NEGATIVE_PENALTY = 1.0
}

-- ================================
-- CALLBACK FUNCTIONS
-- ================================
local function calculateTipBreakdown(fare, elapsedTime, speedFactor, passengerType)
  local tipBreakdown = {}
  local baseFare = tonumber(fare.baseFare) or 0

  if speedFactor > 0.05 then
    local efficiency = math.min(speedFactor * 0.25, 0.25)
    tipBreakdown["Efficient Trip"] = efficiency * baseFare
  end

  return tipBreakdown
end

local function calculateDriverRating(fare, rideData, elapsedTime, speedFactor, passengerType)
  local spd = tonumber(speedFactor) or 0
  local rating = RATING.BASE

  if spd < 0 then
    rating = rating - math.min(RATING.MAX_NEGATIVE_PENALTY, -spd) * RATING.NEGATIVE_SPEED_PENALTY
  elseif spd > 0 then
    rating = rating + math.min(RATING.MAX_POSITIVE_BOOST, spd) * RATING.POSITIVE_SPEED_BONUS
  end

  if elapsedTime and elapsedTime > 0 and spd >= 0 then
    rating = rating + RATING.ON_TIME_BONUS
  end

  return math.max(RATING.MIN, math.min(RATING.MAX, rating))
end

local function getDescription(fare, passengerType)
  local count = fare.passengers or 0
  local label = count == 1 and "passenger" or "passengers"
  return string.format("%s (%d %s) - Budget trip", passengerType.name, count, label)
end

local function getPaymentLabel(fare, speedFactor, passengerType)
  return speedFactor > 0 and "Efficient Trip" or "Standard"
end

local function onUpdate(fare, rideData, passengerType)
  -- minimal tracking - nothing needed
end

-- ================================
-- LIFECYCLE
-- ================================
local function onExtensionLoaded()
  if not gameplay_taxi then
    log('W', logTag, 'gameplay_taxi not loaded - passenger type not registered')
    return
  end

  gameplay_taxi.registerPassengerType("STUDENT", {
    name = "Student",
    description = "Budget riders; flexible but reward efficiency",
    baseMultiplier = 0.5,
    speedWeight = 0.8,
    distanceWeight = 1.0,
    selectionWeight = 4,
    seatRange = {1, 5},
    valueRange = {0.0, 1.2},
    speedTolerance = 0.5,

    fareWeights = {
      {min = 0.7, max = 1.0, weight = 6},
      {min = 1.0, max = 1.3, weight = 3},
      {min = 1.3, max = 1.6, weight = 1}
    },

    calculateTipBreakdown = calculateTipBreakdown,
    calculateDriverRating = calculateDriverRating,
    getDescription = getDescription,
    getPaymentLabel = getPaymentLabel,
    onUpdate = onUpdate
  })

  log('I', logTag, 'Student passenger type registered')
end

-- ================================
-- MODULE EXPORTS
-- ================================
M.onExtensionLoaded = onExtensionLoaded
return M