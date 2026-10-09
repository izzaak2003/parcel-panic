--!strict
-- Decides who works at which desk, stands each player at it, and runs the lone
-- player's desk switching. All of it is held here; a client can only ask to switch.
--
-- With two or more players the desks are split and nobody may switch: the Scanner
-- desk gets the X-ray, the Clerk desk gets the rulebook and gives the verdict.
-- A player alone works both desks, one at a time, and may give the verdict from
-- either. Their time at the rulebook is limited for each parcel.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent.Config)
local DeskPlan = require(script.Parent.DeskPlan)
local RateLimit = require(script.Parent.RateLimit)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local SPOT_NAMES: { [Types.Desk]: string } = { Scanner = "ScannerSpot", Clerk = "ClerkSpot" }
local STANDING_HEIGHT = 3 -- from the floor to the middle of a character
local SIDE_STEP = 2.6 -- between players who share a desk

local DeskService = {}

local roster: { Player } = {} -- everyone in the server, oldest first
local desks: { [Player]: Types.Desk } = {}
local listener: ((Player) -> ())? = nil
local rosterListener: ((number) -> ())? = nil
local characterAdded: { [Player]: RBXScriptConnection } = {}

-- The lone player's rulebook time. Unused while two or more players are present.
local peekOpen = false -- true while a shift is running
local peekLeft = 0
local peekEndsAt = 0 -- server clock time the rulebook closes, or 0 while the timer is stopped
local peekTimer: thread? = nil

local spots: { [Types.Desk]: BasePart } = {}
local warnedAbout: { [Types.Desk]: boolean } = {}

local function findSpot(desk: Types.Desk): BasePart?
	local cached = spots[desk]
	if cached and cached:IsDescendantOf(workspace) then
		return cached
	end
	spots[desk] = nil
	local found = workspace:FindFirstChild(SPOT_NAMES[desk], true)
	if found and found:IsA("BasePart") then
		spots[desk] = found
		return found
	end
	if not warnedAbout[desk] then
		warnedAbout[desk] = true
		warn(
			`No part named "{SPOT_NAMES[desk]}" in Workspace, so players are not moved to that desk.`
		)
	end
	return nil
end

local function isSolo(): boolean
	return #roster == 1
end

-- Whether this player is entitled to what `desk` shows.
function DeskService.sees(player: Player, desk: Types.Desk): boolean
	local own = desks[player]
	return own ~= nil and (isSolo() or own == desk)
end

function DeskService.canStamp(player: Player): boolean
	local own = desks[player]
	return own ~= nil and (isSolo() or own == "Clerk")
end

local function sync(player: Player)
	local desk: Types.Desk? = desks[player]
	if not desk then
		return
	end
	local state: Types.DeskState = {
		desk = desk,
		solo = isSolo(),
		canStamp = DeskService.canStamp(player),
		peekLeft = peekLeft,
		peekEndsAt = peekEndsAt,
	}
	Remotes.DeskSync:FireClient(player, state)
end

local function notify(player: Player)
	if listener then
		listener(player)
	end
end

-- Stands the player's character at their desk and keeps it there.
local function place(player: Player)
	local desk: Types.Desk? = desks[player]
	local character = player.Character
	if not desk or not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpHeight = 0
		humanoid.JumpPower = 0
	end
	local spot = findSpot(desk)
	if not spot then
		return
	end
	-- Players who share a desk stand side by side: centre, right, left.
	local ahead = 0
	for _, other in roster do
		if other == player then
			break
		end
		if desks[other] == desk then
			ahead += 1
		end
	end
	local side = if ahead % 2 == 1 then (ahead + 1) / 2 else -ahead / 2
	character:PivotTo(spot.CFrame * CFrame.new(side * SIDE_STEP, STANDING_HEIGHT, 0))
end

local moveTo: (Player, Types.Desk) -> ()

-- Makes the rulebook timer match the situation. It runs only while a lone player
-- has the rulebook open during a shift. Stopping it banks whatever time is left.
local function refreshPeek()
	if peekTimer then
		task.cancel(peekTimer)
		peekTimer = nil
		peekLeft = math.max(0, peekEndsAt - workspace:GetServerTimeNow())
	end
	peekEndsAt = 0

	local alone = roster[1]
	if not isSolo() or not peekOpen or desks[alone] ~= "Clerk" then
		return
	end
	if peekLeft <= 0 then
		moveTo(alone, "Scanner")
		return
	end
	peekEndsAt = workspace:GetServerTimeNow() + peekLeft
	peekTimer = task.delay(peekLeft, function()
		peekTimer = nil
		peekLeft = 0
		peekEndsAt = 0
		if isSolo() and roster[1] == alone then
			moveTo(alone, "Scanner")
		end
	end)
end

function moveTo(player: Player, desk: Types.Desk)
	desks[player] = desk
	refreshPeek()
	place(player)
	sync(player)
	notify(player)
end

-- Runs after anyone joins or leaves. `countBefore` is how many players there were.
local function settle(countBefore: number)
	DeskPlan.rebalance(roster, desks)
	-- The shift hears about the change straight after the seats are settled and
	-- before anyone is sent anything, so it can deal fresh rules first.
	if rosterListener then
		rosterListener(#roster)
	end
	if isSolo() and countBefore ~= 1 then
		-- Newly alone: a full allowance, not whatever the last lone player left.
		peekLeft = Config.PeekSeconds
	end
	refreshPeek()
	-- Where a player stands depends on who else shares the desk, so place everyone.
	for _, player in roster do
		place(player)
	end
	-- Being alone or not changes what every player may see and do, so tell them all.
	for _, player in roster do
		sync(player)
		notify(player)
	end
end

local function onRequestSwitch(player: Player)
	if not RateLimit.allow(player, "switch") then
		return
	end
	if not isSolo() or roster[1] ~= player or not peekOpen then
		return
	end
	local to: Types.Desk = if desks[player] == "Scanner" then "Clerk" else "Scanner"
	if to == "Clerk" and peekLeft <= 0 then
		return
	end
	moveTo(player, to)
end

local function onPlayerAdded(player: Player)
	if table.find(roster, player) then
		return
	end
	local countBefore = #roster
	table.insert(roster, player)
	characterAdded[player] = player.CharacterAdded:Connect(function(character)
		-- The body arrives a moment after the character does. Wait for it, then
		-- one more step so the spawn point does not move the character back.
		character:WaitForChild("HumanoidRootPart", 10)
		task.wait()
		if player.Character == character then
			place(player)
		end
	end)
	settle(countBefore)
end

local function onPlayerRemoving(player: Player)
	local index = table.find(roster, player)
	if not index then
		return
	end
	local countBefore = #roster
	table.remove(roster, index)
	desks[player] = nil
	local connection = characterAdded[player]
	if connection then
		connection:Disconnect()
		characterAdded[player] = nil
	end
	settle(countBefore)
end

-- A new parcel, or a new shift, gives the lone player a full allowance again.
function DeskService.openPeek()
	if peekTimer then
		task.cancel(peekTimer)
		peekTimer = nil
	end
	peekOpen = true
	peekLeft = Config.PeekSeconds
	refreshPeek()
	if isSolo() then
		sync(roster[1])
	end
end

-- The shift is over: close the rulebook and send the lone player back to the X-ray.
function DeskService.closePeek()
	peekOpen = false
	refreshPeek()
	if isSolo() then
		local alone = roster[1]
		if desks[alone] == "Clerk" then
			moveTo(alone, "Scanner")
		else
			sync(alone)
		end
	end
end

-- `onChange` is called for a player whenever what they may see could have changed.
-- `onRoster` is called with the new player count whenever someone joins or leaves,
-- before any `onChange` call that the same join or leave causes.
function DeskService.start(onChange: (Player) -> (), onRoster: (number) -> ())
	listener = onChange
	rosterListener = onRoster
	Remotes.RequestSwitch.OnServerEvent:Connect(onRequestSwitch)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return DeskService
