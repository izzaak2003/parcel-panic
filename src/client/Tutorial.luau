--!strict
-- The first-time prompts: three short lines that walk a new player through
-- their first parcel. They never block play. Each one moves on when the player
-- does the thing it describes, or after a few seconds, and the whole thing ends
-- at the first verdict.
--
-- "New" means the collection book is empty, so nothing extra has to be saved to
-- remember that the prompts were seen.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Feedback = require(script.Parent.Feedback)
local Gui = require(script.Parent.Gui)
local ShiftClient = require(script.Parent.ShiftClient)
local Types = require(ReplicatedStorage.Shared.Types)

local READ_SECONDS = 5 -- how long a line that only explains stays up
local MIN_SECONDS = 1.5 -- the least time any line stays up, however quick the player is

-- What a step can look at to decide whether the player has done it.
type Progress = {
	seconds: number, -- time this step has been showing
	openedRulebook: boolean,
	sentPing: boolean,
	heardPing: boolean,
}
type Step = { text: string, done: (Progress) -> boolean }

local function read(progress: Progress): boolean
	return progress.seconds >= READ_SECONDS
end
local function never(): boolean
	return false -- only the first verdict ends this step
end

-- One list for each way a first shift can begin. To change the wording, edit here.
local ALONE: { Step } = {
	{ text = "The X-ray shows what is inside the parcel.", done = read },
	{
		text = "Open the rulebook. Anything that matches a rule goes back.",
		done = function(progress)
			return progress.openedRulebook
		end,
	},
	{ text = "Now stamp the parcel: Return or Ship.", done = never },
}
local AT_SCANNER: { Step } = {
	{ text = "The X-ray shows what is inside. Only you can see it.", done = read },
	{
		text = "Tell the Clerk what you see: tap Colour, Shape and Handles.",
		done = function(progress)
			return progress.sentPing
		end,
	},
	{ text = "The Clerk checks the rules and stamps Return or Ship.", done = never },
}
local AT_CLERK: { Step } = {
	{ text = "You hold the rulebook. Anything that matches a rule goes back.", done = read },
	{
		text = "Only the Scanner can see inside. Their stamps appear at the top.",
		done = function(progress)
			return progress.heardPing or progress.seconds >= READ_SECONDS * 2
		end,
	},
	{ text = "When you know, stamp the parcel: Return or Ship.", done = never },
}

local Tutorial = {}

function Tutorial.start()
	local label = Gui.label(Gui.root(), "TutorialLabel")
	label.Visible = false

	local steps: { Step }? = nil -- the lines being shown, or nil when none are
	local index = 0
	local startedAt = 0
	local finished = false -- true once the first verdict has ended it for good
	local run = 0 -- goes up each time the lines start, so an older watcher knows to stop
	local solo = false
	local desk: Types.Desk? = nil
	local progress: Progress =
		{ seconds = 0, openedRulebook = false, sentPing = false, heardPing = false }

	local function show(step: number)
		local list = steps
		if not list then
			return
		end
		index = step
		startedAt = os.clock()
		label.Text = `{step} of {#list}: {list[step].text}`
		label.Visible = true
		Feedback.pop(label, 0.8)
	end

	local function hide()
		steps = nil
		label.Visible = false
	end

	-- Moves to the next line once the current one has been done. Runs only while
	-- lines are showing. A line always stays up long enough to be read.
	local function watch(list: { Step }, mine: number)
		while steps == list and run == mine do
			progress.seconds = os.clock() - startedAt
			if index < #list and progress.seconds >= MIN_SECONDS and list[index].done(progress) then
				show(index + 1)
			end
			task.wait(0.2)
		end
	end

	local function begin(list: { Step }, own: Types.DeskState)
		solo = own.solo
		desk = own.desk
		progress = { seconds = 0, openedRulebook = false, sentPing = false, heardPing = false }
		steps = list
		run += 1
		show(1)
		task.spawn(watch, list, run)
	end

	ShiftClient.onVerdict(function()
		if steps then
			finished = true
			hide()
		end
	end)

	ShiftClient.onPing(function(ping: Types.Ping)
		if not steps then
			return
		end
		if ping.from == desk then
			progress.sentPing = true
		else
			progress.heardPing = true
		end
	end)

	ShiftClient.onChanged(function()
		if finished then
			return
		end
		local state = ShiftClient.getState()
		local own = ShiftClient.getDesk()
		local saved = ShiftClient.getProgress()
		if not state or not own or not saved or not ShiftClient.isLive() then
			return
		end

		if steps then
			if state.phase ~= "Running" or own.solo ~= solo or (not solo and own.desk ~= desk) then
				-- The team changed, so these lines are now the wrong ones. Drop
				-- them; the right set starts below, or on the next parcel.
				hide()
			else
				if own.solo and own.desk == "Clerk" then
					progress.openedRulebook = true
				end
				return
			end
		end

		-- Anyone with something in their collection book has played before.
		if next(saved.collection) ~= nil then
			finished = true
			return
		end
		if state.phase == "Running" and state.parcelSeq > 0 then
			begin(
				if own.solo then ALONE elseif own.desk == "Scanner" then AT_SCANNER else AT_CLERK,
				own
			)
		end
	end)
end

return Tutorial
