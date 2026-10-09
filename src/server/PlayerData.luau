--!strict
-- Each player's saved progress: the postal licence and the collection book.
--
-- How it stays safe:
--   * A player whose data failed to load is never saved. They play on with a
--     fresh card that exists only for this visit, and are told so. Saving
--     defaults over real data is the one mistake that cannot be undone.
--   * Every save reads what is stored and merges into it, never replaces it.
--     If the player has already joined another server and earned something
--     there, neither server's save can undo the other's.
--   * Data written by a newer version of the game is left alone, and things in
--     it that this version does not recognise are kept, so an old server
--     cannot erase what a new one saved.
--   * One save at a time per player. A second request made while one is running
--     waits and then runs once.
--   * Leaving saves. If that save fails, the progress is kept and tried again.
--     Closing the server saves everyone at once, with a deadline.
--
-- One known gap: the licence that is further along wins a merge. If two servers
-- each add a stamp on different days from the same starting point before either
-- has saved, one of those stamps is lost. That needs a save to be outstanding
-- across midnight UTC (seconds normally, minutes if the store is failing) while
-- the player earns again elsewhere, and it costs one stamp.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Calendar = require(script.Parent.Calendar)
local Config = require(script.Parent.Config)
local ParcelDefs = require(ReplicatedStorage.Shared.ParcelDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

-- Studio playtests get a store of their own, so test settings can never touch
-- what real players have earned.
local STORE_NAME = if RunService:IsStudio() then "PlayerData_Studio" else "PlayerData"
local VERSION = 1
local MAX_UNKNOWN = 200 -- ids this version does not know that it will still carry
local MAX_ID_LENGTH = 40
local GIVE_UP_ROUNDS = 10 -- failed saves in a row before a departed player's progress is dropped

type Session = {
	owner: Player,
	key: string,
	data: Types.PlayerSave, -- what was stored plus what this visit has added
	loaded: boolean, -- the stored data was read, so it is safe to write back
	ready: boolean, -- loading has finished, one way or the other
	dirty: boolean, -- something changed since the last save
	saving: boolean,
	again: boolean, -- a save was asked for while one was running
	departed: boolean, -- the player has left the server
	failedRounds: number, -- saves in a row that used up every try
	savedAt: number, -- when the last save succeeded, by os.clock
}

local PlayerData = {}

local store: DataStore? = nil
local sessions: { [Player]: Session } = {}
-- Players who have left with progress that could not be saved yet.
local stranded: { [Session]: boolean } = {}
local savesRunning = 0
local closing = false

local function fresh(): Types.PlayerSave
	return {
		version = VERSION,
		-- The first stamp is a gift, so the card never starts empty.
		licence = { stamps = 1, cards = 0, lastStampDay = 0 },
		collection = {},
	}
end

local function copy(save: Types.PlayerSave): Types.PlayerSave
	return {
		version = save.version,
		licence = table.clone(save.licence),
		collection = table.clone(save.collection),
	}
end

local function wholeNumber(value: any, least: number, most: number, otherwise: number): number
	if typeof(value) ~= "number" or value ~= value then
		return otherwise
	end
	return math.clamp(math.floor(value), least, most)
end

-- Whether this was written by a later version of the game than this one.
local function isNewer(stored: any): boolean
	return typeof(stored) == "table"
		and typeof(stored.version) == "number"
		and stored.version > VERSION
end

-- Turns whatever was stored into a well-formed save. Stored data is not trusted:
-- an older version, a bug, or a manual edit may have left anything there, which
-- is why it arrives typed as `any` and every field is checked before use.
local function tidy(stored: any): Types.PlayerSave
	local save = fresh()
	if typeof(stored) ~= "table" then
		return save
	end

	local licence = stored.licence
	if typeof(licence) == "table" then
		save.licence.stamps = wholeNumber(licence.stamps, 1, Config.LicenceSlots, 1)
		save.licence.cards = wholeNumber(licence.cards, 0, math.huge, 0)
		-- A date in the future would block every stamp until it came round, so
		-- one is thrown away. Tomorrow is allowed, for servers whose clocks differ.
		local day = wholeNumber(licence.lastStampDay, 0, math.huge, 0)
		save.licence.lastStampDay = if day > Calendar.today() + 1 then 0 else day
	end

	-- Ids this version does not know are kept as long as they are well formed:
	-- a newer server may have added an item, and this one must not erase it.
	-- Only those count towards the limit, so they can never crowd out a known one.
	local collection = stored.collection
	if typeof(collection) == "table" then
		local unknownKept = 0
		for id, found in collection do
			if typeof(id) == "string" and found == true then
				if ParcelDefs.ItemsById[id] then
					save.collection[id] = true
				elseif #id <= MAX_ID_LENGTH and unknownKept < MAX_UNKNOWN then
					save.collection[id] = true
					unknownKept += 1
				end
			end
		end
	end
	return save
end

-- Combines what is stored with what a session holds. The licence that is further
-- along wins and the collections are joined, so applying it twice changes nothing.
local function merge(stored: Types.PlayerSave, mine: Types.PlayerSave): Types.PlayerSave
	local a, b = stored.licence, mine.licence
	local mineIsAhead = b.cards > a.cards or (b.cards == a.cards and b.stamps > a.stamps)
	local furthest = if mineIsAhead then b else a
	local merged: Types.PlayerSave = {
		version = VERSION,
		licence = {
			stamps = furthest.stamps,
			cards = furthest.cards,
			lastStampDay = math.max(a.lastStampDay, b.lastStampDay),
		},
		collection = table.clone(stored.collection),
	}
	for id in mine.collection do
		merged.collection[id] = true
	end
	return merged
end

-- Runs `attempt` until it works or the tries run out, waiting longer each time.
local function withRetries(what: string, key: string, attempt: () -> ()): boolean
	local pause = Config.SaveBackoff
	for try = 1, Config.SaveAttempts do
		local problem = ""
		local ok = xpcall(attempt, function(message)
			problem = tostring(message)
		end)
		if ok then
			return true
		end
		if try == Config.SaveAttempts then
			warn(`Player data: {what} of {key} failed {try} times: {problem}`)
		else
			task.wait(pause)
			pause *= 2
		end
	end
	return false
end

-- Tells the player where they stand. Only items this version knows are sent.
local function sync(session: Session)
	if sessions[session.owner] ~= session then
		return
	end
	local known: { [string]: boolean } = {}
	for id in session.data.collection do
		if ParcelDefs.ItemsById[id] then
			known[id] = true
		end
	end
	local progress: Types.Progress = {
		licence = session.data.licence,
		licenceSlots = Config.LicenceSlots,
		collection = known,
		saving = session.loaded,
	}
	Remotes.ProgressSync:FireClient(session.owner, progress)
end

-- One pass of saving: writes a snapshot and takes back what is now stored.
local function write(dataStore: DataStore, session: Session)
	-- Anything earned while this runs stays in the session, marks it dirty
	-- again, and goes out with the next pass.
	session.dirty = false
	local snapshot = copy(session.data)
	local written: Types.PlayerSave? = nil
	local tooNew = false
	local ok = withRetries("save", session.key, function()
		written = nil
		-- The store may call this more than once, and it must not yield.
		dataStore:UpdateAsync(session.key, function(stored)
			if isNewer(stored) then
				tooNew = true
				return nil -- cancels the write
			end
			local result = merge(tidy(stored), snapshot)
			written = result
			return result
		end)
	end)

	local result = written
	if tooNew then
		-- Another server has since saved in a newer format. Stop writing.
		session.loaded = false
		sync(session)
	elseif ok and result then
		-- What is stored now may include progress from another server. Take
		-- it, and lay on top whatever this session earned in the meantime.
		session.data = merge(result, session.data)
		session.savedAt = os.clock()
		session.failedRounds = 0
		sync(session)
	else
		session.dirty = true
		session.failedRounds += 1
	end
end

-- Saves this session if it has anything new. Yields. Safe to call at any time,
-- including after the player has left.
local function save(session: Session)
	local dataStore = store
	if not dataStore or not session.loaded then
		return
	end
	if session.saving then
		session.again = true
		return
	end
	session.saving = true
	savesRunning += 1
	-- Whatever happens inside, the lines after this always run.
	local finished = xpcall(function()
		repeat
			session.again = false
			if session.dirty and session.loaded then
				write(dataStore, session)
			end
		until not session.again
	end, function(problem)
		warn(`Player data: saving {session.key} stopped unexpectedly: {problem}`)
	end)
	if not finished then
		-- Still owed. Counting it as a failed round keeps a repeating error from
		-- holding a departed player's session for ever.
		session.dirty = true
		session.failedRounds += 1
	end
	session.saving = false
	savesRunning -= 1

	-- A player who has left with progress still unsaved is kept for another try.
	if session.departed then
		local keep = session.dirty and session.loaded and session.failedRounds < GIVE_UP_ROUNDS
		if keep then
			stranded[session] = true
		else
			stranded[session] = nil
		end
	end
end

-- Saves now unless a save has just succeeded, in which case the regular
-- autosave picks it up. Keeps a burst of awards from becoming a burst of writes.
local function saveSoon(session: Session)
	if os.clock() - session.savedAt >= Config.SaveGap then
		task.spawn(save, session)
	end
end

local function load(player: Player)
	if sessions[player] then
		return
	end
	local session: Session = {
		owner = player,
		key = `u_{player.UserId}`,
		data = fresh(),
		loaded = false,
		ready = false,
		dirty = false,
		saving = false,
		again = false,
		departed = false,
		failedRounds = 0,
		savedAt = -math.huge,
	}
	sessions[player] = session

	local dataStore = store
	local stored: any = nil
	local ok = false
	if dataStore then
		ok = withRetries("load", session.key, function()
			stored = dataStore:GetAsync(session.key)
		end)
	end

	-- The player may have left while this was loading.
	if sessions[player] ~= session then
		return
	end
	if ok then
		session.data = tidy(stored)
		if isNewer(stored) then
			-- Shown, but never written: this version might drop what it cannot read.
			warn(
				`Player data: {session.key} was saved by a newer version of the game and will not be written.`
			)
		else
			session.loaded = true
		end
	end
	session.ready = true
	sync(session)
end

local function unload(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	sessions[player] = nil
	session.departed = true
	-- Start the count afresh, so earlier failures do not cut the retries short.
	session.failedRounds = 0
	-- If a save is already running, this makes it go round once more.
	save(session)
end

-- Adds an item to the player's collection book. Call when their team handles it correctly.
function PlayerData.collect(player: Player, itemId: string)
	local session = sessions[player]
	if not session or not session.ready then
		return
	end
	if session.data.collection[itemId] or not ParcelDefs.ItemsById[itemId] then
		return
	end
	session.data.collection[itemId] = true
	session.dirty = true
	sync(session)
end

-- Gives the player the stamp for `day`, unless they already have one for that
-- day or a later one. A seventh stamp starts a new card.
function PlayerData.stamp(player: Player, day: number)
	local session = sessions[player]
	if not session or not session.ready then
		return
	end
	local licence = session.data.licence
	if day <= licence.lastStampDay then
		return
	end
	licence.lastStampDay = day
	if licence.stamps >= Config.LicenceSlots then
		licence.cards += 1
		licence.stamps = 1
	else
		licence.stamps += 1
	end
	session.dirty = true
	sync(session)
	saveSoon(session)
end

function PlayerData.start()
	-- In a place that has never been published this fails, and so does every
	-- load. Players then play without saving, which is the right outcome.
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn(`Player data: no data store, so nothing will be saved: {result}`)
	end

	Players.PlayerRemoving:Connect(unload)
	Players.PlayerAdded:Connect(function(player)
		task.spawn(load, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end

	task.spawn(function()
		while not closing do
			task.wait(Config.AutosaveSeconds)
			for _, session in sessions do
				if session.dirty then
					task.spawn(save, session)
				end
			end
			for session in stranded do
				task.spawn(save, session)
			end
		end
	end)

	-- The server is closing. Save everyone at once, including players who left
	-- with a save still owed, and keep trying whatever fails until the deadline.
	game:BindToClose(function()
		closing = true
		local deadline = os.clock() + Config.ShutdownSeconds
		local owed = true
		while owed and os.clock() < deadline do
			for _, session in sessions do
				if session.dirty then
					task.spawn(save, session)
				end
			end
			for session in stranded do
				task.spawn(save, session)
			end
			while savesRunning > 0 and os.clock() < deadline do
				task.wait(0.1)
			end
			owed = next(stranded) ~= nil
			for _, session in sessions do
				if session.dirty and session.loaded then
					owed = true
				end
			end
			if owed then
				task.wait(0.5)
			end
		end
	end)
end

return PlayerData
