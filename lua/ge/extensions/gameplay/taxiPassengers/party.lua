local M = {}
local logTag = 'partyPassenger'

-- ================================
-- CONSTANTS
-- ================================
local G_THRESHOLDS = {
  SMOOTH_RIDE = 0.28,
  GENTLE_DRIVING = 0.24,
  SUDDEN_MOVEMENT = 0.5,
  HIGH_AVG_G = 0.35,
  HIGH_MAX_G = 0.7,
  HIGH_SPEED = 0.15
}

-- ================================
-- HELPER FUNCTIONS
-- ================================
local function getPartyData(fare)
  return fare.rideQuality and fare.rideQuality.partyData
end

local function getGForceTotal(sensorData)
  return math.abs(sensorData.gx or 0) + math.abs(sensorData.gy or 0)
end

local function initPartyData(rideData)
  if rideData.partyData then return end
  rideData.partyData = {
    maxGForce = 0,
    avgGForce = 0,
    gForceReadings = 0,  -- count instead of storing all readings
    gForceSum = 0        -- running sum for O(1) average
  }
end

-- ================================
-- PARTY PASSENGER TYPE
-- ================================
local function calculateTipBreakdown(fare, elapsedTime, speedFactor, passengerType)
  local tipBreakdown = {}
  local baseFare = tonumber(fare.baseFare) or 0
  local pd = getPartyData(fare)

  if speedFactor < -0.08 then
    tipBreakdown["Safety Bonus"] = 0.25 * baseFare
  end

  if gameplay_taxi.rideData and gameplay_taxi.rideData.currentSensorData then
    local totalG = getGForceTotal(gameplay_taxi.rideData.currentSensorData)
    if totalG < G_THRESHOLDS.SMOOTH_RIDE then
      tipBreakdown["Smooth Ride"] = 0.18 * baseFare
    end
  end

  if pd then
    if pd.avgGForce and pd.avgGForce < G_THRESHOLDS.GENTLE_DRIVING then
      tipBreakdown["Gentle Driving"] = 0.12 * baseFare
    end
    if pd.maxGForce and pd.maxGForce < G_THRESHOLDS.SUDDEN_MOVEMENT then
      tipBreakdown["No Sudden Movements"] = 0.08 * baseFare
    end
  end

  return tipBreakdown
end

local function calculateDriverRating(fare, rideData, elapsedTime, speedFactor, passengerType)
  local pd = getPartyData(fare) or {}
  local avgG = pd.avgGForce or 0
  local maxG = pd.maxGForce or 0
  local spd = tonumber(speedFactor) or 0
  local rating = 5.0

  if avgG > G_THRESHOLDS.HIGH_AVG_G then
    rating = rating - (avgG - G_THRESHOLDS.HIGH_AVG_G) * 4.0
  end
  if maxG > G_THRESHOLDS.HIGH_MAX_G then
    rating = rating - (maxG - G_THRESHOLDS.HIGH_MAX_G) * 2.0
  end
  if spd > G_THRESHOLDS.HIGH_SPEED then
    rating = rating - math.min(1.0, spd) * 0.8
  end
  if avgG < 0.25 and spd <= 0 then
    rating = rating + 0.3
  end

  return math.max(1, math.min(5, rating))
end

local function getDescription(fare, passengerType)
  local count = fare.passengers or 0
  return string.format("Party Group (%d %s) - Drive safely!",
    count, count == 1 and "person" or "people")
end

local function getPaymentLabel(fare, speedFactor, passengerType)
  if speedFactor > 0.2 then
    return "Speed Penalty"
  elseif speedFactor < -0.1 then
    return "Safety Bonus"
  end
  return "Standard Rate"
end

local function onUpdate(fare, rideData, passengerType)
  initPartyData(rideData)

  if not rideData.currentSensorData then return end

  local totalG = getGForceTotal(rideData.currentSensorData)
  local pd = rideData.partyData

  -- Track max G-force
  pd.maxGForce = math.max(pd.maxGForce, totalG)

  -- Running average calculation (O(1) instead of O(n))
  pd.gForceReadings = pd.gForceReadings + 1
  pd.gForceSum = pd.gForceSum + totalG
  pd.avgGForce = pd.gForceSum / pd.gForceReadings

  -- Store reference in fare for tip calculation
  fare.rideQuality = fare.rideQuality or {}
  fare.rideQuality.partyData = pd
end

-- ================================
-- LIFECYCLE
-- ================================
local function onExtensionLoaded()
  -- gameplay_taxi is dynamically loaded - must check before use
  if not gameplay_taxi then
    log('W', logTag, 'gameplay_taxi not loaded - passenger type not registered')
    return
  end

  gameplay_taxi.registerPassengerType("PARTY", {
    name = "Party Group",
    description = "Large groups heading to parties who value safety and comfort over speed",
    baseMultiplier = 0.55,
    speedWeight = -0.4,
    distanceWeight = 1.15,
    selectionWeight = 3,
    seatRange = {12, nil},
    valueRange = {1.2, nil},
    speedTolerance = 0.35,

    fareWeights = {
      {min = 0.45, max = 0.65, weight = 4},
      {min = 0.65, max = 0.95, weight = 3},
      {min = 0.95, max = 1.25, weight = 2}
    },

    calculateTipBreakdown = calculateTipBreakdown,
    calculateDriverRating = calculateDriverRating,
    getDescription = getDescription,
    getPaymentLabel = getPaymentLabel,
    onUpdate = onUpdate
  })

  log('I', logTag, 'Party passenger type registered')
end

-- ================================
-- MODULE EXPORTS
-- ================================
M.onExtensionLoaded = onExtensionLoaded
return M