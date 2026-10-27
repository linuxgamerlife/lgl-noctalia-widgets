--!nonstrict
-- Headless poller. Started when the plugin is enabled (plugin_api 17+).

local service = require("./lib/service.luau")

service.start()

function update()
  service.update()
end

function onConfigChanged()
  service.configChanged()
end

function onIpc(event, payload)
  service.ipc(event, payload)
end

function onExit(_signal, _reason)
  service.stop()
end
