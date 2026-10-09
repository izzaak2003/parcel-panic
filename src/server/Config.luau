--!strict
-- The numbers that tune a shift. Change values here, not in the logic.
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

-- In Studio only, a number attribute on ServerScriptService named "Test_<Key>"
-- replaces a value, so a playtest can run a 30-second shift. Live servers ignore it.
local function tuned(key: string, default: number): number
	if RunService:IsStudio() then
		local override = ServerScriptService:GetAttribute("Test_" .. key)
		if typeof(override) == "number" then
			return override
		end
	end
	return default
end

return table.freeze({
	ShiftSeconds = tuned("ShiftSeconds", 480),
	MaxStrikes = tuned("MaxStrikes", 3),
	RulesPerShift = tuned("RulesPerShift", 3),
	ShiftStartDelay = tuned("ShiftStartDelay", 2), -- first player arriving to the shift starting
	FirstParcelDelay = tuned("FirstParcelDelay", 3), -- shift starting to the first parcel
	ParcelGap = tuned("ParcelGap", 1.5), -- a verdict to the next parcel
	ReturnChance = tuned("ReturnChance", 0.5), -- share of parcels that should go back
	RequestCooldown = tuned("RequestCooldown", 0.25), -- shortest gap between requests from one player
	PeekSeconds = tuned("PeekSeconds", 15), -- solo: rulebook time allowed per parcel
	PingBurst = tuned("PingBurst", 4), -- stamps a player may send in a row: three traits and one more
	PingPerSecond = tuned("PingPerSecond", 1), -- how fast that allowance refills
})
