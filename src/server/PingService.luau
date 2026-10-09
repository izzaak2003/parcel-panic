--!strict
-- The ping board: ready-made messages between the desks, so a team can work
-- without chat. A client only picks a stamp. The server decides what the stamp
-- says, from what it knows, and sends the result to everyone.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent.Config)
local DeskService = require(script.Parent.DeskService)
local RateLimit = require(script.Parent.RateLimit)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ShiftService = require(script.Parent.ShiftService)
local StampDefs = require(ReplicatedStorage.Shared.StampDefs)
local Types = require(ReplicatedStorage.Shared.Types)

local PingService = {}

local pingSeq = 0

-- Everything after `player` comes from the client and may be anything at all.
--
-- `dealSeen` and `seqSeen` say which rulebook and which parcel the player was
-- looking at when they pressed the stamp. If either has moved on, the stamp is
-- dropped: it was about something that is no longer there, and after a change of
-- team the sender may be at a different desk from the one they pressed it at.
local function onSendPing(
	player: Player,
	stampId: unknown,
	dealSeen: unknown,
	seqSeen: unknown,
	choice: unknown
)
	if not RateLimit.allowBurst(player, "ping", Config.PingBurst, Config.PingPerSecond) then
		return
	end
	if typeof(stampId) ~= "string" or typeof(seqSeen) ~= "number" then
		return
	end
	local stamp = StampDefs.ById[stampId]
	local desk: Types.Desk? = DeskService.deskOf(player)
	-- A player alone has nobody to ping.
	if not stamp or not desk or DeskService.isSolo() or not ShiftService.isRunning() then
		return
	end
	if dealSeen ~= ShiftService.currentDeal() then
		return
	end
	-- A rule belongs to the rulebook. Every other stamp is about one parcel.
	if stamp.kind ~= "rule" and seqSeen ~= ShiftService.parcelOnDesk() then
		return
	end

	local ping: Types.Ping = {
		seq = 0,
		deal = ShiftService.currentDeal(),
		parcelSeq = ShiftService.parcelOnDesk(),
		from = desk,
		stamp = stamp.id,
	}
	local trait: Types.Trait? = stamp.trait
	if stamp.kind == "trait" and trait and desk == "Scanner" then
		-- The Scanner states a trait. The value is the server's own, so the stamp
		-- cannot say anything untrue, and it needs that parcel to still be on the desk.
		local value = ShiftService.traitFor(player, trait, seqSeen)
		if value == nil then
			return
		end
		ping.value = value
	elseif stamp.kind == "rule" and desk == "Clerk" then
		-- The Clerk shows one rule, chosen by its place in the rulebook.
		local ruleId = if typeof(choice) == "number"
			then ShiftService.ruleIdFor(player, choice)
			else nil
		if not ruleId then
			return
		end
		ping.ruleId = ruleId
	end
	-- Anything else is a plain stamp, or a question about what the sender cannot see.

	pingSeq += 1
	ping.seq = pingSeq
	Remotes.PingShown:FireAllClients(ping)
end

function PingService.start()
	Remotes.SendPing.OnServerEvent:Connect(onSendPing)
end

return PingService
