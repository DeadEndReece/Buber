local logTag = "BUBER"

log("I", logTag, "Loading BUBER")

-- Load config first so it is available before buberTaxi.lua runs
setExtensionUnloadMode("gameplay_taxiConfig", "manual")
if extensions.loadAtRoot then
  extensions.loadAtRoot("lua/ge/extensions/gameplay/taxiConfig", "gameplay")
else
  extensions.load("gameplay_taxiConfig")
end

setExtensionUnloadMode("gameplay_buberTaxi", "manual")
setExtensionUnloadMode("buber_ui", "manual")

if extensions.loadAtRoot then
  extensions.loadAtRoot("lua/ge/extensions/gameplay/buberTaxi", "gameplay")
else
  extensions.load("gameplay_buberTaxi")
end

extensions.load("buber_ui")

log("I", logTag, "BUBER loaded")
