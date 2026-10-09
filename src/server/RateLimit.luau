--!strict
-- Limits how often a player may make each kind of request. Each kind has its
-- own clock, so stamping a parcel does not swallow a desk switch made just after.
local Players = game:GetService("Players")

local Config = require(script.Parent.Config)

local RateLimit = {}

local lastRequestAt: { [Player]: { [string]: number } } = {}

Players.PlayerRemoving:Connect(function(player)
	lastRequestAt[player] = nil
end)

function RateLimit.allow(player: Player, kind: string): boolean
	-- A request can still be in flight when its sender leaves. Dropping it keeps a
	-- player who has gone from being written back into the table.
	if player.Parent ~= Players then
		return false
	end
	local times = lastRequestAt[player]
	if not times then
		times = {}
		lastRequestAt[player] = times
	end
	local now = os.clock()
	local last = times[kind]
	if last and now - last < Config.RequestCooldown then
		return false
	end
	times[kind] = now
	return true
end

return RateLimit
