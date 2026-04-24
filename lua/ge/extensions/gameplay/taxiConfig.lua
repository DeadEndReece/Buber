--[[
  BUBER Configuration
  ===================
  All tunable constants for the BUBER taxi mod live here.
  Edit this file to customize gameplay without touching game logic.
]]

local M = {}

-- ============================================================================
-- BRAND
-- ============================================================================
M.brand = {
  name                = "BUBER",              -- Display name shown in UI and toasts
  ratingSaveDir       = "buber",              -- Subfolder inside career save for rating data
  ratingSaveFile      = "taxiRating.json",    -- Filename for persisted driver rating
}

-- ============================================================================
-- TIMING (seconds unless noted)
-- ============================================================================
M.timing = {
  jobOfferIntervalMin       = 5,      -- Minimum wait between fare offers
  jobOfferIntervalMax       = 45,     -- Maximum wait between fare offers
  jobOfferPrepareLeadTime   = 3,      -- Pre-generate fare this many seconds before offer
  jobAcceptTimeout          = 30,     -- Time to accept or reject before auto-reject
  completedFareDisplay      = 6,      -- How long the fare-complete screen stays visible
  updateInterval            = 1,      -- Main loop tick interval
  routeRestoreCooldown      = 2.0,    -- Cooldown between route-restore attempts
  returnToVehicleGrace      = 20,     -- Grace period to return to vehicle during dropoff
}

-- ============================================================================
-- TAXI ZONES (meters unless noted)
-- ============================================================================
M.zones = {
  stopRadius              = 5,        -- Arrival detection radius at pickup / dropoff
  stopHeight              = 2.5,      -- Visual cylinder height for taxi zones
  drawRadius              = 1,        -- Visual cylinder radius for taxi zones
  pickupSearchRadius      = 500,      -- How far to search for pickup spots
  minPickupDistance        = 60,       -- Minimum distance for a valid pickup from player
  pickupCacheRefreshDist  = 125,      -- Re-scan pickups after moving this far
  maxPickupSamples        = 8,        -- Max pickup candidates to try per offer
  maxDropoffSamples       = 24,       -- Max dropoff candidates to try per offer
}

-- ============================================================================
-- PASSENGER SERVICE
-- ============================================================================
M.service = {
  stopServiceSeconds      = 3,        -- Time passengers need to board / exit (non-bus)
  stopSpeedThreshold      = 0.75,     -- Max speed (m/s) to count as "stopped"
  busPassengerServiceRate  = 2,       -- Passengers processed per second on bus stops
}

-- ============================================================================
-- MULTI-STOP / BUS ROUTES
-- ============================================================================
M.multiStop = {
  vehicleSeatThreshold    = 18,       -- Min seats to qualify for bus-route fares
  emptyStopChance         = 0.35,     -- Probability a bus stop has zero drop-offs
  requiredRating          = 2.0,      -- Driver rating needed to unlock multi-stop
}

-- ============================================================================
-- SHARED RIDES
-- ============================================================================
M.sharedRide = {
  minSeats                = 4,        -- Min available seats to offer a shared ride
  offerChance             = 0.25,     -- Probability of shared ride vs direct fare
  minDropoffDistance      = 250,      -- Min distance between consecutive drop-offs
  maxDropoffs             = 3,        -- Max drop-off points in a shared ride
}

-- ============================================================================
-- BUS DISPLAY DEFAULTS (city bus electronic sign)
-- ============================================================================
M.busDisplay = {
  defaultRoute            = "[BUS]",
  defaultDirection        = "Not in Service",
  defaultColor            = "#FFA200",
}

-- ============================================================================
-- FARE CALCULATION
-- ============================================================================
M.fare = {
  distanceMultiplier      = 3,        -- Base distance scaling factor
  suggestedSpeed          = 18,       -- Reference speed (m/s) for speed-factor calc
  minDropoffDistance       = 600,      -- Min pickup-to-dropoff distance for direct fares
}

-- ============================================================================
-- DRIVER RATING
-- ============================================================================
M.rating = {
  sumPerLevel             = 25,       -- Rating points needed per whole level
  maxRating               = 5,        -- Hard ceiling for driver rating

  -- Abandonment penalties (applied per offence within a shift)
  abandonBasePenalty      = 0.10,     -- First offence rating penalty
  abandonScalePenalty     = 0.15,     -- Additional penalty per subsequent offence
  abandonMaxPenalty       = 1.0,      -- Hard cap on a single abandonment penalty

  -- Seat cap curve: maps driver rating → max usable passenger seats
  -- Use math.huge for "unlimited"
  seatCapCurve = {
    {rating = 0.0, value = 4},
    {rating = 0.2, value = 4},
    {rating = 0.4, value = 5},
    {rating = 0.6, value = 5},
    {rating = 0.8, value = 6},
    {rating = 1.0, value = 8},
    {rating = 1.5, value = 12},
    {rating = 2.0, value = 18},
    {rating = 2.5, value = 25},
    {rating = 3.0, value = 35},
    {rating = 3.5, value = 50},
    {rating = 4.0, value = 65},
    {rating = 4.5, value = 80},
    {rating = 5.0, value = math.huge},
  },

  -- Progression milestones shown in the UI
  milestones = {
    {rating = 0.0, label = "Start fares",       description = "Direct BUBER fares are available."},
    {rating = 0.2, label = "First cap bump",    description = "Early payout ceiling increases."},
    {rating = 0.4, label = "More seats",         description = "Small groups become easier to serve."},
    {rating = 0.6, label = "Steady work",        description = "Direct fare cap keeps climbing."},
    {rating = 0.8, label = "Larger calls",       description = "More passenger capacity opens up."},
    {rating = 1.0, label = "Trusted driver",     description = "Better direct fares and larger groups."},
    {rating = 1.5, label = "Growing demand",     description = "Bigger jobs start appearing more often."},
    {rating = 2.0, label = "Route driver",       description = "Multi-stop and bus routes unlock."},
    {rating = 2.5, label = "Route regular",      description = "Bus payouts and seat capacity increase."},
    {rating = 3.0, label = "High capacity",      description = "Large multi-stop work opens up."},
    {rating = 3.5, label = "City favourite",     description = "Higher route limits and more seats."},
    {rating = 4.0, label = "Elite service",      description = "Strong direct and route payouts."},
    {rating = 4.5, label = "Premium capacity",   description = "Most vehicle seats can be used."},
    {rating = 5.0, label = "BUBER legend",       description = "Full vehicle capacity unlocked."},
  },
}

-- ============================================================================
-- VEHICLE CLASS PAY TIERS
-- Each tier: performance index range → pay multiplier range
-- ============================================================================
M.vehicle = {
  classTiers = {
    D = {description = "Economy/Utility",   minPI = 0,   maxPI = 20,  minMultiplier = 0.70, maxMultiplier = 0.90},
    C = {description = "Standard",          minPI = 21,  maxPI = 40,  minMultiplier = 0.95, maxMultiplier = 1.10},
    B = {description = "Sports",            minPI = 41,  maxPI = 65,  minMultiplier = 1.15, maxMultiplier = 1.30},
    A = {description = "High Performance",  minPI = 66,  maxPI = 85,  minMultiplier = 1.35, maxMultiplier = 1.55},
    S = {description = "Super Sports",      minPI = 86,  maxPI = 100, minMultiplier = 1.65, maxMultiplier = 1.90},
    X = {description = "Modified",          minPI = 101, maxPI = 120, minMultiplier = 2.00, maxMultiplier = 2.20},
  },

  -- Seat pack capacity rules: pattern → total seat count
  -- Checked against vehicle part names to determine seating
  seatPackRules = {
    {pattern = "citybus_seats",       total = 44},
    {pattern = "schoolbus_seats_r_c", total = 10},
    {pattern = "schoolbus_seats_l_c", total = 10},
    {pattern = "limo_seat",           total = 8},
  },

  -- Capsule-style seat packs (only matched when part name contains "capsule" AND "seats")
  capsuleSeatPacks = {
    {pattern = "lhd_artic_seats_upper", total = 77},
    {pattern = "rhd_artic_seats_upper", total = 77},
    {pattern = "lhd_artic_seats",       total = 30},
    {pattern = "rhd_artic_seats",       total = 30},
    {pattern = "lhd_seats_upper",       total = 53},
    {pattern = "lh_seats_upper",        total = 53},
    {pattern = "lhd_seats",             total = 17},
    {pattern = "lh_seats",              total = 17},
    {pattern = "sd12m",                 total = 25},
    {pattern = "sd18m",                 total = 41},
    {pattern = "sd105",                 total = 21},
    {pattern = "sd_seats",              total = 33},
    {pattern = "dd105",                 total = 29},
    {pattern = "sd195",                 total = 43},
  },
}

-- ============================================================================
-- PAYOUT LIMITS
-- Soft caps, overflow rates, and rating-gated hard caps for fare earnings
-- ============================================================================
M.payout = {
  -- Direct fare profile (point-to-point rides)
  direct = {
    softCap                 = 6500,
    softCapOverflowRate     = 0.30,     -- % of excess above soft cap that is kept
    multiplierStackCap      = 4.5,      -- Max combined multiplier stack

    -- Tip limits per driver level (0–5)
    tipSoftCapOverflowRate  = 0.25,
    tipSoftCaps             = {[0] = 80, [1] = 150, [2] = 275, [3] = 450, [4] = 700, [5] = 1000},
    tipBasePercentCaps      = {[0] = 0.20, [1] = 0.25, [2] = 0.30, [3] = 0.35, [4] = 0.45, [5] = 0.50},

    -- Rating-gated hard cap: max possible payout at each rating level
    ratingHardCapCurve = {
      {rating = 0.0, value = 300},
      {rating = 0.2, value = 500},
      {rating = 0.4, value = 700},
      {rating = 0.6, value = 900},
      {rating = 0.8, value = 1100},
      {rating = 1.0, value = 1300},
      {rating = 1.5, value = 1800},
      {rating = 2.0, value = 2500},
      {rating = 2.5, value = 3300},
      {rating = 3.0, value = 4200},
      {rating = 3.5, value = 5200},
      {rating = 4.0, value = 6500},
      {rating = 4.5, value = 7600},
      {rating = 5.0, value = 8500},
    },
  },

  -- Multi-stop / bus route profile
  multistop = {
    softCap                 = 12000,
    softCapOverflowRate     = 0.25,
    multiplierStackCap      = 3.0,

    -- Diminishing returns for high passenger counts / long distances
    fullPassengerCount      = 16,       -- Passengers above this earn at reduced rate
    extraPassengerRate      = 0.35,     -- Rate for passengers above fullPassengerCount
    fullDistanceMeters      = 12000,    -- Distance above this earns at reduced rate
    extraDistanceRate       = 0.45,     -- Rate for distance above fullDistanceMeters

    -- Tip limits per driver level (0–5)
    tipSoftCapOverflowRate  = 0.18,
    tipSoftCaps             = {[0] = 120, [1] = 225, [2] = 400, [3] = 650, [4] = 950, [5] = 1300},
    tipBasePercentCaps      = {[0] = 0.12, [1] = 0.15, [2] = 0.18, [3] = 0.22, [4] = 0.27, [5] = 0.32},

    -- Rating-gated hard cap
    ratingHardCapCurve = {
      {rating = 0.0, value = 500},
      {rating = 0.2, value = 800},
      {rating = 0.4, value = 1100},
      {rating = 0.6, value = 1400},
      {rating = 0.8, value = 1700},
      {rating = 1.0, value = 2200},
      {rating = 1.5, value = 3200},
      {rating = 2.0, value = 4500},
      {rating = 2.5, value = 6000},
      {rating = 3.0, value = 8000},
      {rating = 3.5, value = 10000},
      {rating = 4.0, value = 12500},
      {rating = 4.5, value = 14500},
      {rating = 5.0, value = 16500},
    },
  },
}

-- ============================================================================
-- VISUAL — Zone marker colors {r, g, b, a}
-- ============================================================================
M.visual = {
  zoneColors = {
    pickup = {
      active   = {1, 0.82, 0.2, 0.85},
      inactive = {1, 0.82, 0.2, 0.35},
    },
    dropoff = {
      active   = {0.22, 0.86, 0.45, 0.85},
      inactive = {0.22, 0.86, 0.45, 0.35},
    },
  },
  debugSpotColors = {
    all      = {0.18, 0.9, 0.35, 0.45},
    pickup   = {1, 0.82, 0.2, 0.75},
    bus      = {0.2, 0.55, 1, 0.75},
    reserved = {1, 0.1, 0.1, 0.9},
  },
}

-- ============================================================================
-- PASSENGER MODULES
-- ============================================================================
M.passengerModules = {
  path = "/lua/ge/extensions/gameplay/taxiPassengers/",
}

-- ============================================================================
-- DEFAULT PASSENGER TYPE (Standard)
-- Numeric tuning values — callback functions remain in taxi.lua
-- ============================================================================
M.defaultPassenger = {
  name              = "Standard",
  description       = "Regular passengers who value speed and efficiency",
  baseMultiplier    = 1.0,
  speedWeight       = 1.0,
  distanceWeight    = 1.0,
  selectionWeight   = 5,
  seatRange         = {nil, 10},
  valueRange        = {nil, nil},
  speedTolerance    = 0.5,
  roughGThreshold   = 0.6,       -- G-force peak above which a "rough event" is counted
  fareWeights = {
    {min = 0.5, max = 0.8, weight = 3},
    {min = 0.8, max = 1.2, weight = 5},
    {min = 1.2, max = 1.5, weight = 2},
  },
}

return M
