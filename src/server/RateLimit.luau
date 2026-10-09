--!strict
-- Limits how often a player may make each kind of request. Each kind has its
-- own clock, so stamping a parcel does not swallow a desk switch made just after.
local Players = game:GetService("Players")

local Config = require(script.Parent.Config)

type Bucket = { tokens: number, at: number }

local RateLimit = {}

local lastRequestAt: { [Player]: { [string]: number } } = {}
local buckets: { [Player]: { [string]: Bucket } } = {}

Players.PlayerRemoving:Connect(function(player)
	lastRequestAt[player] = nil
	buckets[player] = nil
end)

-- One request of this kind per cooldown.
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

-- A short run of requests at once, then a steady trickle: up to `burst` in a
-- row, refilling at `perSecond`. For things a player does in quick groups.
function RateLimit.allowBurst(
	player: Player,
	kind: string,
	burst: number,
	perSecond: number
): boolean
	if player.Parent ~= Players then
		return false
	end
	local mine = buckets[player]
	if not mine then
		mine = {}
		buckets[player] = mine
	end
	local now = os.clock()
	local bucket = mine[kind]
	if not bucket then
		bucket = { tokens = burst, at = now }
		mine[kind] = bucket
	end
	bucket.tokens = math.min(burst, bucket.tokens + (now - bucket.at) * perSecond)
	bucket.at = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

return RateLimit
