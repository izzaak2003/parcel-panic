--!strict
-- Holds the latest of everything the server has sent this player, and is the
-- only client code that talks to the server. The screen, the camera, and the
-- room effects all read from here and are told when something changes.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local SETTLE_SECONDS = 0.5

local ShiftClient = {}

local state: Types.PublicShiftState? = nil
local desk: Types.DeskState? = nil
local scannedSeq = 0
local scanned: Types.Contents? = nil
local ruleIds: { string } = {}
local progress: Types.Progress? = nil
local live = false

local changeListeners: { () -> () } = {}
local verdictListeners: { (number, Types.Verdict, boolean) -> () } = {}
local pingListeners: { (Types.Ping) -> () } = {}

-- One listener failing must not stop the others hearing the same news.
local function report(problem: unknown)
	warn(`A screen could not handle an update: {problem}`)
end

local function changed()
	for _, listener in changeListeners do
		xpcall(listener, report)
	end
end

function ShiftClient.getState(): Types.PublicShiftState?
	return state
end

function ShiftClient.getDesk(): Types.DeskState?
	return desk
end

function ShiftClient.getRuleIds(): { string }
	return ruleIds
end

-- This player's licence and collection book, once the server has sent them.
function ShiftClient.getProgress(): Types.Progress?
	return progress
end

-- What is inside the parcel on the desk, if this player has been told.
function ShiftClient.getContents(): Types.Contents?
	local current = state
	if
		current
		and current.phase == "Running"
		and current.parcelSeq > 0
		and scannedSeq == current.parcelSeq
	then
		return scanned
	end
	return nil
end

-- False for the first moment after joining. Messages that piled up while the
-- game was loading arrive all at once then, and should update what is shown
-- without each one being played as an event.
function ShiftClient.isLive(): boolean
	return live
end

function ShiftClient.onChanged(listener: () -> ())
	table.insert(changeListeners, listener)
end

function ShiftClient.onVerdict(listener: (number, Types.Verdict, boolean) -> ())
	table.insert(verdictListeners, listener)
end

function ShiftClient.onPing(listener: (Types.Ping) -> ())
	table.insert(pingListeners, listener)
end

-- Requests. The server decides whether each one counts.
function ShiftClient.submit(verdict: Types.Verdict)
	local current = state
	if current and current.phase == "Running" and current.parcelSeq > 0 then
		Remotes.SubmitVerdict:FireServer(current.parcelSeq, verdict)
	end
end

function ShiftClient.requestShift()
	Remotes.RequestShift:FireServer()
end

function ShiftClient.requestSwitch()
	local own = desk
	if own and own.solo then
		Remotes.RequestSwitch:FireServer()
	end
end

-- The server is told which rulebook and parcel this player was looking at, so
-- it can drop a stamp that arrives after either has changed.
function ShiftClient.ping(stampId: string, choice: number?)
	local own = desk
	local current = state
	if own and current and not own.solo then
		Remotes.SendPing:FireServer(stampId, current.deal, current.parcelSeq, choice)
	end
end

-- Call after every listener has been added, so nothing sent early is missed.
function ShiftClient.start()
	Remotes.ShiftSync.OnClientEvent:Connect(function(newState: Types.PublicShiftState)
		state = newState
		changed()
	end)

	Remotes.DeskSync.OnClientEvent:Connect(function(newDesk: Types.DeskState)
		desk = newDesk
		-- Once the desks are split, drop whatever belonged to the other one. The
		-- server has already dealt new rules and a new parcel by then, so this is
		-- tidying, not what keeps the halves apart.
		if not newDesk.solo then
			if newDesk.desk == "Scanner" then
				ruleIds = {}
			else
				scannedSeq = 0
				scanned = nil
			end
		end
		changed()
	end)

	Remotes.ParcelScanned.OnClientEvent:Connect(function(seq: number, contents: Types.Contents)
		scannedSeq = seq
		scanned = contents
		changed()
	end)

	Remotes.RulebookShown.OnClientEvent:Connect(function(ids: { string })
		ruleIds = ids
		changed()
	end)

	Remotes.ProgressSync.OnClientEvent:Connect(function(newProgress: Types.Progress)
		progress = newProgress
		changed()
	end)

	Remotes.VerdictJudged.OnClientEvent:Connect(
		function(seq: number, verdict: Types.Verdict, wasCorrect: boolean)
			if live then
				for _, listener in verdictListeners do
					xpcall(listener, report, seq, verdict, wasCorrect)
				end
			end
		end
	)

	Remotes.PingShown.OnClientEvent:Connect(function(ping: Types.Ping)
		if live then
			for _, listener in pingListeners do
				xpcall(listener, report, ping)
			end
		end
	end)

	task.delay(SETTLE_SECONDS, function()
		live = true
		changed()
	end)
end

return ShiftClient
