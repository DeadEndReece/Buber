local M = {}
local logTag = "buber"

local function onExtensionLoaded()
  log("I", logTag, "Loading buber modules...")
  
  local extName = extensions.loadAtRoot("lua/ge/extensions/buber/ui", "buber")
  if extName then
    log("I", logTag, "Loaded: " .. extName)
  end
end

M.onExtensionLoaded = onExtensionLoaded
return M