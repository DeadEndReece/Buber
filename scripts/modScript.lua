local logTag = "BUBER"

log("I", logTag, "Loading BUBER")

setExtensionUnloadMode("buber_ui", "manual")
setExtensionUnloadMode("gameplay_taxi", "manual")

if extensions.gameplay_taxi and type(extensions.gameplay_taxi.setAvailable) ~= "function" then
  extensions.unload("gameplay_taxi")
end

if extensions.loadAtRoot then
  extensions.loadAtRoot("lua/ge/extensions/gameplay/taxi", "gameplay")
else
  extensions.load("gameplay_taxi")
end

extensions.load("buber_ui")

log("I", logTag, "BUBER loaded")
