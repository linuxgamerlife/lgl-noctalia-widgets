--!nonstrict

-- SPDX-License-Identifier: MIT
-- Copyright (C) 2026 LinuxGamerLife

-- Weather & Time service entry. The implementation lives in lib/service.luau.

local service = require("./lib/service.luau")

service.start()

function update()
  service.update()
end

function onConfigChanged()
  service.configChanged()
end

function onIpc(event, _payload)
  service.ipc(event)
end

function onExit(_signal, _reason)
  service.stop()
end
