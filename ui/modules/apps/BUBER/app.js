var app = angular.module('beamng.apps')

// =============================================================================
// Constants
// =============================================================================

var STATES = {
  START: 'start',
  READY: 'ready',
  ACCEPT: 'accept',
  PICKUP: 'pickup',
  DROPOFF: 'dropoff',
  COMPLETE: 'complete'
}

var ON_DUTY_STATES = [STATES.READY, STATES.ACCEPT, STATES.PICKUP, STATES.DROPOFF]

var LIVE_STATES = [STATES.PICKUP, STATES.DROPOFF]

var BUBER_UI_DEFAULT_SETTINGS = {
  mainOpacity: 1,
  mainScale: 1,
  popupOpacity: 1,
  popupScale: 1,
  popupPosition: 'bottom-center',
  meterEnabled: true,
  meterOpacity: 1,
  meterScale: 1,
  meterPosition: 'bottom-center'
}

var BUBER_UI_STORAGE_KEY = 'buberUiSettings'

var BUBER_UI_POSITIONS = [
  { value: 'bottom-center', label: 'Bottom center' },
  { value: 'bottom-left', label: 'Bottom left' },
  { value: 'bottom-right', label: 'Bottom right' },
  { value: 'top-center', label: 'Top center' },
  { value: 'top-right', label: 'Top right' }
]

var BUBER_UI_POSITION_LOOKUP = {}
BUBER_UI_POSITIONS.forEach(function (option) {
  BUBER_UI_POSITION_LOOKUP[option.value] = true
})

// Lookup tables for display text
var STATUS_TITLES = {
  start: 'Off duty',
  ready: 'Waiting for dispatch',
  accept: 'New fare available',
  pickup: 'Drive to pickup',
  dropoff: 'Passenger onboard',
  complete: { default: 'Fare completed', abandoned: 'Passenger abandoned' }
}

var STATUS_SUBTITLES = {
  start: (fare) => fare.passengerDescription || '',
  accept: () => 'Review the fare and decide whether to take the call.',
  pickup: () => 'Follow the route to collect your passengers.',
  dropoff: () => 'Deliver your passengers smoothly for the best payout.',
  complete: (fare, isPenalty) => isPenalty
    ? 'Abandoning a live dropoff reduced your driver rating.'
    : 'Your latest fare has been processed.',
  ready: () => ''
}

var DISPATCH_HINTS = {
  start: () => 'Tap the duty toggle to start taking fares.',
  ready: (state) => state.hasSuccessfulCompletedFare()
    ? 'Waiting for the next passenger.'
    : 'Dispatch is live.',
  accept: () => 'New fare ready for review.',
  pickup: () => 'Meter live. Head to the pickup point.',
  dropoff: () => 'Passenger onboard. Finish the route cleanly.',
  complete: (fare, isPenalty) => isPenalty
    ? 'Repeat offences heavily affect your driver score.'
    : 'Fare complete. Showing earnings.'
}

// =============================================================================
// Helpers
// =============================================================================

function buberDefaultState() {
  return {
    state: STATES.START,
    currentFare: null,
    lastCompletedFare: null,
    resultNextState: null,
    availableSeats: 0,
    vehicleOpenSeats: 0,
    seatCap: 0,
    vehicleMultiplier: 1.0,
    vehicleClassName: 'C',
    vehicleClassDescription: 'Standard',
    vehiclePerformanceIndex: null,
    vehicleClassMultiplier: 1.0,
    cumulativeReward: 0,
    fareStreak: 0,
    currentPassengerType: null,
    playerRating: 0,
    multiStopRequiredRating: 2.0,
    multiStopUnlocked: false,
    progression: buberDefaultProgression(),
    lastPassengerRating: null,
    returnToVehicleActive: false,
    returnToVehicleSeconds: null,
    taxiDisabled: false,
    disabledReason: ''
  }
}

function buberDefaultProgression() {
  return {
    rating: 0,
    maxRating: 5,
    directCap: 300,
    multiStopCap: 500,
    multiStopRequiredRating: 2.0,
    multiStopUnlocked: false,
    seatCap: 4,
    seatCapUnlimited: false,
    vehicleOpenSeats: 0,
    availableSeats: 0,
    nextUnlock: null,
    milestones: []
  }
}

function buberParsePayload(data, fallback) {
  if (typeof data === 'string') {
    try {
      return JSON.parse(data)
    } catch {
      return fallback || {}
    }
  }
  return data ? angular.copy(data) : (fallback || {})
}

function buberFormatMoney(value) {
  var amount = Number(value) || 0
  return '$' + amount.toLocaleString(undefined, {
    minimumFractionDigits: amount % 1 === 0 ? 0 : 2,
    maximumFractionDigits: 2
  })
}

function buberFormatDistanceMeters(value, decimalPlaces) {
  var meters = Number(value)
  if (!Number.isFinite(meters)) return '--'

  if (window.UiUnits && typeof UiUnits.buildString === 'function') {
    return UiUnits.buildString('distance', Math.max(0, meters), decimalPlaces)
  }

  return (Math.max(0, meters) / 1000).toFixed(decimalPlaces) + ' km'
}

function buberClampNumber(value, minValue, maxValue, fallback) {
  var amount = Number(value)
  if (!Number.isFinite(amount)) return fallback
  return Math.max(minValue, Math.min(maxValue, amount))
}

function buberNormalizePosition(value, fallback) {
  value = String(value || '')
  return BUBER_UI_POSITION_LOOKUP[value] ? value : fallback
}

function buberNormalizeBoolean(value, fallback) {
  if (value === true || value === 'true' || value === 1 || value === '1') return true
  if (value === false || value === 'false' || value === 0 || value === '0') return false
  return fallback
}

function buberNormalizeUiSettings(data) {
  var incoming = data || {}
  var settings = angular.extend({}, BUBER_UI_DEFAULT_SETTINGS, incoming)

  settings.mainOpacity = buberClampNumber(settings.mainOpacity, 0.35, 1, BUBER_UI_DEFAULT_SETTINGS.mainOpacity)
  settings.mainScale = buberClampNumber(settings.mainScale, 0.75, 1, BUBER_UI_DEFAULT_SETTINGS.mainScale)
  settings.popupOpacity = buberClampNumber(settings.popupOpacity, 0.35, 1, BUBER_UI_DEFAULT_SETTINGS.popupOpacity)
  settings.popupScale = buberClampNumber(settings.popupScale, 0.75, 1, BUBER_UI_DEFAULT_SETTINGS.popupScale)
  settings.popupPosition = buberNormalizePosition(settings.popupPosition, BUBER_UI_DEFAULT_SETTINGS.popupPosition)
  settings.meterEnabled = buberNormalizeBoolean(settings.meterEnabled, BUBER_UI_DEFAULT_SETTINGS.meterEnabled)
  settings.meterOpacity = buberClampNumber(settings.meterOpacity, 0.35, 1, BUBER_UI_DEFAULT_SETTINGS.meterOpacity)
  settings.meterScale = buberClampNumber(settings.meterScale, 0.75, 1, BUBER_UI_DEFAULT_SETTINGS.meterScale)
  settings.meterPosition = buberNormalizePosition(settings.meterPosition, BUBER_UI_DEFAULT_SETTINGS.meterPosition)

  return settings
}

function buberUiActionValue(value) {
  if (typeof value === 'boolean') return value ? 'true' : 'false'
  return String(value)
}

function buberReadStoredUiSettings() {
  try {
    if (!window.localStorage) return null
    var raw = window.localStorage.getItem(BUBER_UI_STORAGE_KEY)
    return raw ? JSON.parse(raw) : null
  } catch (e) {
    return null
  }
}

function buberWriteStoredUiSettings(settings) {
  try {
    if (!window.localStorage) return
    window.localStorage.setItem(BUBER_UI_STORAGE_KEY, JSON.stringify(buberNormalizeUiSettings(settings)))
  } catch (e) {}
}

// =============================================================================
// Directive & Controller
// =============================================================================

app.directive('buberapp', [function () {
  return {
    templateUrl: '/ui/modules/apps/BUBER/app.html',
    replace: true,
    restrict: 'EA',
    scope: true
  }
}])

app.controller('BuberController', ['$scope', '$sce', '$timeout', '$interval', '$element', function ($scope, $sce, $timeout, $interval, $element) {
  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  var sendLua, sendUiAction, sendTaxiAction, requestTaxiState
  var pendingSettingSaves = {}

  sendLua = function (command) {
    bngApi.engineLua(command)
  }

  sendUiAction = function (action) {
    sendLua('extensions.buber_ui.handleUiAction(' + JSON.stringify(action) + ')')
  }

  sendTaxiAction = function (method) {
    sendUiAction(method)
    requestTaxiState()
  }

  requestTaxiState = function () {
    sendLua(
      'local ext = extensions.buber_ui or extensions.gameplay_buberTaxi or gameplay_buberTaxi; ' +
      'if ext and ext.requestUiState then ext.requestUiState(true) end'
    )
  }

  function queueUiSettingSave(key, value) {
    if (pendingSettingSaves[key]) {
      $timeout.cancel(pendingSettingSaves[key])
    }

    pendingSettingSaves[key] = $timeout(function () {
      delete pendingSettingSaves[key]
      sendUiAction('setUiSetting:' + key + ':' + buberUiActionValue(value))
    }, 140)
  }

  function cancelPendingSettingSaves() {
    Object.keys(pendingSettingSaves).forEach(function (key) {
      $timeout.cancel(pendingSettingSaves[key])
      delete pendingSettingSaves[key]
    })
  }

  function getRootElement() {
    return ($element && $element[0]) || document.querySelector('.buber-root')
  }

  function updateTabSize() {
    var root = getRootElement()
    var button = root ? root.querySelector('#taxi-show-button') : null
    if (!root || !button) return

    var isVerticalDock = root.classList.contains('is-left-anchored') || root.classList.contains('is-right-anchored')
    button.style.width = isVerticalDock ? '28px' : '75px'
    button.style.height = isVerticalDock ? '75px' : '28px'
  }

  function setDockSide(side) {
    var root = getRootElement()
    if (!root) return

    root.classList.toggle('is-left-anchored', side === 'left')
    root.classList.toggle('is-right-anchored', side === 'right')
    root.classList.toggle('is-top-anchored', side === 'top')
    root.classList.toggle('is-bottom-anchored', side === 'bottom')
  }

  function updateDockOrientation() {
    var root = getRootElement()
    if (!root || !window.innerWidth || !window.innerHeight) return

    var rect = root.getBoundingClientRect()
    var distances = [
      { side: 'left', distance: rect.left },
      { side: 'right', distance: window.innerWidth - rect.right },
      { side: 'top', distance: rect.top },
      { side: 'bottom', distance: window.innerHeight - rect.bottom }
    ]

    distances.sort(function (left, right) {
      return left.distance - right.distance
    })

    setDockSide(distances[0].side)
    updateTabSize()
  }

  function getFare() {
    return $scope.taxi.currentFare || {}
  }

  function isMultiStop(fare) {
    fare = fare || getFare()
    return fare.routeMode === 'multistop'
  }

  function isSharedRide(fare) {
    fare = fare || getFare()
    return isMultiStop(fare) && fare.routeType === 'shared'
  }

  function isPenaltyResult() {
    var lastFare = $scope.taxi.lastCompletedFare
    return lastFare && lastFare.resultType === 'abandoned'
  }

  function hasSuccessfulCompletedFare() {
    return !!$scope.taxi.lastCompletedFare && !isPenaltyResult()
  }

  function isOnDuty() {
    if ($scope.taxi.taxiDisabled) return false
    if ($scope.taxi.state === STATES.COMPLETE) {
      return $scope.taxi.resultNextState !== STATES.START
    }
    return ON_DUTY_STATES.indexOf($scope.taxi.state) !== -1
  }

  function isLiveFare() {
    return LIVE_STATES.indexOf($scope.taxi.state) !== -1 && !!$scope.taxi.currentFare
  }

  function isReturnToVehicleActive() {
    return !!$scope.taxi.returnToVehicleActive && !!$scope.taxi.currentFare
  }

  function getReturnToVehicleSeconds() {
    var seconds = Number($scope.taxi.returnToVehicleSeconds)
    return Number.isFinite(seconds) ? Math.max(0, Math.ceil(seconds)) : 0
  }

  function getOfferKey(fare) {
    if (!fare) return ''
    return [
      fare.offerExpiresAt || '',
      fare.routeMode || '',
      fare.routeLabel || '',
      fare.passengerType || fare.passengerTypeName || '',
      fare.passengers || '',
      fare.initialBaseFare || fare.baseFare || ''
    ].join('|')
  }

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  $scope.ui = {
    open: false,
    activePage: 'dashboard',
    selectedMilestoneRating: null,
    activeOfferKey: '',
    offerPopupDismissedKey: '',
    settings: buberNormalizeUiSettings(buberReadStoredUiSettings()),
    settingsOpen: false
  }
  $scope.taxi = buberDefaultState()
  $scope.uiPositionOptions = BUBER_UI_POSITIONS
  var dockTimer = $interval(updateDockOrientation, 250)
  $timeout(updateDockOrientation, 0)

  // ---------------------------------------------------------------------------
  // Events
  // ---------------------------------------------------------------------------

  $scope.$on('buberUiState', function (event, data) {
    var parsed = buberParsePayload(data, { ui: { open: false } })
    var ui = parsed.ui || {}
    $scope.ui.open = !!ui.open
    $scope.ui.settings = buberNormalizeUiSettings(ui.settings || $scope.ui.settings)
    buberWriteStoredUiSettings($scope.ui.settings)
    $scope.$evalAsync()
    $timeout(updateDockOrientation, 0)
  })

  $scope.$on('buberHotkey', function () {
    $scope.ui.open = !$scope.ui.open
    sendUiAction('toggleOpen')
    requestTaxiState()
    updateDockOrientation()
    $scope.$evalAsync()
  })

  $scope.$on('buberState', function (event, data) {
    $scope.taxi = angular.extend(buberDefaultState(), buberParsePayload(data))
    var offerKey = getOfferKey($scope.taxi.currentFare)

    if ($scope.taxi.state !== STATES.ACCEPT || !offerKey) {
      $scope.ui.activeOfferKey = ''
      $scope.ui.offerPopupDismissedKey = ''
    } else if ($scope.ui.activeOfferKey !== offerKey) {
      $scope.ui.activeOfferKey = offerKey
      $scope.ui.offerPopupDismissedKey = ''
    }

    $scope.$evalAsync()
  })

  $scope.$on('SettingsChanged', function () {
    updateDockOrientation()
    $scope.$evalAsync()
  })

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  $scope.init = function () {
    sendLua('settings.notifyUI()')
    requestTaxiState()
    updateDockOrientation()
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  $scope.toggleOpen = function () {
    $scope.ui.open = !$scope.ui.open
    updateDockOrientation()
    sendUiAction('toggleOpen')
    requestTaxiState()
  }

  $scope.close = function () {
    $scope.ui.open = false
    updateDockOrientation()
    sendUiAction('close')
  }

  $scope.goAvailable = function () {
    sendTaxiAction('setAvailable')
  }

  $scope.stopTaxiJob = function () {
    sendTaxiAction('stopTaxiJob')
  }

  $scope.toggleDuty = function () {
    if (isOnDuty()) {
      $scope.stopTaxiJob()
    } else if ($scope.canGoAvailable()) {
      $scope.goAvailable()
    }
  }

  $scope.acceptJob = function () {
    $scope.dismissOfferPopup()
    sendTaxiAction('acceptJob')
  }

  $scope.rejectJob = function () {
    $scope.dismissOfferPopup()
    sendTaxiAction('rejectJob')
  }

  $scope.abandonJob = function () {
    sendTaxiAction('abandonJob')
  }

  $scope.dismissOfferPopup = function () {
    $scope.ui.offerPopupDismissedKey = getOfferKey(getFare())
  }

  $scope.setActivePage = function (page) {
    $scope.ui.activePage = page === 'progression' ? 'progression' : 'dashboard'
    if ($scope.ui.activePage === 'progression' && $scope.ui.selectedMilestoneRating === null) {
      var next = $scope.getNextUnlock()
      $scope.ui.selectedMilestoneRating = next ? next.rating : Number($scope.taxi.playerRating || 0)
    }
  }

  $scope.isActivePage = function (page) {
    return $scope.ui.activePage === page
  }

  $scope.toggleSettings = function () {
    $scope.ui.settingsOpen = !$scope.ui.settingsOpen
  }

  $scope.setUiSetting = function (key, value) {
    $scope.ui.settings = buberNormalizeUiSettings($scope.ui.settings)
    buberWriteStoredUiSettings($scope.ui.settings)
    queueUiSettingSave(key, $scope.ui.settings[key])
  }

  $scope.resetUiSettings = function () {
    cancelPendingSettingSaves()
    $scope.ui.settings = buberNormalizeUiSettings()
    buberWriteStoredUiSettings($scope.ui.settings)
    sendUiAction('resetUiSettings')
  }

  // ---------------------------------------------------------------------------
  // Formatters
  // ---------------------------------------------------------------------------

  $scope.formatMoney = buberFormatMoney

  $scope.formatRating = function (value) {
    var amount = Number(value)
    return Number.isFinite(amount) ? amount.toFixed(1) : '--'
  }

  $scope.formatDistance = function (value) {
    var amount = Number(value)
    return Number.isFinite(amount) ? buberFormatDistanceMeters(amount * 1000, 2) : '--'
  }

  $scope.formatPercent = function (value) {
    return Math.round((Number(value) || 0) * 100) + '%'
  }

  $scope.formatScale = function (value) {
    return Math.round((Number(value) || 0) * 100) + '%'
  }

  // ---------------------------------------------------------------------------
  // Display helpers
  // ---------------------------------------------------------------------------

  $scope.getUiSettingsStyle = function () {
    var settings = buberNormalizeUiSettings($scope.ui.settings)
    return [
      '--buber-main-opacity:' + settings.mainOpacity,
      '--buber-main-scale:' + settings.mainScale,
      '--buber-popup-opacity:' + settings.popupOpacity,
      '--buber-popup-scale:' + settings.popupScale,
      '--buber-meter-opacity:' + settings.meterOpacity,
      '--buber-meter-scale:' + settings.meterScale
    ].join(';')
  }

  $scope.getUiPositionClasses = function () {
    var settings = buberNormalizeUiSettings($scope.ui.settings)
    return 'popup-pos-' + settings.popupPosition + ' meter-pos-' + settings.meterPosition
  }

  $scope.getVehicleClassDisplay = function () {
    var fare = getFare()
    var className = String($scope.taxi.vehicleClassName || fare.vehicleClassName || 'C').toUpperCase()
    var pi = Number($scope.taxi.vehiclePerformanceIndex || fare.vehiclePerformanceIndex)
    return Number.isFinite(pi) ? className + ' · ' + pi.toFixed(1) + ' PI' : className
  }

  $scope.getVehicleClassPayDisplay = function () {
    var fare = getFare()
    var multiplier = Number(
      $scope.taxi.vehicleClassMultiplier || fare.vehicleClassMultiplier ||
      $scope.taxi.vehicleMultiplier || 1
    )
    return 'x' + multiplier.toFixed(2)
  }

  $scope.getLastFareResultType = function () {
    var lastFare = $scope.taxi.lastCompletedFare
    return (lastFare && lastFare.resultType) || 'completed'
  }

  $scope.getResultNextState = function () {
    return $scope.taxi.resultNextState || null
  }

  $scope.getProgression = function () {
    return angular.extend(buberDefaultProgression(), $scope.taxi.progression || {})
  }

  $scope.getProgressRatingPercent = function () {
    var progression = $scope.getProgression()
    var rating = Number(progression.rating)
    var maxRating = Number(progression.maxRating) || 5
    if (!Number.isFinite(rating)) rating = Number($scope.taxi.playerRating) || 0
    return Math.max(0, Math.min(100, (rating / maxRating) * 100)) + '%'
  }

  $scope.getProgressionSeatDisplay = function (source) {
    source = source || $scope.getProgression()
    if (source.seatCapUnlimited) return 'Vehicle max'
    return String(Math.max(0, Number(source.seatCap || source.availableSeats || 0)))
  }

  $scope.getProgressionMultiStopCapDisplay = function () {
    var progression = $scope.getProgression()
    return progression.multiStopUnlocked ? $scope.formatMoney(progression.multiStopCap) : 'Locked'
  }

  $scope.getMilestoneMultiStopCapDisplay = function (milestone) {
    return milestone && milestone.multiStopUnlocked ? $scope.formatMoney(milestone.multiStopCap) : 'Locked'
  }

  $scope.getNextUnlock = function () {
    return $scope.getProgression().nextUnlock || null
  }

  $scope.getNextUnlockText = function () {
    var next = $scope.getNextUnlock()
    if (!next) return 'All progression rewards unlocked.'
    return next.label + ' at ' + $scope.formatRating(next.rating) + ' rating.'
  }

  $scope.getProgressionMilestones = function () {
    return $scope.getProgression().milestones || []
  }

  $scope.selectProgressionMilestone = function (milestone) {
    if (!milestone) return
    $scope.ui.selectedMilestoneRating = milestone.rating
  }

  $scope.isSelectedProgressionMilestone = function (milestone) {
    return milestone && Number($scope.ui.selectedMilestoneRating) === Number(milestone.rating)
  }

  $scope.isPastProgressionMilestone = function (milestone) {
    if (!milestone) return false
    return Number($scope.getProgression().rating || 0) > Number(milestone.rating || 0)
  }

  $scope.getMultiStopUnlockRating = function () {
    var required = Number($scope.taxi.multiStopRequiredRating)
    return Number.isFinite(required) ? required : 2.0
  }

  $scope.hasLockedMultiStop = function () {
    return $scope.taxi.multiStopUnlocked === false
  }

  $scope.getMultiStopUnlockText = function () {
    var required = $scope.formatRating($scope.getMultiStopUnlockRating())
    if (Number($scope.taxi.vehicleOpenSeats || 0) >= 18) {
      return 'Bus routes unlock at ' + required + ' driver rating. Direct fares are available now.'
    }
    return 'Multi-stop routes unlock at ' + required + ' driver rating.'
  }

  $scope.isPenaltyResult = isPenaltyResult
  $scope.hasSuccessfulCompletedFare = hasSuccessfulCompletedFare

  // ---------------------------------------------------------------------------
  // Status display (single source of truth)
  // ---------------------------------------------------------------------------

  $scope.getStatusTitle = function () {
    if (isReturnToVehicleActive()) return 'Return to vehicle'
    if ($scope.taxi.taxiDisabled) return 'BUBER unavailable'

    var state = $scope.taxi.state
    var fare = getFare()
    var multi = isMultiStop(fare)
    var shared = isSharedRide(fare)

    // Multi-stop overrides
    if (multi) {
      if (state === STATES.ACCEPT) return shared ? 'New shared ride' : 'New multi-stop route'
      if (state === STATES.PICKUP) return shared ? 'Drive to shared pickup' : 'Drive to first stop'
      if (state === STATES.DROPOFF) return shared ? 'Shared ride active' : 'Multi-stop route active'
    }

    // Default titles
    if (state === STATES.COMPLETE) {
      return isPenaltyResult() ? STATUS_TITLES.complete.abandoned : STATUS_TITLES.complete.default
    }

    return STATUS_TITLES[state] || STATUS_TITLES.start
  }

  $scope.getStatusSubtitle = function () {
    if (isReturnToVehicleActive()) {
      return 'Passenger onboard. Get back in within ' + getReturnToVehicleSeconds() + 's or the fare is abandoned.'
    }

    if ($scope.taxi.taxiDisabled) {
      return $scope.taxi.disabledReason || 'This vehicle cannot take BUBER fares right now.'
    }

    var state = $scope.taxi.state
    var fare = getFare()
    var multi = isMultiStop(fare)
    var shared = isSharedRide(fare)

    if (multi) {
      if (state === STATES.ACCEPT) {
        return shared ? 'Review the shared ride and decide whether to take the group.' : 'Review the scheduled line and decide whether to take the route.'
      }
      if (state === STATES.PICKUP) {
        var pickupName = (fare.pickup && fare.pickup.stopName) || 'the first stop'
        return shared
          ? 'Head to ' + pickupName + ' to collect the shared ride.'
          : 'Head to ' + pickupName + ' to begin ' + (fare.routeLabel || 'the route') + '.'
      }
      if (state === STATES.DROPOFF) {
        return shared
          ? 'Drop each passenger off in order. Next: ' + (fare.nextStopName || 'next drop-off') + '.'
          : 'Continue along ' + (fare.routeLabel || 'the route') + ' toward ' +
             (fare.nextStopName || 'the next stop') + '.'
      }
    }

    return STATUS_SUBTITLES[state](fare, isPenaltyResult())
  }

  $scope.getDispatchHint = function () {
    if (isReturnToVehicleActive()) {
      return 'Return to your vehicle: ' + getReturnToVehicleSeconds() + 's left.'
    }

    if ($scope.taxi.taxiDisabled) {
      return $scope.taxi.disabledReason || 'BUBER is unavailable right now.'
    }

    var state = $scope.taxi.state
    var fare = getFare()
    var multi = isMultiStop(fare)
    var shared = isSharedRide(fare)

    if (multi) {
      if (state === STATES.ACCEPT) return shared ? 'Shared ride ready for review.' : 'Scheduled route ready for review.'
      if (state === STATES.PICKUP) return shared ? 'Shared pickup marked.' : 'First stop marked. Start the line.'
      if (state === STATES.DROPOFF) return shared ? 'Next drop-off: ' + (fare.nextStopName || 'the next stop') + '.' : 'On route to ' + (fare.nextStopName || 'the next stop') + '.'
    }

    if (state === STATES.READY && $scope.hasLockedMultiStop()) {
      return $scope.getMultiStopUnlockText()
    }

    return DISPATCH_HINTS[state]($scope, isPenaltyResult())
  }

  $scope.getSummaryNote = function () {
    if ($scope.taxi.state === STATES.READY && !$scope.taxi.taxiDisabled) {
      if ($scope.hasLockedMultiStop()) return $scope.getMultiStopUnlockText()
      return hasSuccessfulCompletedFare() ? 'Waiting For Next Passenger' : 'Waiting For Job'
    }
    return ''
  }

  // ---------------------------------------------------------------------------
  // State queries
  // ---------------------------------------------------------------------------

  $scope.isOnDuty = isOnDuty
  $scope.hasLiveFare = isLiveFare
  $scope.isReturnToVehicleActive = isReturnToVehicleActive
  $scope.getReturnToVehicleSeconds = getReturnToVehicleSeconds
  $scope.hasFareOffer = function () {
    return $scope.taxi.state === STATES.ACCEPT && !!$scope.taxi.currentFare
  }
  $scope.showFarePopup = function () {
    var offerKey = getOfferKey(getFare())
    return $scope.hasFareOffer() && !!offerKey && $scope.ui.offerPopupDismissedKey !== offerKey
  }
  $scope.hasCurrentFare = function () {
    return !!$scope.taxi.currentFare
  }
  $scope.canAbandonJob = isLiveFare
  $scope.canGoAvailable = function () {
    return !$scope.taxi.taxiDisabled && $scope.taxi.state === STATES.START
  }
  $scope.canStopJob = function () {
    return ON_DUTY_STATES.indexOf($scope.taxi.state) !== -1
  }
  $scope.canToggleDuty = function () {
    return $scope.canGoAvailable() || $scope.canStopJob()
  }
  $scope.hasCompletedFare = function () {
    return $scope.taxi.state === STATES.READY && !$scope.taxi.currentFare && hasSuccessfulCompletedFare()
  }
  $scope.getCompletedFare = function () {
    return $scope.taxi.lastCompletedFare || {}
  }
  $scope.showTaxiMeter = function () {
    return $scope.ui.settings.meterEnabled !== false && (isLiveFare() || $scope.hasCompletedMeterFare())
  }

  // ---------------------------------------------------------------------------
  // Multi-stop helpers
  // ---------------------------------------------------------------------------

  $scope.isMultiStopFare = isMultiStop
  $scope.isSharedRide = isSharedRide

  $scope.getOfferPopupHeadline = function () {
    var fare = getFare()
    if (isSharedRide(fare)) return fare.routeLabel || 'Shared ride'
    return isMultiStop(fare)
      ? (fare.routeLabel || 'Multi-stop route')
      : (fare.passengerTypeName || $scope.taxi.currentPassengerType || 'Standard')
  }

  $scope.getOfferDistance = function () {
    var fare = getFare()
    var distance = Number(fare.totalRouteDistance || fare.estimatedDistance || 0)
    return Number.isFinite(distance) ? buberFormatDistanceMeters(distance, 1) : '--'
  }

  $scope.getOfferRouteLabel = function () {
    return isSharedRide(getFare()) ? 'Drop-offs' : (isMultiStop(getFare()) ? 'Stops' : 'Route')
  }

  $scope.getOfferRouteValue = function () {
    var fare = getFare()
    if (isMultiStop(fare)) {
      return Math.max(1, Number(fare.totalStops || 1) - 1)
    }
    return $scope.getOfferDistance()
  }

  $scope.getOfferDescription = function () {
    var fare = getFare()
    return fare.passengerDescription || 'A new fare is waiting for your response.'
  }

  $scope.getMultiStopDropoffCount = function (fare) {
    fare = fare || $scope.getMeterFareSource()
    var totalStops = Number(fare.totalStops || 0)
    if (!Number.isFinite(totalStops) || totalStops <= 0) {
      totalStops = Array.isArray(fare.stops) ? fare.stops.length : 0
    }
    return Math.max(0, totalStops - 1)
  }

  $scope.getCompletedDropoffCount = function (fare) {
    return Math.max(0, Number((fare || $scope.getMeterFareSource()).completedDropoffStops || 0))
  }

  $scope.getRemainingDropoffCount = function (fare) {
    fare = fare || $scope.getMeterFareSource()
    return Math.max(0, $scope.getMultiStopDropoffCount(fare) - $scope.getCompletedDropoffCount(fare))
  }

  // ---------------------------------------------------------------------------
  // Live fare display
  // ---------------------------------------------------------------------------

  $scope.getActiveFare = getFare

  $scope.getLiveFareHeadline = function () {
    var fare = getFare()
    if (isMultiStop(fare)) {
      if (isSharedRide(fare)) {
        return $scope.taxi.state === STATES.DROPOFF ? 'Shared ride in progress' : 'Heading to shared pickup'
      }
      return $scope.taxi.state === STATES.DROPOFF ? 'Route in progress' : 'Heading to first stop'
    }
    return $scope.taxi.state === STATES.DROPOFF ? 'Passenger onboard' : 'Heading to pickup'
  }

  $scope.getLiveCardPrimaryLabel = function () {
    return isSharedRide(getFare()) ? 'Ride type' : (isMultiStop(getFare()) ? 'Route' : 'Passenger type')
  }

  $scope.getLiveCardPrimaryValue = function () {
    var fare = getFare()
    if (isSharedRide(fare)) {
      return fare.routeLabel || 'Shared ride'
    }
    if (isMultiStop(fare)) {
      return fare.routeLabel || 'Multi-stop'
    }
    return fare.passengerTypeName || $scope.taxi.currentPassengerType || 'Standard'
  }

  $scope.getLiveCardSecondaryLabel = function () {
    if (isSharedRide(getFare())) {
      return $scope.taxi.state === STATES.DROPOFF ? 'Next drop-off' : 'Pickup'
    }
    return isMultiStop(getFare())
      ? ($scope.taxi.state === STATES.DROPOFF ? 'Next stop' : 'First stop')
      : 'Passengers'
  }

  $scope.getLiveCardSecondaryValue = function () {
    var fare = getFare()
    if (!isMultiStop(fare)) {
      return Number(fare.passengers || 0)
    }
    if ($scope.taxi.state === STATES.DROPOFF) {
      return fare.nextStopName || 'Next stop'
    }
    return (fare.pickup && fare.pickup.stopName) || 'Route start'
  }

  $scope.getLiveCardTertiaryLabel = function () {
    if (isSharedRide(getFare())) {
      return $scope.taxi.state === STATES.DROPOFF ? 'Drop-offs left' : 'Drop-offs'
    }
    return isMultiStop(getFare())
      ? ($scope.taxi.state === STATES.DROPOFF ? 'Stops left' : 'Dropoffs')
      : 'Meter'
  }

  $scope.getLiveCardTertiaryValue = function () {
    var fare = getFare()
    if (!isMultiStop(fare)) {
      return 'Bottom center'
    }
    return $scope.taxi.state === STATES.DROPOFF
      ? $scope.getRemainingDropoffCount(fare)
      : $scope.getMultiStopDropoffCount(fare)
  }

  // ---------------------------------------------------------------------------
  // Meter display
  // ---------------------------------------------------------------------------

  $scope.hasCompletedMeterFare = function () {
    return $scope.taxi.state === STATES.COMPLETE && !!$scope.taxi.lastCompletedFare
  }

  $scope.getMeterFareSource = function () {
    if ($scope.hasCompletedMeterFare()) {
      return $scope.taxi.lastCompletedFare || {}
    }
    return getFare()
  }

  $scope.getStopService = function () {
    return $scope.getMeterFareSource().stopService || null
  }

  $scope.hasStopService = function () {
    return !!$scope.getStopService() && isLiveFare()
  }

  $scope.getMeterInstructionSource = function () {
    var fare = $scope.getMeterFareSource()
    var stopService = $scope.getStopService()

    if ($scope.taxi.state === STATES.COMPLETE) return ''
    if (isReturnToVehicleActive()) {
      return 'Return to your vehicle in ' + getReturnToVehicleSeconds() + 's'
    }
    if (!isMultiStop(fare)) return ''

    if (stopService && stopService.instructionHtml) {
      return String(stopService.instructionHtml)
    }

    if (isSharedRide(fare)) {
      return $scope.taxi.state === STATES.PICKUP ? 'Proceed to shared pickup' : 'Proceed to next drop-off'
    }
    return $scope.taxi.state === STATES.PICKUP ? 'Proceed to first stop' : 'Proceed to next stop'
  }

  $scope.hasMeterInstruction = function () {
    return !!$scope.getMeterInstructionSource()
  }

  $scope.getMeterInstructionHtml = function () {
    return $sce.trustAsHtml($scope.getMeterInstructionSource())
  }

  $scope.getMeterStatus = function () {
    var fare = $scope.getMeterFareSource()
    var state = $scope.taxi.state
    var penalty = isPenaltyResult()
    var multi = isMultiStop(fare)

    if (state === STATES.COMPLETE) return penalty ? 'PENALTY' : 'COMPLETE'
    if (isReturnToVehicleActive()) return 'RETURN'
    if ($scope.hasStopService()) return state === STATES.PICKUP ? 'BOARDING' : 'SERVICE'
    if (multi) {
      if (isSharedRide(fare)) return state === STATES.DROPOFF ? 'SHARED' : 'PICKUP'
      return state === STATES.DROPOFF ? 'ON ROUTE' : 'TO STOP'
    }

    switch (state) {
      case STATES.DROPOFF: return 'HIRED'
      case STATES.PICKUP: return 'TO PICKUP'
      default: return 'IDLE'
    }
  }

  $scope.getMeterFareDisplay = function () {
    var fare = $scope.getMeterFareSource()
    if ($scope.taxi.state === STATES.COMPLETE && isPenaltyResult()) {
      return '-' + Number(fare.ratingPenalty || 0).toFixed(2)
    }
    var amount = $scope.taxi.state === STATES.COMPLETE
      ? fare.totalFare
      : (fare.initialBaseFare || fare.baseFare || 0)
    return '$' + Math.ceil(Number(amount))
  }

  $scope.getMeterDistance = function () {
    var fare = $scope.getMeterFareSource()
    var stopService = $scope.getStopService()

    if ($scope.taxi.state === STATES.COMPLETE && isPenaltyResult()) {
      return String(Math.max(1, Number(fare.shiftOffenceCount || 1)))
    }

    if ($scope.taxi.state === STATES.COMPLETE) {
      var dist = Number(fare.totalDistance)
      return Number.isFinite(dist) ? buberFormatDistanceMeters(dist * 1000, 1) : buberFormatDistanceMeters(0, 1)
    }

    if (isReturnToVehicleActive()) {
      return getReturnToVehicleSeconds() + 's'
    }

    if (stopService) {
      if (stopService.instructionStep === 'close') return '--'
      if (isMultiStop(fare) && Number.isFinite(Number(stopService.waitingPassengers))) {
        return String(Math.max(0, Math.ceil(Number(stopService.waitingPassengers || 0))))
      }
      return String(Math.max(0, Math.ceil(Number(stopService.remaining || 0))))
    }

    var distance = Number(fare.remainingDistance)
    if (!Number.isFinite(distance) || distance < 0) {
      distance = Number(fare.estimatedDistance || fare.totalDistance || 0)
    }

    return Number.isFinite(distance) && distance > 0
      ? buberFormatDistanceMeters(distance, 1)
      : buberFormatDistanceMeters(0, 1)
  }

  $scope.getMeterPassengers = function () {
    var fare = $scope.getMeterFareSource()
    var stopService = $scope.getStopService()
    if (isMultiStop(fare) && stopService && Number.isFinite(Number(stopService.onboardPassengers))) {
      return Number(stopService.onboardPassengers || 0)
    }
    if (isMultiStop(fare) && $scope.taxi.state === STATES.DROPOFF) {
      return Number(fare.remainingPassengers || fare.passengers || 0)
    }
    return Number(fare.passengers || 0)
  }

  $scope.getMeterStageLabel = function () {
    var fare = $scope.getMeterFareSource()
    var state = $scope.taxi.state
    var penalty = isPenaltyResult()

    if (state === STATES.COMPLETE) {
      return penalty ? 'SHIFT ENDED' : 'EARNED'
    }

    if (isReturnToVehicleActive()) {
      return 'RETURN NOW'
    }

    if ($scope.hasStopService()) {
      var stopService = $scope.getStopService()
      if (stopService && stopService.instructionStep === 'close') return 'CLOSE DOORS'
      return state === STATES.PICKUP ? 'HOLD FOR PICKUP' : 'HOLD FOR STOP'
    }

    if (isMultiStop(fare)) {
      if (state === STATES.PICKUP) return isSharedRide(fare) ? 'PICKUP' : 'FIRST STOP'
      var total = Math.max(1, $scope.getMultiStopDropoffCount(fare))
      var current = Math.min(total, Math.max(1, $scope.getCompletedDropoffCount(fare) + 1))
      return (isSharedRide(fare) ? 'DROP ' : 'STOP ') + current + ' / ' + total
    }

    return state === STATES.DROPOFF ? 'DROP OFF' : 'PICKUP'
  }

  $scope.getMeterFareLabel = function () {
    var fare = $scope.getMeterFareSource()
    var penalty = isPenaltyResult()

    if ($scope.taxi.state === STATES.COMPLETE) {
      return penalty ? 'RATING HIT' : 'TOTAL FARE'
    }

    return isSharedRide(fare) ? 'SHARED FARE'
      : isMultiStop(fare) ? 'ROUTE FARE'
      : ($scope.taxi.state === STATES.DROPOFF ? 'EST FARE' : 'CALL FARE')
  }

  $scope.getMeterDistanceLabel = function () {
    var fare = $scope.getMeterFareSource()
    var penalty = isPenaltyResult()

    if ($scope.taxi.state === STATES.COMPLETE) {
      return penalty ? 'STRIKE' : 'ROUTE'
    }

    if (isReturnToVehicleActive()) {
      return 'TIMER'
    }

    if ($scope.hasStopService()) {
      var stopService = $scope.getStopService()
      if (stopService && stopService.instructionStep === 'close') return 'DOORS'
      return isSharedRide(fare) ? 'WAIT SEC' : (isMultiStop(fare) ? 'WAIT PAX' : 'WAIT SEC')
    }

    if (isMultiStop(fare) && $scope.taxi.state === STATES.DROPOFF) {
      return 'NEXT'
    }

    return 'ROUTE'
  }

  $scope.getMeterPassengerLabel = function () {
    var fare = $scope.getMeterFareSource()
    if (isMultiStop(fare) && $scope.taxi.state === STATES.DROPOFF) {
      return 'ONBOARD'
    }
    return 'PAX'
  }

  $scope.getMeterPassengerType = function () {
    var fare = $scope.getMeterFareSource()
    var stopService = $scope.getStopService()
    var penalty = isPenaltyResult()

    if ($scope.taxi.state === STATES.COMPLETE && penalty) {
      return 'OFFENCE #' + Math.max(1, Number(fare.shiftOffenceCount || 1))
    }

    if (stopService) {
      return ((stopService.targetName || fare.nextStopName || fare.routeLabel || 'STOP')).toUpperCase()
    }

    if (isMultiStop(fare)) {
      if ($scope.taxi.state === STATES.PICKUP) {
        return ((fare.pickup && fare.pickup.stopName) || fare.routeLabel || 'MULTI-STOP').toUpperCase()
      }
      return (fare.nextStopName || fare.routeLabel || (isSharedRide(fare) ? 'NEXT DROP-OFF' : 'NEXT STOP')).toUpperCase()
    }

    return (fare.passengerTypeName || $scope.taxi.currentPassengerType || 'Standard').toUpperCase()
  }

  $scope.tipBreakdownEntries = function () {
    var breakdown = ($scope.taxi.lastCompletedFare && $scope.taxi.lastCompletedFare.tipBreakdown) || {}
    return Object.keys(breakdown).map(function (key) {
      return { label: key, amount: breakdown[key] }
    })
  }

  $scope.$on('$destroy', function () {
    cancelPendingSettingSaves()
    $interval.cancel(dockTimer)
  })
}])
