local M = {}
M.dependencies = { "gameplay_taxi" }

local logTag = "buberapp"

local defaultAppLayoutDirectory = "settings/ui_apps/originalLayouts/default/"
local userDefaultAppLayoutDirectory = "settings/ui_apps/layouts/default/"
local uiSettingsDirectory = "settings/buber"
local uiSettingsFile = uiSettingsDirectory .. "/uiSettings.json"

local defaultUiSettings = {
  mainOpacity = 1,
  mainScale = 1,
  popupOpacity = 1,
  popupScale = 1,
  popupPosition = "bottom-center",
  meterEnabled = true,
  meterOpacity = 1,
  meterScale = 1,
  meterPosition = "bottom-center"
}

local positionOptions = {
  ["bottom-center"] = true,
  ["bottom-left"] = true,
  ["bottom-right"] = true,
  ["top-center"] = true,
  ["top-right"] = true
}

local uiApp = {
  appName = "buberapp",
  placement = {
    left = "0px",
    top = "250px",
    width = "500px",
    height = "420px",
    position = "absolute"
  }
}

local careerLayout = { filename = "career" }

local runtime = {
  open = false,
  settings = {},
  settingsLoaded = false,
  lastUiPushAt = 0,
  stateToUpdate = false
}

local function copyTable(source)
  local out = {}
  for key, value in pairs(source or {}) do
    out[key] = value
  end
  return out
end

local function clampNumber(value, minValue, maxValue)
  local number = tonumber(value)
  if not number then return nil end
  return math.max(minValue, math.min(maxValue, number))
end

local function sanitizeBoolean(value, fallback)
  if value == true or value == "true" or value == "1" or value == 1 then return true end
  if value == false or value == "false" or value == "0" or value == 0 then return false end
  return fallback
end

local function sanitizePosition(value, fallback)
  value = tostring(value or "")
  return positionOptions[value] and value or fallback
end

local function sanitizeUiSetting(key, value, fallback)
  if key == "mainOpacity" or key == "popupOpacity" or key == "meterOpacity" then
    return clampNumber(value, 0.35, 1) or fallback
  end

  if key == "mainScale" or key == "popupScale" or key == "meterScale" then
    return clampNumber(value, 0.75, 1) or fallback
  end

  if key == "popupPosition" or key == "meterPosition" then
    return sanitizePosition(value, fallback)
  end

  if key == "meterEnabled" then
    return sanitizeBoolean(value, fallback)
  end

  return fallback
end

local function sanitizeUiSettings(data)
  local settings = copyTable(defaultUiSettings)
  if type(data) ~= "table" then return settings end

  for key, fallback in pairs(defaultUiSettings) do
    settings[key] = sanitizeUiSetting(key, data[key], fallback)
  end

  return settings
end

local function loadUiSettings()
  runtime.settings = sanitizeUiSettings(jsonReadFile(uiSettingsFile) or {})
  runtime.settingsLoaded = true
end

local function ensureUiSettingsLoaded()
  if not runtime.settingsLoaded then
    loadUiSettings()
  end
end

local function saveUiSettings()
  if not FS:directoryExists(uiSettingsDirectory) then
    FS:directoryCreate(uiSettingsDirectory)
  end

  jsonWriteFile(uiSettingsFile, runtime.settings, true)
end

local function setUiSetting(key, value)
  ensureUiSettingsLoaded()

  if defaultUiSettings[key] == nil then return end

  runtime.settings[key] = sanitizeUiSetting(key, value, runtime.settings[key])
  saveUiSettings()
end

local function resetUiSettings()
  runtime.settings = copyTable(defaultUiSettings)
  runtime.settingsLoaded = true
  saveUiSettings()
end

local function pushUiState()
  ensureUiSettingsLoaded()

  local now = os.clock()
  if (now - runtime.lastUiPushAt) < 0.15 then return end

  runtime.lastUiPushAt = now
  guihooks.trigger("buberUiState", { ui = { open = runtime.open, settings = runtime.settings } })
end

local function requestUiState(force)
  if force then runtime.lastUiPushAt = 0 end
  pushUiState()
end

local taxiActionMethods = {
  setAvailable = "setAvailable",
  stopTaxiJob = "stopTaxiJob",
  acceptJob = "acceptJob",
  rejectJob = "rejectJob",
  abandonJob = "abandonCurrentJob"
}

local function getTaxiExtension(methodName)
  local taxi = extensions and extensions.gameplay_taxi or nil
  if taxi and type(taxi[methodName]) == "function" then return taxi end

  taxi = gameplay_taxi
  if taxi and type(taxi[methodName]) == "function" then return taxi end

  if extensions then
    if extensions.unload and extensions.gameplay_taxi then
      pcall(extensions.unload, "gameplay_taxi")
    end

    if setExtensionUnloadMode then
      pcall(setExtensionUnloadMode, "gameplay_taxi", "manual")
    end

    local ok, err = false, nil
    if extensions.loadAtRoot then
      ok, err = pcall(extensions.loadAtRoot, "lua/ge/extensions/gameplay/taxi", "gameplay")
    elseif extensions.load then
      ok, err = pcall(extensions.load, "gameplay_taxi")
    end

    if not ok then
      log("E", logTag, "Unable to load BUBER gameplay_taxi: " .. tostring(err or "no extension loader available"))
    end
  end

  taxi = extensions and extensions.gameplay_taxi or nil
  if taxi and type(taxi[methodName]) == "function" then return taxi end

  taxi = gameplay_taxi
  if taxi and type(taxi[methodName]) == "function" then return taxi end

  return nil
end

local function callTaxiAction(actionName)
  local methodName = taxiActionMethods[actionName]
  if not methodName then return false end

  local taxi = getTaxiExtension(methodName)
  if not taxi then
    log("E", logTag, "BUBER taxi action unavailable: " .. tostring(actionName) .. " (" .. tostring(methodName) .. ")")
    return false
  end

  local ok, err = pcall(taxi[methodName])
  if not ok then
    log("E", logTag, "BUBER taxi action failed: " .. tostring(actionName) .. " - " .. tostring(err))
    return false
  end

  return true
end


local function handleUiAction(action)
  local actionName = tostring(action or "")

  if actionName == "toggleOpen" then
    runtime.open = not runtime.open
  elseif actionName == "open" then
    runtime.open = true
  elseif actionName == "close" then
    runtime.open = false
  elseif taxiActionMethods[actionName] then
    callTaxiAction(actionName)
  elseif actionName == "resetUiSettings" then
    resetUiSettings()
  else
    local key, value = string.match(actionName, "^setUiSetting:([^:]+):(.+)$")
    if key then
      setUiSetting(key, value)
    end
  end

  requestUiState(true)
end

local function onExtensionLoaded()
  getTaxiExtension("setAvailable")
  loadUiSettings()
  requestUiState(true)
end

local function onUpdate()
  if runtime.stateToUpdate then
    ui_apps.requestUIAppsData()
    runtime.stateToUpdate = false
  end
end

local function onGameStateUpdate(state)
  getTaxiExtension("setAvailable")

  if state and state.appLayout == "freeroam" and career_career.isActive() then
    if ui_apps_genericMissionData then
      ui_apps_genericMissionData.clearData()
    end
    core_gamestate.setGameState("career", "career", nil)
    return
  end

  onUpdate()
  requestUiState(true)
end

M.onExtensionLoaded = onExtensionLoaded
M.onUpdate = onUpdate
M.onGameStateUpdate = onGameStateUpdate
M.requestUiState = requestUiState
M.handleUiAction = handleUiAction
M.setUiSetting = setUiSetting
M.resetUiSettings = resetUiSettings

M.toggle = function()
  runtime.open = not runtime.open
  requestUiState(true)
end

M.open = function()
  runtime.open = true
  requestUiState(true)
end

M.close = function()
  runtime.open = false
  pushUiState()
end

return M
