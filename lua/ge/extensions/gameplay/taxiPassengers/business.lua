local M = {}

-- Passenger type configuration constants
local PASSENGER_CONFIG = {
    baseMultiplier = 0.75,
    speedWeight = 1.3,
    distanceWeight = 1.0,
    selectionWeight = 3,
    seatRange = { nil, 10 },
    valueRange = { 0.5, 2.2 },
    speedTolerance = 0.25
}

-- Speed factor thresholds
local SPEED = {
    SLOW_THRESHOLD = -0.05,
    FAST_THRESHOLD = 0.05,
    VERY_FAST_THRESHOLD = 0.08,
    VERY_SLOW_THRESHOLD = -0.08,
    ASSERTIVE_THRESHOLD = 0.15,
    UNACCEPTABLE_THRESHOLD = -0.2
}

-- G-force thresholds
local GFORCE = {
    ACCEL_BRAKE_HIGH = 0.85,
    ACCEL_BRAKE_LOW = -0.75,
    LATERAL_HIGH = 0.95,
    ASSERTIVE_MIN = 0.6,
    ASSERTIVE_MAX = 1.2
}

-- Rating adjustments
local RATING = {
    MIN = 1,
    MAX = 5,
    SLOW_PENALTY = 1.5,
    FAST_BONUS = 0.8,
    ASSERTIVE_BONUS = 0.3,
    AGGRESSIVE_PENALTY = 1.0,
    AGGRESSIVE_EVENTS_THRESHOLD = 8,
    RECKLESS_EVENTS_THRESHOLD = 10
}

-- Efficiency penalties
local EFFICIENCY = {
    AGGRESSIVE_PENALTY = 2,
    EFFICIENCY_DIVISOR = 100
}

local function clamp(value, min, max)
    return math.max(min, math.min(max, value))
end

local function calculateTipBreakdown(fare, speedFactor, passengerType)
    local tipBreakdown = {}
    local baseFare = tonumber(fare.baseFare) or 0

    if speedFactor > SPEED.FAST_THRESHOLD then
        local bonus = speedFactor * baseFare * passengerType.speedWeight * 0.45
        tipBreakdown["Efficiency Bonus"] = math.min(bonus, baseFare * 0.45)
    end

    local rq = fare.rideQuality
    if rq and speedFactor > SPEED.ASSERTIVE_THRESHOLD and rq.assertive then
        tipBreakdown["Assertive Driving"] = 0.12 * baseFare
    end

    return tipBreakdown
end

local function calculateDriverRating(fare, speedFactor, passengerType)
    local rq = fare.rideQuality or {}
    local spd = tonumber(speedFactor) or 0
    local rating = RATING.MAX

    if spd < SPEED.SLOW_THRESHOLD then
        rating = rating - math.min(1.0, -spd) * RATING.SLOW_PENALTY
    elseif spd > SPEED.FAST_THRESHOLD then
        rating = rating + math.min(1.0, spd) * RATING.FAST_BONUS
    end

    if rq.assertive and spd > SPEED.ASSERTIVE_THRESHOLD then
        rating = rating + RATING.ASSERTIVE_BONUS
    end
    if rq.aggressiveEvents and rq.aggressiveEvents > RATING.AGGRESSIVE_EVENTS_THRESHOLD then
        rating = rating - RATING.AGGRESSIVE_PENALTY
    end

    return clamp(rating, RATING.MIN, RATING.MAX)
end

local function updateRideData(fare, rideData)
    if not rideData.aggressiveEvents then
        rideData.aggressiveEvents = 0
        rideData.assertiveDriving = false
        rideData.efficiencyScore = 100
    end

    local sensor = rideData.currentSensorData
    if not sensor then return end

    local gx, gy = sensor.gx, sensor.gy
    local totalGForce = math.sqrt(gx * gx + gy * gy)

    -- Check for aggressive events
    local isAggressive = false

    if gy > GFORCE.ACCEL_BRAKE_HIGH or gy < GFORCE.ACCEL_BRAKE_LOW then
        rideData.aggressiveEvents = rideData.aggressiveEvents + 1
        rideData.efficiencyScore = math.max(0, rideData.efficiencyScore - EFFICIENCY.AGGRESSIVE_PENALTY)
        isAggressive = true
    end

    if math.abs(gx) > GFORCE.LATERAL_HIGH then
        rideData.aggressiveEvents = rideData.aggressiveEvents + 1
        rideData.efficiencyScore = math.max(0, rideData.efficiencyScore - EFFICIENCY.AGGRESSIVE_PENALTY)
        isAggressive = true
    end

    -- Check for assertive (smooth) driving
    if totalGForce >= GFORCE.ASSERTIVE_MIN and totalGForce <= GFORCE.ASSERTIVE_MAX then
        rideData.assertiveDriving = true
    elseif isAggressive and gy < -GFORCE.ACCEL_BRAKE_LOW then
        rideData.assertiveDriving = true
    end

    fare.rideQuality = {
        aggressiveEvents = rideData.aggressiveEvents,
        assertive = rideData.assertiveDriving,
        efficiency = rideData.efficiencyScore / EFFICIENCY.EFFICIENCY_DIVISOR
    }
end

local function getPaymentLabel(fare, speedFactor, passengerType)
    local rq = fare.rideQuality
    local events = rq and rq.aggressiveEvents or 0

    -- Determine base label
    local label
    if speedFactor < SPEED.VERY_SLOW_THRESHOLD then
        label = "Lateness Penalty"
    elseif speedFactor > SPEED.VERY_FAST_THRESHOLD then
        label = "Efficiency Bonus"
    else
        label = "On Time"
    end

    -- Append modifiers
    if rq then
        if speedFactor > SPEED.ASSERTIVE_THRESHOLD and rq.assertive then
            label = label .. " | Assertive Driving"
        elseif speedFactor < -0.2 then
            label = label .. " | Unacceptable Delays"
        elseif events > RATING.RECKLESS_EVENTS_THRESHOLD then
            label = label .. " | Reckless Driving"
        end
    end

    return label
end

local function onExtensionLoaded()
    gameplay_taxi.registerPassengerType("BUSINESS", {
        name = "Business",
        description = "Time-conscious passengers with strict schedules",
        baseMultiplier = PASSENGER_CONFIG.baseMultiplier,
        speedWeight = PASSENGER_CONFIG.speedWeight,
        distanceWeight = PASSENGER_CONFIG.distanceWeight,
        selectionWeight = PASSENGER_CONFIG.selectionWeight,
        seatRange = PASSENGER_CONFIG.seatRange,
        valueRange = PASSENGER_CONFIG.valueRange,
        fareWeights = {
            { min = 0.9, max = 1.2, weight = 3 },
            { min = 1.2, max = 1.6, weight = 6 },
            { min = 1.6, max = 2.1, weight = 3 }
        },
        speedTolerance = PASSENGER_CONFIG.speedTolerance,
        calculateTipBreakdown = function(fare, _, speedFactor, passengerType)
            return calculateTipBreakdown(fare, speedFactor, passengerType)
        end,
        calculateDriverRating = function(fare, _, _, speedFactor, passengerType)
            return calculateDriverRating(fare, speedFactor, passengerType)
        end,
        onUpdate = function(fare, rideData, passengerType)
            updateRideData(fare, rideData)
        end,
        getDescription = function(fare, passengerType)
            return string.format("%s (%d passengers) - Time critical", passengerType.name, fare.passengers)
        end,
        getPaymentLabel = function(fare, speedFactor, passengerType)
            return getPaymentLabel(fare, speedFactor, passengerType)
        end
    })
end

M.onExtensionLoaded = onExtensionLoaded

return M
