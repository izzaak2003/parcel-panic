--!strict
-- Connects the on-screen desk to the shift. The layout is StarterGui.DeskGui,
-- built in Studio; this code only fills it in and reports button presses.
-- It decides nothing: it draws what the server sent and asks the server for verdicts.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ParcelDefs = require(ReplicatedStorage.Shared.ParcelDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RuleDefs = require(ReplicatedStorage.Shared.RuleDefs)
local Types = require(ReplicatedStorage.Shared.Types)

local FEEDBACK_SECONDS = 1.2
local HANDLE_TEXT = { [0] = "No handles", [1] = "One handle", [2] = "Two handles" }

local DeskUi = {}

-- The names below are a contract with the Studio place. docs/NOTES.md lists them.
local function child(parent: Instance, name: string): Instance
	local found = parent:WaitForChild(name, 30)
	if not found then
		error(`{parent:GetFullName()} has no child named "{name}". See docs/NOTES.md.`)
	end
	return found
end

-- Anything this code only shows, hides, or recolours can be any kind of GUI
-- element, so a Frame can be swapped for an ImageLabel or a ScrollingFrame in Studio.
local function element(parent: Instance, name: string): GuiObject
	local found = child(parent, name)
	assert(found:IsA("GuiObject"), `{found:GetFullName()} must be a GUI element`)
	return found
end

local function label(parent: Instance, name: string): TextLabel
	local found = child(parent, name)
	assert(found:IsA("TextLabel"), `{found:GetFullName()} must be a TextLabel`)
	return found
end

local function button(parent: Instance, name: string): TextButton
	local found = child(parent, name)
	assert(found:IsA("TextButton"), `{found:GetFullName()} must be a TextButton`)
	return found
end

function DeskUi.start()
	local gui = child(child(Players.LocalPlayer, "PlayerGui"), "DeskGui")
	if gui:IsA("ScreenGui") and gui.ResetOnSpawn then
		warn(
			"DeskGui.ResetOnSpawn is on, so the desk will stop updating after a respawn. Turn it off."
		)
	end

	local topBar = element(gui, "TopBar")
	local timerLabel = label(topBar, "TimerLabel")
	local strikesLabel = label(topBar, "StrikesLabel")
	local correctLabel = label(topBar, "CorrectLabel")

	local scannerPanel = element(gui, "ScannerPanel")
	local emptyLabel = label(scannerPanel, "EmptyLabel")
	local contentsFrame = element(scannerPanel, "Contents")
	local itemLabel = label(contentsFrame, "ItemLabel")
	local shapeLabel = label(contentsFrame, "ShapeLabel")
	local handlesLabel = label(contentsFrame, "HandlesLabel")
	local colourLabel = label(contentsFrame, "ColourLabel")
	local colourSwatch = element(contentsFrame, "ColourSwatch")

	local ruleList = element(element(gui, "ClerkPanel"), "RuleList")
	local ruleTemplate = label(ruleList, "RuleTemplate")

	local verdictBar = element(gui, "VerdictBar")
	local shipButton = button(verdictBar, "ShipButton")
	local returnButton = button(verdictBar, "ReturnButton")

	local feedbackLabel = label(gui, "FeedbackLabel")

	local endPanel = element(gui, "EndPanel")
	local endTitle = label(endPanel, "EndTitle")
	local endSummary = label(endPanel, "EndSummary")
	local playAgainButton = button(endPanel, "PlayAgainButton")

	-- The latest of each message from the server. Drawing always starts from these.
	local state: Types.PublicShiftState? = nil
	local scannedSeq = 0
	local scanned: Types.Contents? = nil

	local function render()
		local current = state
		if not current then
			return
		end

		strikesLabel.Text = `Mistakes: {current.strikes} / {current.maxStrikes}`
		correctLabel.Text = `Parcels: {current.correct}`
		if current.phase ~= "Running" then
			timerLabel.Text = "--:--"
		end

		local onDesk = current.phase == "Running" and current.parcelSeq > 0
		local contents = if onDesk and scannedSeq == current.parcelSeq then scanned else nil
		contentsFrame.Visible = contents ~= nil
		emptyLabel.Visible = contents == nil
		if contents then
			local item = ParcelDefs.ItemsById[contents.item]
			itemLabel.Text = if item then item.name else contents.item
			shapeLabel.Text = contents.shape
			handlesLabel.Text = HANDLE_TEXT[contents.handles] or `{contents.handles} handles`
			colourLabel.Text = contents.colour
			colourSwatch.BackgroundColor3 = ParcelDefs.ColourSwatches[contents.colour]
		elseif current.phase == "Waiting" then
			emptyLabel.Text = "Shift starting..."
		else
			emptyLabel.Text = "Next parcel on its way..."
		end

		verdictBar.Visible = current.phase ~= "Ended"
		shipButton.Active = onDesk
		returnButton.Active = onDesk
		shipButton.AutoButtonColor = onDesk
		returnButton.AutoButtonColor = onDesk

		endPanel.Visible = current.phase == "Ended"
		if current.phase == "Ended" then
			endTitle.Text = if current.endReason == "StruckOut"
				then "Shift over"
				else "Shift complete!"
			endSummary.Text =
				`Parcels handled correctly: {current.correct}\nMistakes: {current.strikes}`
		end
	end

	Remotes.ShiftSync.OnClientEvent:Connect(function(newState: Types.PublicShiftState)
		state = newState
		render()
	end)

	Remotes.ParcelScanned.OnClientEvent:Connect(function(seq: number, contents: Types.Contents)
		scannedSeq = seq
		scanned = contents
		render()
	end)

	Remotes.RulebookShown.OnClientEvent:Connect(function(ruleIds: { string })
		for _, row in ruleList:GetChildren() do
			if row:IsA("TextLabel") and row ~= ruleTemplate then
				row:Destroy()
			end
		end
		for index, id in ruleIds do
			local rule = RuleDefs.ById[id]
			if rule then
				local row = ruleTemplate:Clone()
				row.Name = "Rule"
				row.Text = rule.text
				row.LayoutOrder = index
				row.Visible = true
				row.Parent = ruleList
			end
		end
	end)

	local feedbackCount = 0
	Remotes.VerdictJudged.OnClientEvent:Connect(
		function(_seq: number, _verdict: Types.Verdict, wasCorrect: boolean)
			feedbackCount += 1
			local shown = feedbackCount
			feedbackLabel.Text = if wasCorrect then "Correct!" else "Mistake!"
			feedbackLabel.Visible = true
			task.delay(FEEDBACK_SECONDS, function()
				-- Leave it alone if a newer verdict has replaced this one.
				if shown == feedbackCount then
					feedbackLabel.Visible = false
				end
			end)
		end
	)

	-- No guard against double presses here: the server rejects a second verdict
	-- for the same parcel, and the next ShiftSync switches the buttons off.
	local function submit(verdict: Types.Verdict)
		local current = state
		if current and current.phase == "Running" and current.parcelSeq > 0 then
			Remotes.SubmitVerdict:FireServer(current.parcelSeq, verdict)
		end
	end

	-- Activated fires for mouse clicks, screen taps, and gamepad presses alike.
	shipButton.Activated:Connect(function()
		submit("Ship")
	end)
	returnButton.Activated:Connect(function()
		submit("Return")
	end)
	playAgainButton.Activated:Connect(function()
		Remotes.RequestShift:FireServer()
	end)

	-- Runs for as long as the player is in the game. The server sends the time the
	-- shift ends once; the countdown is worked out here from the shared server clock.
	task.spawn(function()
		while true do
			local current = state
			if current and current.phase == "Running" then
				local left = math.max(0, math.ceil(current.endsAt - workspace:GetServerTimeNow()))
				timerLabel.Text = string.format("%d:%02d", left // 60, left % 60)
			end
			task.wait(0.25)
		end
	end)
end

return DeskUi
