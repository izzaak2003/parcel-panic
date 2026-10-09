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
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

if RunService:IsRunning() then
	error("tests/Simulate is a development tool and must not run in a live game or a playtest")
end

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
local dealSeenBy = {}
local function remote(name)
	local self = { Name = name, OnServerEvent = signal() }
	-- Each entry also notes which rulebook was in force for that player when it
	-- was sent, going by the last public state they were given.
	local function record(player, args)
		if name == "ShiftSync" then
			dealSeenBy[player.Name] = args[1].deal
		end
		table.insert(
			sent,
			{ to = player.Name, remote = name, args = args, deal = dealSeenBy[player.Name] }
		)
	end
	function self:FireClient(player, ...)
		record(player, table.pack(...))
	end
	function self:FireAllClients(...)
		for _, player in players.list do
			record(player, table.pack(...))
		end
	end
	return self
end

local remotes = {}
for _, child in ReplicatedStorage.Remotes:GetChildren() do
	remotes[child.Name] = remote(child.Name)
end

-- Short delays so a scenario takes a fraction of a second.
local quick = {
	ShiftSeconds = 60,
	ShiftStartDelay = 0.05,
	FirstParcelDelay = 0.05,
	ParcelGap = 0.05,
	RequestCooldown = 0,
	PeekSeconds = 0.4,
	PingBurst = 1000, -- lowered to the real value where the limit itself is tested
	StampParcels = 2,
	OddChance = 0, -- raised to 1 where the odd parcel is tested
	SaveBackoff = 0.02,
	SaveGap = 0, -- raised where the gap between saves is tested
	AutosaveSeconds = 100000, -- saving is triggered by hand in these tests
	ShutdownSeconds = 3,
}

-- A stand-in for Roblox's data store that can be told to fail or be slow.
local function deepCopy(value)
	if typeof(value) ~= "table" then
		return value
	end
	local result = {}
	for key, inner in value do
		result[key] = deepCopy(inner)
	end
	return result
end
local saved = {} -- what is "stored", by key
local storeLog = { gets = 0, updates = 0, overlapped = false }
local storeFaults = { gets = 0, updates = 0, delay = 0, landThenFail = 0, runTwice = 0 } -- how many coming calls fail; seconds each call takes
local updatesInFlight = {}
local fakeStore = {}
function fakeStore:GetAsync(key)
	storeLog.gets += 1
	if storeFaults.delay > 0 then
		task.wait(storeFaults.delay)
	end
	if storeFaults.gets > 0 then
		storeFaults.gets -= 1
		error("fake data store: GetAsync failed")
	end
	return deepCopy(saved[key])
end
function fakeStore:UpdateAsync(key, transform)
	storeLog.updates += 1
	updatesInFlight[key] = (updatesInFlight[key] or 0) + 1
	if updatesInFlight[key] > 1 then
		storeLog.overlapped = true
	end
	if storeFaults.delay > 0 then
		task.wait(storeFaults.delay)
	end
	updatesInFlight[key] -= 1
	if storeFaults.updates > 0 then
		storeFaults.updates -= 1
		error("fake data store: UpdateAsync failed")
	end
	-- The real store may run the function more than once before it settles.
	if storeFaults.runTwice > 0 then
		storeFaults.runTwice -= 1
		transform(deepCopy(saved[key]))
	end
	local result = transform(deepCopy(saved[key]))
	if result ~= nil then
		saved[key] = deepCopy(result)
	end
	-- The write happened, but the caller is told it did not.
	if storeFaults.landThenFail > 0 then
		storeFaults.landThenFail -= 1
		error("fake data store: UpdateAsync landed, then reported failure")
	end
	return result
end
local closers = {} -- functions the game asked to run when the server closes

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
	elseif name == "DataStoreService" then
		return {
			GetDataStore = function()
				return fakeStore
			end,
		}
	end
	return game:GetService(name)
end
function fakeGame:BindToClose(closer)
	table.insert(closers, closer)
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

-- The game's own settings, with the short delays laid over them. Config is
-- frozen, so this is a copy the tests can also change as they go.
local realConfig = load("Config")
loaded.Config = nil
local config = table.clone(realConfig)
for key, value in quick do
	config[key] = value
end
stubs.Config = config

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
local function lastEntry(to, remoteName)
	for index = #sent, 1, -1 do
		local entry = sent[index]
		if entry.to == to and entry.remote == remoteName then
			return entry
		end
	end
	return nil
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
	for _, player in players.list do
		local own = desk(player.Name)
		local state = shift(player.Name)
		if own and state and state.phase == "Running" then
			if own.desk == "Scanner" then
				local entry = lastEntry(player.Name, "RulebookShown")
				check(
					when .. ": Scanner " .. player.Name .. " does not hold the rulebook in force",
					entry == nil or entry.deal ~= state.deal
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
local function join(name, userId)
	nextId += 1
	local player = {
		Name = name,
		UserId = userId or nextId,
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

local PlayerData = load("PlayerData")
PlayerData.start()
load("ShiftService").start()
load("PingService").start()

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

section("the ping board in a pair")
local function ping(player, stampId, choice)
	local seen = shift(player.Name)
	remotes.SendPing.OnServerEvent:Fire(player, stampId, seen.deal, seen.parcelSeq, choice)
end
local function lastPing(name)
	local args = last(name, "PingShown")
	return args and args[1]
end
local inside = last("A", "ParcelScanned")[2]
m = mark()
ping(a, "colour")
check(
	"the Scanner's colour stamp reaches both players with the parcel's true colour",
	count("A", "PingShown", m) == 1
		and count("B", "PingShown", m) == 1
		and lastPing("B").from == "Scanner"
		and lastPing("B").value == inside.colour
)
ping(a, "handle")
check("the handle stamp carries the true number of handles", lastPing("B").value == inside.handles)
ping(a, "shape")
check("the shape stamp carries the true shape", lastPing("B").value == inside.shape)
m = mark()
ping(b, "colour")
check(
	"the Clerk's colour stamp is a question with no value",
	count("A", "PingShown", m) == 1 and lastPing("A").from == "Clerk" and lastPing("A").value == nil
)
m = mark()
ping(b, "rule", 2)
check(
	"the Clerk's rule stamp shows the rule at that place in the rulebook",
	lastPing("A").ruleId == currentRules()[1][2]
)
m = mark()
for _, bad in { 0, 4, 1.5, 0 / 0, math.huge, "2", {} } do
	ping(b, "rule", bad)
end
ping(b, "rule")
check("a rule stamp naming no real rule is ignored", count("A", "PingShown", m) == 0)
m = mark()
ping(a, "rule", 1)
check(
	"the Scanner's rule stamp is a question and shows no rule",
	count("B", "PingShown", m) == 1 and lastPing("B").ruleId == nil
)
m = mark()
ping(a, "nonsense")
ping(a, 42)
ping(a)
check("an unknown stamp is ignored", count("A", "PingShown", m) == 0)

-- A stamp says which rulebook and parcel the player was looking at.
local looking = shift("A")
m = mark()
remotes.SendPing.OnServerEvent:Fire(a, "check", looking.deal - 1, looking.parcelSeq)
check("a stamp pressed under an earlier rulebook is dropped", count("B", "PingShown", m) == 0)
remotes.SendPing.OnServerEvent:Fire(a, "colour", looking.deal, looking.parcelSeq - 1)
check("a trait stamp about an earlier parcel is dropped", count("B", "PingShown", m) == 0)
remotes.SendPing.OnServerEvent:Fire(a, "check", looking.deal, looking.parcelSeq - 1)
check("a plain stamp about an earlier parcel is dropped", count("B", "PingShown", m) == 0)
remotes.SendPing.OnServerEvent:Fire(b, "rule", looking.deal, looking.parcelSeq - 1, 1)
check(
	"a rule stamp is not tied to a parcel, and says which rulebook and parcel it was sent under",
	count("A", "PingShown", m) == 1
		and lastPing("A").deal == looking.deal
		and lastPing("A").parcelSeq == looking.parcelSeq
)
m = mark()
remotes.SendPing.OnServerEvent:Fire(a, "colour", looking.deal, "x")
remotes.SendPing.OnServerEvent:Fire(a, "colour")
check(
	"a stamp that does not say what the player was looking at is dropped",
	count("B", "PingShown", m) == 0
)

m = mark()
ping(a, "check")
ping(b, "hurry")
check("plain stamps go through from either desk", count("A", "PingShown", m) == 2)
stamp(b, shift("B").parcelSeq, rightVerdict())
m = mark()
ping(a, "colour")
check(
	"with no parcel on the desk the Scanner's trait stamp is ignored",
	count("B", "PingShown", m) == 0
)
settleDown()

-- The limit on stamps, at the game's real settings: a short run, then a trickle.
config.PingBurst = realConfig.PingBurst
m = mark()
for _ = 1, 12 do
	ping(b, "hurry")
end
check(
	"twelve stamps at once: only the allowed run gets through",
	count("A", "PingShown", m) == realConfig.PingBurst,
	count("A", "PingShown", m) .. " of 12, allowance " .. realConfig.PingBurst
)
task.wait(1 / realConfig.PingPerSecond + 0.15)
m = mark()
for _ = 1, 5 do
	ping(b, "hurry")
end
check(
	"a second later, one more is allowed",
	count("A", "PingShown", m) == 1,
	count("A", "PingShown", m) .. " of 5"
)
config.PingBurst = quick.PingBurst
settleDown()

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
m = mark()
ping(c, "check")
ping(c, "colour")
check("a lone player's stamps go nowhere", count("C", "PingShown", m) == 0)

leave(c)

section("the rule of the day, the odd parcel, and saved progress")
local Calendar = load("Calendar")
local ParcelDefs = load("ParcelDefs")
local function keyOf(player)
	return "u_" .. player.UserId
end
local function progress(name)
	local args = last(name, "ProgressSync")
	return args and args[1]
end
local function size(list)
	local total = 0
	for _ in list do
		total += 1
	end
	return total
end
-- Every stamp a player has, counting filled cards.
local function stampsOf(name)
	local shown = progress(name)
	return shown.licence.cards * shown.licenceSlots + shown.licence.stamps
end
-- Handles so many parcels correctly in the running shift, alone.
local function handle(player, right)
	for _ = 1, right do
		settleDown()
		stamp(player, shift(player.Name).parcelSeq, rightVerdict())
		task.wait(0.02)
	end
end
-- Ends the running shift with mistakes.
local function strikeOut(player)
	for _ = 1, 10 do
		settleDown()
		if shift(player.Name).phase ~= "Running" then
			break
		end
		stamp(
			player,
			shift(player.Name).parcelSeq,
			if rightVerdict() == "Ship" then "Return" else "Ship"
		)
		task.wait(0.02)
	end
end
local function newShift(player)
	strikeOut(player)
	remotes.RequestShift.OnServerEvent:Fire(player)
	settleDown()
end

local d = join("D")
settleDown()
check(
	"a new player starts with one free stamp and is told progress is being saved",
	progress("D") ~= nil and stampsOf("D") == 1 and progress("D").saving == true
)

newShift(d)
local today = Calendar.today()
check(
	"the rule of the day is public, is the first rule in the book, and follows from the date",
	shift("D").dailyRuleId == currentRules()[1][1]
		and shift("D").dailyRuleId == Rulebook.daily(today).id
)
handle(d, config.StampParcels - 1)
check("one parcel short of the mark earns no stamp", stampsOf("D") == 1)
handle(d, 1)
check("the stamp is earned the moment the player has handled enough", stampsOf("D") == 2)
check("what was handled correctly goes in the collection book", size(progress("D").collection) >= 1)
task.wait(0.1)
check("earning a stamp is saved", saved[keyOf(d)] ~= nil and saved[keyOf(d)].licence.stamps == 2)
handle(d, config.StampParcels)
check("handling more on the same day earns no second stamp", stampsOf("D") == 2)
newShift(d)
handle(d, config.StampParcels)
check("nor does a second shift on the same day", stampsOf("D") == 2)

config.DayOffset += 1
newShift(d)
check(
	"the next day has its own rule of the day",
	shift("D").dailyRuleId == Rulebook.daily(today + 1).id
)
handle(d, config.StampParcels)
check("the next day earns another stamp", stampsOf("D") == 3)

config.OddChance = 1
newShift(d)
settleDown()
local oddSeen = last("D", "ParcelScanned")[2]
check("the odd parcel turns up", ParcelDefs.ItemsById[oddSeen.item].odd == true, oddSeen.item)
stamp(d, shift("D").parcelSeq, rightVerdict())
task.wait(0.05)
check(
	"handled correctly, it goes in the collection book",
	progress("D").collection[oddSeen.item] == true
)
config.OddChance = quick.OddChance

local dId = d.UserId
leave(d)
settleDown()
d = join("D", dId)
settleDown()
check(
	"coming back loads what was saved",
	progress("D").saving and stampsOf("D") == 3 and progress("D").collection[oddSeen.item] == true
)

-- Days far in the future, so each call below earns a stamp whatever came before.
local farDay = today + 1000
local function nextDay()
	farDay += 1
	return farDay
end

-- Another server saved in the meantime.
local key = keyOf(d)
saved[key].collection.trophy = true
saved[key].collection.candle = true
saved[key].licence = { stamps = 2, cards = 1, lastStampDay = saved[key].licence.lastStampDay }
PlayerData.stamp(d, nextDay())
task.wait(0.1)
check(
	"a save adds to what another server stored and never replaces it",
	saved[key].collection.trophy == true
		and saved[key].collection.candle == true
		and saved[key].collection[oddSeen.item] == true
		and saved[key].licence.cards == 1
)
check(
	"the player is then shown the combined progress",
	progress("D").licence.cards == 1 and progress("D").collection.trophy == true
)

local stampsNow = stampsOf("D")
storeFaults.updates = 2
local updatesBefore = storeLog.updates
PlayerData.stamp(d, nextDay())
task.wait(0.3)
check(
	"a save that fails is tried again until it works",
	storeLog.updates - updatesBefore == 3
		and saved[key].licence.cards * 6 + saved[key].licence.stamps == stampsNow + 1,
	(storeLog.updates - updatesBefore) .. " calls"
)

storeFaults.delay = 0.1
storeLog.overlapped = false
PlayerData.stamp(d, nextDay())
PlayerData.stamp(d, nextDay())
PlayerData.stamp(d, nextDay())
task.wait(0.7)
storeFaults.delay = 0
check(
	"three saves asked for at once run one after another and lose nothing",
	not storeLog.overlapped
		and saved[key].licence.cards * 6 + saved[key].licence.stamps == stampsNow + 4,
	"stored "
		.. (saved[key].licence.cards * 6 + saved[key].licence.stamps)
		.. ", expected "
		.. (stampsNow + 4)
)

-- Fill the card, then one more.
while progress("D").licence.stamps < 6 do
	PlayerData.stamp(d, nextDay())
end
local cardsBefore = progress("D").licence.cards
PlayerData.stamp(d, nextDay())
check(
	"a stamp on a full card starts a new card",
	progress("D").licence.cards == cardsBefore + 1 and progress("D").licence.stamps == 1
)
task.wait(0.1)

-- A write that lands but is reported as failed, and a write whose function runs twice.
storeFaults.landThenFail = 1
PlayerData.stamp(d, nextDay())
task.wait(0.2)
local afterLanded = saved[key].licence.cards * 6 + saved[key].licence.stamps
storeFaults.runTwice = 1
PlayerData.stamp(d, nextDay())
task.wait(0.2)
check(
	"a save that landed but reported failure, and one run twice, each count once",
	afterLanded == stampsOf("D") - 1
		and saved[key].licence.cards * 6 + saved[key].licence.stamps == stampsOf("D"),
	"stored "
		.. (saved[key].licence.cards * 6 + saved[key].licence.stamps)
		.. ", shown "
		.. stampsOf("D")
)

-- With a gap required between saves, a second award waits for the autosave or for leaving.
config.SaveGap = 15
updatesBefore = storeLog.updates
PlayerData.stamp(d, nextDay())
task.wait(0.1)
check("a stamp just after a save is not written at once", storeLog.updates == updatesBefore)
local owedStamps = stampsOf("D")
leave(d)
task.wait(0.1)
check(
	"but leaving writes it",
	saved[key].licence.cards * 6 + saved[key].licence.stamps == owedStamps
)
config.SaveGap = quick.SaveGap

storeFaults.gets = 100000
local e = join("E")
task.wait(0.5)
check(
	"a player whose data will not load plays on with a fresh card and is told it is not being saved",
	progress("E") ~= nil and progress("E").saving == false and stampsOf("E") == 1
)
updatesBefore = storeLog.updates
PlayerData.collect(e, "ball")
PlayerData.stamp(e, nextDay())
task.wait(0.1)
leave(e)
task.wait(0.1)
check(
	"and is never saved, so a fresh card cannot overwrite real data",
	storeLog.updates == updatesBefore and saved[keyOf(e)] == nil
)
storeFaults.gets = 0

saved.u_777 = {
	version = 1,
	licence = { stamps = 4, cards = 0, lastStampDay = 5 },
	collection = { ball = true },
}
storeFaults.gets = 2
join("F", 777)
task.wait(0.3)
check(
	"a load that fails twice and then works is used",
	progress("F").saving == true and stampsOf("F") == 4 and progress("F").collection.ball == true
)

storeFaults.delay = 0.3
local g = join("G")
task.wait(0.05)
leave(g)
task.wait(0.5)
storeFaults.delay = 0
check(
	"a player who leaves while their data is loading is sent nothing and saves nothing",
	count("G", "ProgressSync") == 0 and saved[keyOf(g)] == nil
)

saved.u_888 = {
	licence = { stamps = "lots", cards = -5, lastStampDay = 0 / 0 },
	collection = { nope = true, ball = "yes", teapot = true },
}
local h = join("H", 888)
saved.u_889 = "garbage"
join("I", 889)
task.wait(0.1)
local repaired = progress("H")
check(
	"damaged stored data is repaired field by field, not trusted",
	repaired.saving
		and repaired.licence.stamps == 1
		and repaired.licence.cards == 0
		and repaired.licence.lastStampDay == 0
		and repaired.collection.teapot == true
		and repaired.collection.nope == nil
		and repaired.collection.ball == nil
)
check(
	"stored data that is not a save at all gives a fresh card",
	stampsOf("I") == 1 and progress("I").saving
)

-- A date in the future must not lock a player out of stamps.
saved.u_891 =
	{ version = 1, licence = { stamps = 2, cards = 0, lastStampDay = 10 ^ 9 }, collection = {} }
local l = join("L", 891)
task.wait(0.1)
PlayerData.stamp(l, Calendar.today())
check(
	"a stored date in the future is thrown away, so today's stamp can still be earned",
	stampsOf("L") == 3
)

-- Saved by a newer version of the game: shown, never written.
saved.u_890 = {
	version = 99,
	licence = { stamps = 5, cards = 0, lastStampDay = 1 },
	collection = { ball = true },
	somethingNew = "kept",
}
local j = join("J", 890)
task.wait(0.1)
check(
	"data from a newer version of the game is shown but marked as not being saved",
	stampsOf("J") == 5 and progress("J").saving == false
)
PlayerData.collect(j, "teapot")
leave(j)
task.wait(0.1)
check(
	"and is left exactly as it was",
	saved.u_890.version == 99
		and saved.u_890.somethingNew == "kept"
		and saved.u_890.collection.teapot == nil
)

-- A player leaves while the store is down, then the server closes.
local k = join("K", 892)
task.wait(0.1)
PlayerData.collect(k, "ball")
storeFaults.updates = config.SaveAttempts
leave(k)
task.wait(0.4)
check(
	"a save on leaving that fails every try is not lost track of",
	saved.u_892 == nil or saved.u_892.collection.ball == nil
)

PlayerData.collect(h, "lantern")
storeFaults.delay = 0.1
local closed = false
for _, closer in closers do
	task.spawn(function()
		closer()
		closed = true
	end)
end
task.wait(1.2)
storeFaults.delay = 0
check(
	"closing the server saves unsaved progress and waits for it to finish",
	closed and saved.u_888 ~= nil and saved.u_888.collection.lantern == true
)
check(
	"and writes what the departed player was owed",
	saved.u_892 ~= nil and saved.u_892.collection.ball == true
)
check(
	"an item id this version does not know survives a save",
	saved.u_888.collection.nope == true and saved.u_888.collection.teapot == true
)

table.insert(lines, ("%d checks, %d failed, %d messages sent"):format(checks, failures, #sent))
return table.concat(lines, "\n")
