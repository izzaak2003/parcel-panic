-- Runs the real server modules against made-up players, to check who is sent
-- what when people join and leave. Studio's playtest through MCP has one client,
-- so this is the only way to exercise two or more players without a person.
--
-- How to run, in Studio's Edit mode with Rojo connected (through the MCP
-- `execute_luau` tool, or Studio's command bar with `print` in place of `return`):
--
--     return require(game.ServerScriptService.Tests.Simulate:Clone())
--
-- It reads each module's Source from ServerScriptService and ReplicatedStorage,
-- loads it with fake Players and fake remotes, and returns a report. Nothing in
-- the place is changed.
--
-- This is not game code. Rojo puts it in ServerScriptService, which clients never
-- receive, and nothing in the game requires it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local function signal()
	local handlers = {}
	local self = {}
	function self:Connect(fn)
		table.insert(handlers, fn)
		local connection = {}
		function connection:Disconnect()
			local index = table.find(handlers, fn)
			if index then
				table.remove(handlers, index)
			end
		end
		return connection
	end
	function self:Fire(...)
		for _, fn in table.clone(handlers) do
			fn(...)
		end
	end
	return self
end

-- Fake Players service and fake players.
local players = { list = {}, PlayerAdded = signal(), PlayerRemoving = signal() }
function players:GetPlayers()
	return table.clone(self.list)
end

-- Everything the server sends lands here, in order.
local sent = {}
local function remote(name)
	local self = { Name = name, OnServerEvent = signal() }
	function self:FireClient(player, ...)
		table.insert(sent, { to = player.Name, remote = name, args = table.pack(...) })
	end
	function self:FireAllClients(...)
		for _, player in players.list do
			table.insert(sent, { to = player.Name, remote = name, args = table.pack(...) })
		end
	end
	return self
end

local remotes = {}
for _, child in ReplicatedStorage.Remotes:GetChildren() do
	remotes[child.Name] = remote(child.Name)
end

-- Short delays so a scenario takes a fraction of a second.
local config = {
	ShiftSeconds = 60,
	MaxStrikes = 3,
	RulesPerShift = 3,
	ShiftStartDelay = 0.05,
	FirstParcelDelay = 0.05,
	ParcelGap = 0.05,
	ReturnChance = 0.5,
	RequestCooldown = 0,
	PeekSeconds = 0.4,
	PingCooldown = 0,
}

-- Module loader: `script.Parent.X` and `ReplicatedStorage.Shared.X` both become
-- the name "X", and `require` loads that module's Source with fake services.
local names = setmetatable({}, {
	__index = function(_, key)
		return key
	end,
})
local fakeGame = {}
function fakeGame:GetService(name)
	if name == "Players" then
		return players
	elseif name == "ReplicatedStorage" then
		return { Shared = names }
	end
	return game:GetService(name)
end

local sources = {}
for _, module in ServerScriptService.Server:GetChildren() do
	sources[module.Name] = module.Source
end
for _, module in ReplicatedStorage.Shared:GetChildren() do
	sources[module.Name] = module.Source
end

local stubs = {
	Remotes = remotes,
	Config = config,
	ParcelProp = { show = function() end, hide = function() end },
}
local loaded = {}
local function load(name)
	if stubs[name] then
		return stubs[name]
	end
	if loaded[name] == nil then
		local source = sources[name]
		assert(source, "no module named " .. tostring(name))
		local chunk, problem = loadstring(source, name)
		assert(chunk, problem)
		setfenv(
			chunk,
			setmetatable(
				{ game = fakeGame, script = { Parent = names }, require = load },
				{ __index = getfenv() }
			)
		)
		loaded[name] = chunk()
	end
	return loaded[name]
end

local RuleDefs = load("RuleDefs")
local Rulebook = load("Rulebook")

-- Report.
local lines, failures, checks = {}, 0, 0
local function check(what, ok, detail)
	checks += 1
	if not ok then
		failures += 1
	end
	table.insert(
		lines,
		(if ok then "PASS " else "FAIL ") .. what .. (if detail then "  [" .. detail .. "]" else "")
	)
end
local function section(title)
	table.insert(lines, "-- " .. title)
end

-- Reading the log.
local function mark()
	return #sent
end
local function count(to, remoteName, from)
	local total = 0
	for index = (from or 0) + 1, #sent do
		local entry = sent[index]
		if entry.to == to and entry.remote == remoteName then
			total += 1
		end
	end
	return total
end
local function last(to, remoteName)
	for index = #sent, 1, -1 do
		local entry = sent[index]
		if entry.to == to and entry.remote == remoteName then
			return entry.args
		end
	end
	return nil
end
local function desk(name)
	local args = last(name, "DeskSync")
	return args and args[1]
end
local function shift(name)
	local args = last(name, "ShiftSync")
	return args and args[1]
end
local function rulesKey(args)
	return args and table.concat(args[1], ",") or "none"
end

-- The rulebook in force is the last one sent to anybody.
local function currentRules()
	for index = #sent, 1, -1 do
		if sent[index].remote == "RulebookShown" then
			return sent[index].args
		end
	end
	return nil
end

-- With the desks split, nobody at the Scanner desk may hold the rulebook in force,
-- and nobody at the Clerk desk may hold what is inside the parcel on the desk.
local function checkSplit(when)
	if #players.list < 2 then
		return
	end
	local rules = rulesKey(currentRules())
	for _, player in players.list do
		local own = desk(player.Name)
		local state = shift(player.Name)
		if own and state and state.phase == "Running" then
			if own.desk == "Scanner" then
				local holds = rulesKey(last(player.Name, "RulebookShown"))
				check(
					when .. ": Scanner " .. player.Name .. " does not hold the rulebook in force",
					holds ~= rules
				)
			else
				local scan = last(player.Name, "ParcelScanned")
				local holdsParcel = scan ~= nil
					and state.parcelSeq > 0
					and scan[1] == state.parcelSeq
				check(
					when .. ": Clerk " .. player.Name .. " does not hold the parcel on the desk",
					not holdsParcel
				)
			end
		end
	end
end

-- Acting as players.
local nextId = 0
local function join(name)
	nextId += 1
	local player = {
		Name = name,
		UserId = nextId,
		Parent = players,
		Character = nil,
		CharacterAdded = signal(),
	}
	table.insert(players.list, player)
	players.PlayerAdded:Fire(player)
	return player
end
local function leave(player)
	players.PlayerRemoving:Fire(player)
	table.remove(players.list, table.find(players.list, player))
	player.Parent = nil
end
local function stamp(player, seq, verdict)
	remotes.SubmitVerdict.OnServerEvent:Fire(player, seq, verdict)
end
local function settleDown()
	task.wait(0.25)
end

-- The right verdict, worked out from what the server sent to the two desks.
local function rightVerdict()
	local rules = {}
	for _, id in currentRules()[1] do
		table.insert(rules, RuleDefs.ById[id])
	end
	for index = #sent, 1, -1 do
		if sent[index].remote == "ParcelScanned" then
			return Rulebook.judge(rules, sent[index].args[2])
		end
	end
	return "Ship"
end

load("ShiftService").start()

section("one player")
local a = join("A")
settleDown()
check(
	"A is alone at the Scanner desk and may stamp",
	desk("A").desk == "Scanner" and desk("A").solo and desk("A").canStamp
)
check(
	"A, alone, is sent the rulebook and the parcel",
	count("A", "RulebookShown") >= 1 and count("A", "ParcelScanned") >= 1
)
check(
	"the shift is running with a parcel on the desk",
	shift("A").phase == "Running" and shift("A").parcelSeq > 0
)

section("a second player joins the lone player")
local seqBefore = shift("A").parcelSeq
local m = mark()
local b = join("B")
settleDown()
check(
	"B is seated at the Clerk desk",
	desk("B").desk == "Clerk" and not desk("B").solo and desk("B").canStamp
)
check(
	"A is told the desks are split and can no longer stamp",
	not desk("A").solo and not desk("A").canStamp
)
check(
	"the parcel on the desk was replaced",
	shift("A").parcelSeq > seqBefore,
	"was " .. seqBefore .. ", now " .. shift("A").parcelSeq
)
check(
	"after the join the rulebook goes to B only",
	count("B", "RulebookShown", m) >= 1 and count("A", "RulebookShown", m) == 0
)
check(
	"after the join the parcel goes to A only",
	count("A", "ParcelScanned", m) >= 1 and count("B", "ParcelScanned", m) == 0
)
checkSplit("pair")

section("who may stamp in a pair")
m = mark()
stamp(a, shift("A").parcelSeq, "Ship")
task.wait(0.05)
check("a verdict from the Scanner is ignored", count("A", "VerdictJudged", m) == 0)
local right = rightVerdict()
stamp(b, shift("B").parcelSeq, right)
task.wait(0.05)
local judged = last("B", "VerdictJudged")
check(
	"a verdict from the Clerk is judged, and judged right",
	count("B", "VerdictJudged", m) == 1 and judged[3] == true
)
settleDown()
check(
	"the next parcel again goes to A only",
	count("A", "ParcelScanned", m) >= 1 and count("B", "ParcelScanned", m) == 0
)
checkSplit("pair, next parcel")

section("the Clerk leaves, then comes back")
m = mark()
seqBefore = shift("A").parcelSeq
leave(b)
settleDown()
check("A is alone again and may stamp", desk("A").solo and desk("A").canStamp)
check("A, now alone, is sent the rulebook", count("A", "RulebookShown", m) >= 1)
check("nothing was dealt again for a lone player", shift("A").parcelSeq == seqBefore)
m = mark()
b = join("B")
settleDown()
check("B is back at the Clerk desk", desk("B").desk == "Clerk")
check("the parcel was replaced on the rejoin", shift("A").parcelSeq > seqBefore)
check("A gets no rulebook after the rejoin", count("A", "RulebookShown", m) == 0)
checkSplit("pair after a rejoin")

section("a third player joins")
m = mark()
seqBefore = shift("A").parcelSeq
local c = join("C")
settleDown()
check("C doubles up at the Scanner desk", desk("C").desk == "Scanner" and not desk("C").canStamp)
check("the parcel was replaced", shift("A").parcelSeq > seqBefore)
check(
	"the rulebook goes to B only",
	count("B", "RulebookShown", m) >= 1
		and count("A", "RulebookShown", m) == 0
		and count("C", "RulebookShown", m) == 0
)
check(
	"the parcel goes to both Scanners and not the Clerk",
	count("A", "ParcelScanned", m) >= 1
		and count("C", "ParcelScanned", m) >= 1
		and count("B", "ParcelScanned", m) == 0
)
checkSplit("three")

section("the only Clerk of three leaves, then rejoins")
m = mark()
seqBefore = shift("A").parcelSeq
leave(b)
settleDown()
check(
	"C, the newest, is moved to the Clerk desk and may stamp",
	desk("C").desk == "Clerk" and desk("C").canStamp
)
check("A stays at the Scanner desk", desk("A").desk == "Scanner" and not desk("A").canStamp)
check("the parcel C had seen was replaced", shift("A").parcelSeq > seqBefore)
check(
	"the new parcel goes to A only",
	count("A", "ParcelScanned", m) >= 1 and count("C", "ParcelScanned", m) == 0
)
check(
	"the new rulebook goes to C only",
	count("C", "RulebookShown", m) >= 1 and count("A", "RulebookShown", m) == 0
)
checkSplit("three minus the Clerk")
m = mark()
seqBefore = shift("A").parcelSeq
b = join("B")
settleDown()
check("B returns to the Scanner desk this time", desk("B").desk == "Scanner")
check("the parcel was replaced again", shift("A").parcelSeq > seqBefore)
check("B is sent no rulebook", count("B", "RulebookShown", m) == 0)
checkSplit("three after the rejoin")

section("three mistakes end the shift; anyone may start the next")
for _ = 1, 3 do
	settleDown()
	local wrong = if rightVerdict() == "Ship" then "Return" else "Ship"
	stamp(c, shift("C").parcelSeq, wrong)
end
task.wait(0.05)
check(
	"the shift ended on three mistakes",
	shift("A").phase == "Ended" and shift("A").endReason == "StruckOut" and shift("A").strikes == 3
)
m = mark()
remotes.RequestShift.OnServerEvent:Fire(a)
settleDown()
check("a new shift is running", shift("B").phase == "Running" and shift("B").strikes == 0)
check(
	"its rulebook goes to the Clerk only",
	count("C", "RulebookShown", m) >= 1
		and count("A", "RulebookShown", m) == 0
		and count("B", "RulebookShown", m) == 0
)
checkSplit("new shift")

section("everyone but one leaves; the lone player's rulebook time")
leave(b)
leave(a)
settleDown()
check("C is alone and may stamp", desk("C").solo and desk("C").canStamp)
if desk("C").desk == "Clerk" then
	task.wait(config.PeekSeconds + 0.2)
	check(
		"C, left alone at the rulebook, is sent back when the time runs out",
		desk("C").desk == "Scanner"
	)
end
settleDown()
stamp(c, shift("C").parcelSeq, "Ship")
settleDown()
check("a new parcel refills the rulebook time", desk("C").peekLeft > config.PeekSeconds - 0.01)
remotes.RequestSwitch.OnServerEvent:Fire(c)
task.wait(0.05)
check("C can open the rulebook", desk("C").desk == "Clerk" and desk("C").peekEndsAt > 0)
task.wait(config.PeekSeconds + 0.2)
check(
	"C is sent back when the time runs out",
	desk("C").desk == "Scanner" and desk("C").peekLeft == 0
)
remotes.RequestSwitch.OnServerEvent:Fire(c)
task.wait(0.05)
check("a further switch is refused until the next parcel", desk("C").desk == "Scanner")

leave(c)
table.insert(lines, ("%d checks, %d failed, %d messages sent"):format(checks, failures, #sent))
return table.concat(lines, "\n")
