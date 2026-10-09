--!strict
-- Runs the shift. This is the only code that decides what state the game is in.
--
--   Waiting --(first player arrives)--> Running --(time up, or too many mistakes)--> Ended
--                                          ^                                           |
--                                          +--------(a player asks for a new shift)----+
--
-- While Running, the desk is either empty or holds one parcel waiting for a verdict.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent.Config)
local ParcelGenerator = require(script.Parent.ParcelGenerator)
local ParcelProp = require(script.Parent.ParcelProp)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RuleDefs = require(ReplicatedStorage.Shared.RuleDefs)
local Rulebook = require(script.Parent.Rulebook)
local Types = require(ReplicatedStorage.Shared.Types)

local ShiftService = {}

local rng = Random.new()

-- Public state. Every player may know all of it.
local phase: Types.Phase = "Waiting"
local endReason: Types.EndReason? = nil
local endsAt = 0
local strikes = 0
local correct = 0

-- Hidden state. It leaves the server only through RulebookShown and ParcelScanned.
local rules: { RuleDefs.Rule } = {}
local deck: ParcelGenerator.Deck? = nil
local parcel: Types.Contents? = nil -- the parcel on the desk, or nil when the desk is empty
-- Counts every parcel since the server started and never resets, so a request
-- about an old parcel can never match a new one.
local parcelSeq = 0

local startTimer: thread? = nil
local endTimer: thread? = nil
local parcelTimer: thread? = nil
local lastRequestAt: { [Player]: number } = {}

local function publicState(): Types.PublicShiftState
	return {
		phase = phase,
		endsAt = endsAt,
		maxStrikes = Config.MaxStrikes,
		strikes = strikes,
		correct = correct,
		parcelSeq = if parcel then parcelSeq else 0,
		endReason = endReason,
	}
end

local function broadcast()
	Remotes.ShiftSync:FireAllClients(publicState())
end

-- For now every player sits at both desks, so everyone is shown the rulebook and
-- the X-ray. Once desks exist, each of these goes only to the players at its desk.
local function showRulebook(player: Player)
	local ids = {}
	for index, rule in rules do
		ids[index] = rule.id
	end
	Remotes.RulebookShown:FireClient(player, ids)
end

local function showParcel(player: Player)
	if parcel then
		Remotes.ParcelScanned:FireClient(player, parcelSeq, parcel)
	end
end

local function cancel(timer: thread?)
	if timer then
		task.cancel(timer)
	end
end

local function cancelTimers()
	cancel(startTimer)
	cancel(endTimer)
	cancel(parcelTimer)
	startTimer, endTimer, parcelTimer = nil, nil, nil
end

local function endShift(reason: Types.EndReason)
	cancelTimers()
	phase = "Ended"
	endReason = reason
	parcel = nil
	ParcelProp.hide()
	broadcast()
end

local function putParcelOnDesk()
	local currentDeck = deck
	if phase ~= "Running" or not currentDeck then
		return
	end
	parcelSeq += 1
	parcel = ParcelGenerator.draw(currentDeck, rng, Config.ReturnChance)
	ParcelProp.show()
	broadcast()
	for _, player in Players:GetPlayers() do
		showParcel(player)
	end
end

-- Each timer clears its own variable before it runs, so cancelTimers only ever
-- cancels timers that are still waiting.
local function queueParcel(delay: number)
	cancel(parcelTimer)
	parcelTimer = task.delay(delay, function()
		parcelTimer = nil
		putParcelOnDesk()
	end)
end

-- Picks rules that leave at least one parcel to ship and one to send back.
local function chooseRules(): ({ RuleDefs.Rule }, ParcelGenerator.Deck)
	for _ = 1, 20 do
		local picked = Rulebook.pick(rng, Config.RulesPerShift)
		local dealt = ParcelGenerator.deal(picked)
		if #dealt.ship > 0 and #dealt.back > 0 then
			return picked, dealt
		end
	end
	-- A single rule names one value of one trait, so it can never cover every parcel.
	local fallback = Rulebook.pick(rng, 1)
	return fallback, ParcelGenerator.deal(fallback)
end

local function startShift()
	cancelTimers()
	rules, deck = chooseRules()
	phase = "Running"
	endReason = nil
	strikes = 0
	correct = 0
	parcel = nil
	endsAt = workspace:GetServerTimeNow() + Config.ShiftSeconds
	endTimer = task.delay(Config.ShiftSeconds, function()
		endTimer = nil
		endShift("TimeUp")
	end)

	broadcast()
	for _, player in Players:GetPlayers() do
		showRulebook(player)
	end
	queueParcel(Config.FirstParcelDelay)
end

-- One shared limit for everything a player can ask for.
local function allowRequest(player: Player): boolean
	-- A request can still be in flight when its sender leaves. Dropping it keeps a
	-- player who has gone from being written back into lastRequestAt.
	if player.Parent ~= Players then
		return false
	end
	local now = os.clock()
	local last = lastRequestAt[player]
	if last and now - last < Config.RequestCooldown then
		return false
	end
	lastRequestAt[player] = now
	return true
end

-- Everything after `player` comes from the client and may be anything at all.
local function onSubmitVerdict(player: Player, seq: unknown, verdict: unknown)
	if not allowRequest(player) then
		return
	end
	if typeof(seq) ~= "number" or (verdict ~= "Ship" and verdict ~= "Return") then
		return
	end
	local judged = parcel
	if phase ~= "Running" or not judged or seq ~= parcelSeq then
		return
	end

	-- Clear the desk before anything else, so a repeat of this request is rejected.
	parcel = nil
	ParcelProp.hide()

	local wasCorrect = verdict == Rulebook.judge(rules, judged)
	if wasCorrect then
		correct += 1
	else
		strikes += 1
	end
	Remotes.VerdictJudged:FireAllClients(seq, verdict, wasCorrect)

	if strikes >= Config.MaxStrikes then
		endShift("StruckOut")
	else
		broadcast()
		queueParcel(Config.ParcelGap)
	end
end

local function onRequestShift(player: Player)
	if not allowRequest(player) or phase ~= "Ended" then
		return
	end
	startShift()
end

local function onPlayerAdded(player: Player)
	Remotes.ShiftSync:FireClient(player, publicState())
	if phase == "Running" then
		showRulebook(player)
		showParcel(player)
	elseif phase == "Waiting" and not startTimer then
		startTimer = task.delay(Config.ShiftStartDelay, function()
			startTimer = nil
			startShift()
		end)
	end
end

function ShiftService.start()
	Remotes.SubmitVerdict.OnServerEvent:Connect(onSubmitVerdict)
	Remotes.RequestShift.OnServerEvent:Connect(onRequestShift)

	Players.PlayerRemoving:Connect(function(player)
		lastRequestAt[player] = nil
	end)
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return ShiftService
