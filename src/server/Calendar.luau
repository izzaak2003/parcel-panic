--!strict
-- What day it is, as far as the game is concerned. Always the server's clock in
-- UTC, never a player's device, so everyone in the world shares one "today".
local Config = require(script.Parent.Config)

local SECONDS_IN_A_DAY = 86400

local Calendar = {}

-- Days since 1 January 1970, UTC. Tomorrow is today plus one.
function Calendar.today(): number
	return os.time() // SECONDS_IN_A_DAY + Config.DayOffset
end

return Calendar
