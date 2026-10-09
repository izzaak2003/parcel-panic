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
local DeskService = require(script.Parent.DeskService)
local ParcelGenerator = require(script.Parent.ParcelGenerator)
local ParcelProp = require(script.Parent.ParcelProp)
local RateLimit = require(script.Parent.RateLimit)
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

-- Hidden state. It leaves the server only through showRulebook and showParcel.
local rules: { RuleDefs.Rule } = {}
local deck: ParcelGenerator.Deck? = nil
local parcel: Types.Contents? = nil -- the parcel on the desk, or nil when the desk is empty
-- Counts every parcel since the server started and never resets, so a request
-- about an old parcel can never match a new one.
local parcelSeq = 0

local startTimer: thread? = nil
local endTimer: thread? = nil
local parcelTimer: thread? = nil

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

-- The rulebook goes only to players entitled to the Clerk desk.
local function showRulebook(player: Player)
	if not DeskService.sees(player, "Clerk") then
		return
	end
	local ids = {}
	for index, rule in rules do
		ids[index] = rule.id
	end
	Remotes.RulebookShown:FireClient(player, ids)
end

-- What is inside the parcel goes only to players entitled to the Scanner desk.
local function showParcel(player: Player)
	if parcel and DeskService.sees(player, "Scanner") then
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
	DeskService.closePeek()
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
	DeskService.openPeek()
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
	DeskService.openPeek()
	queueParcel(Config.FirstParcelDelay)
end

-- Called when someone joins or leaves, before anyone is sent anything.
--
-- A change of company can leave a player holding a half they are no longer
-- entitled to: someone who was alone has seen both, and someone moved across to
-- fill an empty desk has seen the other side. So whenever two or more players
-- remain, the rules are picked again and the parcel on the desk is replaced, at
-- no cost to the team. What anyone saw before is then worth nothing.
-- DeskService sends each player their share of the new deal straight after this.
local function onRosterChanged(playerCount: number)
	if phase ~= "Running" or playerCount < 2 then
		return
	end
	rules, deck = chooseRules()
	parcel = nil
	ParcelProp.hide()
	queueParcel(Config.ParcelGap)
end

-- Everything after `player` comes from the client and may be anything at all.
local function onSubmitVerdict(player: Player, seq: unknown, verdict: unknown)
	if not RateLimit.allow(player, "verdict") or not DeskService.canStamp(player) then
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
	if not RateLimit.allow(player, "shift") or phase ~= "Ended" then
		return
	end
	startShift()
end

-- Called when a player joins, and again whenever what they may see changes:
-- a desk switch, or someone else joining or leaving. Sends them everything they
-- are now entitled to. The client hides whatever belongs to a desk it has left.
local function onDeskChanged(player: Player)
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
	DeskService.start(onDeskChanged, onRosterChanged)
end

return ShiftService
