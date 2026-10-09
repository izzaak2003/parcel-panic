--!strict
local PingService = require(script.PingService)
local PlayerData = require(script.PlayerData)
local ShiftService = require(script.ShiftService)

PlayerData.start()
ShiftService.start()
PingService.start()
