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
	ShiftStartDelay = tuned("ShiftStartDelay", 2), -- a player arriving to the shift starting, when none is running
	FirstParcelDelay = tuned("FirstParcelDelay", 3), -- shift starting to the first parcel
	ParcelGap = tuned("ParcelGap", 1.5), -- a verdict to the next parcel
	ReturnChance = tuned("ReturnChance", 0.5), -- share of parcels that should go back
	RequestCooldown = tuned("RequestCooldown", 0.25), -- shortest gap between requests from one player
	PeekSeconds = tuned("PeekSeconds", 15), -- solo: rulebook time allowed per parcel
	PingBurst = tuned("PingBurst", 4), -- stamps a player may send in a row: three traits and one more
	PingPerSecond = tuned("PingPerSecond", 1), -- how fast that allowance refills
	OddChance = tuned("OddChance", 0.04), -- share of parcels that hold the odd item
	LicenceSlots = tuned("LicenceSlots", 6), -- stamps on a full licence card
	StampParcels = tuned("StampParcels", 10), -- parcels a player must be present for, handled correctly in one shift, to earn the day's stamp
	DayOffset = tuned("DayOffset", 0), -- added to today's date; only for testing tomorrow today
	SaveAttempts = tuned("SaveAttempts", 4), -- tries at loading or saving before giving up
	SaveBackoff = tuned("SaveBackoff", 1), -- seconds before the second try; doubles each time
	AutosaveSeconds = tuned("AutosaveSeconds", 60), -- how often changed progress is saved during play
	SaveGap = tuned("SaveGap", 15), -- after a save, how long before an award may trigger another at once
	ShutdownSeconds = tuned("ShutdownSeconds", 25), -- longest the server waits for saves when it closes
})
