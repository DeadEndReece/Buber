local logTag = "BUBER"

log("I", logTag, "Loading BUBER")

setExtensionUnloadMode("buber_ui", "manual")
setExtensionUnloadMode("gameplay_taxi", "manual")

-- gameplay_taxi is listed in buber_ui's dependencies, so it auto-loads
extensions.load("buber_ui")

log("I", logTag, "BUBER loaded")