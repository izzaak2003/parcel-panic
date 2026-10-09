--!strict
-- Connects the on-screen desk to the shift. The layout is StarterGui.DeskGui,
-- built in Studio; this code only fills it in and reports button presses.
-- It decides nothing: it draws what the server sent and asks the server to act.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ParcelDefs = require(ReplicatedStorage.Shared.ParcelDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RuleDefs = require(ReplicatedStorage.Shared.RuleDefs)
local Types = require(ReplicatedStorage.Shared.Types)

local FEEDBACK_SECONDS = 1.2
local HANDLE_TEXT = { [0] = "No handles", [1] = "One handle", [2] = "Two handles" }
local ROLE_TEXT: { [Types.Desk]: string } = { Scanner = "SCANNER DESK", Clerk = "CLERK DESK" }

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

-- One line telling the player what to do now.
local function hintFor(desk: Types.DeskState, onDesk: boolean): string
	if not onDesk then
		return "Next parcel on its way..."
	elseif desk.solo then
		return if desk.desk == "Scanner"
			then "Look at the X-ray, check the rulebook, then stamp the parcel."
			else "Remember the rules, then go back to the X-ray."
	elseif desk.desk == "Scanner" then
		return "Tell the Clerk what is inside the parcel."
	else
		return "Ask the Scanner what is inside, then stamp the parcel."
	end
end

-- `showDesk` is called with the player's desk whenever the server changes it.
function DeskUi.start(showDesk: (Types.Desk) -> ())
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
	local roleLabel = label(gui, "RoleLabel")
	local hintLabel = label(gui, "HintLabel")

	local scannerPanel = element(gui, "ScannerPanel")
	local emptyLabel = label(scannerPanel, "EmptyLabel")
	local contentsFrame = element(scannerPanel, "Contents")
	local itemLabel = label(contentsFrame, "ItemLabel")
	local shapeLabel = label(contentsFrame, "ShapeLabel")
	local handlesLabel = label(contentsFrame, "HandlesLabel")
	local colourLabel = label(contentsFrame, "ColourLabel")
	local colourSwatch = element(contentsFrame, "ColourSwatch")

	local clerkPanel = element(gui, "ClerkPanel")
	local ruleList = element(clerkPanel, "RuleList")
	local ruleTemplate = label(ruleList, "RuleTemplate")

	local verdictBar = element(gui, "VerdictBar")
	local shipButton = button(verdictBar, "ShipButton")
	local returnButton = button(verdictBar, "ReturnButton")

	local switchPanel = element(gui, "SwitchPanel")
	local switchButton = button(switchPanel, "SwitchButton")
	local peekLabel = label(switchPanel, "PeekLabel")

	local feedbackLabel = label(gui, "FeedbackLabel")

	local endPanel = element(gui, "EndPanel")
	local endTitle = label(endPanel, "EndTitle")
	local endSummary = label(endPanel, "EndSummary")
	local playAgainButton = button(endPanel, "PlayAgainButton")

	-- The latest of each message from the server. Drawing always starts from these.
	local state: Types.PublicShiftState? = nil
	local desk: Types.DeskState? = nil
	local scannedSeq = 0
	local scanned: Types.Contents? = nil

	local function peekSecondsLeft(own: Types.DeskState): number
		if own.peekEndsAt > 0 then
			return math.max(0, own.peekEndsAt - workspace:GetServerTimeNow())
		end
		return own.peekLeft
	end

	local function render()
		local current = state
		local own = desk
		if not current or not own then
			return
		end
		local running = current.phase == "Running"
		local onDesk = running and current.parcelSeq > 0
		local atScanner = own.desk == "Scanner"

		strikesLabel.Text = `Mistakes: {current.strikes} / {current.maxStrikes}`
		correctLabel.Text = `Parcels: {current.correct}`
		if not running then
			timerLabel.Text = "--:--"
		end
		roleLabel.Text = ROLE_TEXT[own.desk]
		hintLabel.Visible = running
		hintLabel.Text = hintFor(own, onDesk)

		-- Each desk shows only its own half. A lone player holds both halves but
		-- still sees one at a time.
		scannerPanel.Visible = atScanner
		clerkPanel.Visible = not atScanner

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

		verdictBar.Visible = current.phase ~= "Ended" and own.canStamp
		shipButton.Active = onDesk
		returnButton.Active = onDesk
		shipButton.AutoButtonColor = onDesk
		returnButton.AutoButtonColor = onDesk

		switchPanel.Visible = own.solo and running
		local canOpen = peekSecondsLeft(own) > 0
		switchButton.Active = not atScanner or canOpen
		switchButton.AutoButtonColor = switchButton.Active
		if not atScanner then
			switchButton.Text = "Back to X-ray  [Q]"
		elseif canOpen then
			switchButton.Text = "Open rulebook  [Q]"
		else
			switchButton.Text = "Rulebook shut until the next parcel"
		end

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

	local function clearRules()
		for _, row in ruleList:GetChildren() do
			if row:IsA("TextLabel") and row ~= ruleTemplate then
				row:Destroy()
			end
		end
	end

	Remotes.DeskSync.OnClientEvent:Connect(function(newDesk: Types.DeskState)
		local previous = desk
		desk = newDesk
		-- Once the desks are split, drop whatever belonged to the other one. The
		-- server has already dealt new rules and a new parcel by then, so this is
		-- tidying, not what keeps the halves apart.
		if not newDesk.solo then
			if newDesk.desk == "Scanner" then
				clearRules()
			else
				scannedSeq = 0
				scanned = nil
			end
		end
		if not previous or previous.desk ~= newDesk.desk then
			showDesk(newDesk.desk)
		end
		render()
	end)

	Remotes.ParcelScanned.OnClientEvent:Connect(function(seq: number, contents: Types.Contents)
		scannedSeq = seq
		scanned = contents
		render()
	end)

	Remotes.RulebookShown.OnClientEvent:Connect(function(ruleIds: { string })
		clearRules()
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

	-- The server decides whether a switch is allowed; this only asks.
	local function requestSwitch()
		local own = desk
		if own and own.solo then
			Remotes.RequestSwitch:FireServer()
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
	switchButton.Activated:Connect(requestSwitch)

	-- Q is a shortcut for the on-screen switch button, never the only way.
	ContextActionService:BindAction(
		"SwitchDesk",
		function(_name: string, inputState: Enum.UserInputState)
			if inputState == Enum.UserInputState.Begin then
				requestSwitch()
			end
			return Enum.ContextActionResult.Pass
		end,
		false,
		Enum.KeyCode.Q,
		Enum.KeyCode.ButtonY
	)

	-- Runs for as long as the player is in the game. The server sends each deadline
	-- once; the countdowns are worked out here from the shared server clock.
	task.spawn(function()
		while true do
			local current = state
			local own = desk
			if current and current.phase == "Running" then
				local left = math.max(0, math.ceil(current.endsAt - workspace:GetServerTimeNow()))
				timerLabel.Text = string.format("%d:%02d", left // 60, left % 60)
				if own and own.solo then
					peekLabel.Text = `Rulebook time: {math.ceil(peekSecondsLeft(own))}s`
				end
			end
			task.wait(0.25)
		end
	end)
end

return DeskUi
