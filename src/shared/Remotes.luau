--!strict
-- The named messages between the server and the clients. The RemoteEvents
-- themselves are declared in default.project.json; this module hands them out.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = ReplicatedStorage:WaitForChild("Remotes")

local function event(name: string): RemoteEvent
	local remote = folder:WaitForChild(name)
	assert(remote:IsA("RemoteEvent"), `Remotes.{name} must be a RemoteEvent`)
	return remote
end

return table.freeze({
	-- Server to client
	ShiftSync = event("ShiftSync"), -- (state: PublicShiftState) sent whenever the public state changes
	RulebookShown = event("RulebookShown"), -- (ruleIds: { string }) the rules for this shift
	ParcelScanned = event("ParcelScanned"), -- (seq: number, contents: Contents) what is inside the parcel
	VerdictJudged = event("VerdictJudged"), -- (seq: number, verdict: Verdict, wasCorrect: boolean)
	DeskSync = event("DeskSync"), -- (state: DeskState) this player's own desk, sent whenever it changes
	PingShown = event("PingShown"), -- (ping: Ping) a stamp on the ping board, sent to everyone

	-- Client to server. These are requests; the server checks every one.
	SubmitVerdict = event("SubmitVerdict"), -- (seq: number, verdict: Verdict)
	RequestShift = event("RequestShift"), -- () start a new shift after one has ended
	RequestSwitch = event("RequestSwitch"), -- () solo only: move to the other desk
	-- (stampId: string, deal: number, parcelSeq: number, choice: number?) put a stamp on the ping board;
	-- deal and parcelSeq are the ones the player was looking at
	SendPing = event("SendPing"),
})
