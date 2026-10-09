--!strict
-- Draws the desk: the top bar, the X-ray or the rulebook, the stamp buttons,
-- the lone player's desk switch, and the end-of-shift panel. It decides
-- nothing: it draws what ShiftClient holds and passes button presses to it.
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Gui = require(script.Parent.Gui)
local ParcelDefs = require(ReplicatedStorage.Shared.ParcelDefs)
local RuleDefs = require(ReplicatedStorage.Shared.RuleDefs)
local ShiftClient = require(script.Parent.ShiftClient)
local StampDefs = require(ReplicatedStorage.Shared.StampDefs)
local Types = require(ReplicatedStorage.Shared.Types)

local ROLE_TEXT: { [Types.Desk]: string } = { Scanner = "SCANNER DESK", Clerk = "CLERK DESK" }

local DeskUi = {}

-- One line telling the player what to do now.
local function hintFor(desk: Types.DeskState, onDesk: boolean): string
	if not onDesk then
		return "Next parcel on its way..."
	elseif desk.solo then
		return if desk.desk == "Scanner"
			then "Look at the X-ray, check the rulebook, then stamp the parcel."
			else "Remember the rules, then go back to the X-ray."
	elseif desk.desk == "Scanner" then
		return "Stamp what you see, so the Clerk can decide."
	else
		return "Find out what is inside, then stamp Ship or Return."
	end
end

local function peekSecondsLeft(desk: Types.DeskState): number
	if desk.peekEndsAt > 0 then
		return math.max(0, desk.peekEndsAt - workspace:GetServerTimeNow())
	end
	return desk.peekLeft
end

function DeskUi.start()
	local gui = Gui.root()

	local topBar = Gui.element(gui, "TopBar")
	local timerLabel = Gui.label(topBar, "TimerLabel")
	local strikesLabel = Gui.label(topBar, "StrikesLabel")
	local correctLabel = Gui.label(topBar, "CorrectLabel")
	local roleLabel = Gui.label(gui, "RoleLabel")
	local hintLabel = Gui.label(gui, "HintLabel")

	local scannerPanel = Gui.element(gui, "ScannerPanel")
	local emptyLabel = Gui.label(scannerPanel, "EmptyLabel")
	local contentsFrame = Gui.element(scannerPanel, "Contents")
	local itemLabel = Gui.label(contentsFrame, "ItemLabel")
	local shapeLabel = Gui.label(contentsFrame, "ShapeLabel")
	local handlesLabel = Gui.label(contentsFrame, "HandlesLabel")
	local colourLabel = Gui.label(contentsFrame, "ColourLabel")
	local colourSwatch = Gui.element(contentsFrame, "ColourSwatch")

	local clerkPanel = Gui.element(gui, "ClerkPanel")
	local ruleList = Gui.element(clerkPanel, "RuleList")
	local ruleTemplate = Gui.button(ruleList, "RuleTemplate")

	local verdictBar = Gui.element(gui, "VerdictBar")
	local shipButton = Gui.button(verdictBar, "ShipButton")
	local returnButton = Gui.button(verdictBar, "ReturnButton")

	local switchPanel = Gui.element(gui, "SwitchPanel")
	local switchButton = Gui.button(switchPanel, "SwitchButton")
	local peekLabel = Gui.label(switchPanel, "PeekLabel")

	local endPanel = Gui.element(gui, "EndPanel")
	local endTitle = Gui.label(endPanel, "EndTitle")
	local endSummary = Gui.label(endPanel, "EndSummary")
	local playAgainButton = Gui.button(endPanel, "PlayAgainButton")

	-- The rule rows are rebuilt only when the rulebook itself changes.
	local shownRules = ""
	local function drawRules(ruleIds: { string })
		local key = table.concat(ruleIds, ",")
		if key == shownRules then
			return
		end
		shownRules = key
		Gui.clearCopies(ruleList, ruleTemplate)
		for index, id in ruleIds do
			local rule = RuleDefs.ById[id]
			if rule then
				local row = ruleTemplate:Clone()
				row.Name = "Rule"
				row.Text = rule.text
				row.LayoutOrder = index
				row.Visible = true
				row.Parent = ruleList
				-- With the desks split, pressing a rule shows it to the Scanner.
				row.Activated:Connect(function()
					ShiftClient.ping(StampDefs.RuleStampId, index)
				end)
			end
		end
	end

	local function render()
		local state = ShiftClient.getState()
		local desk = ShiftClient.getDesk()
		if not state or not desk then
			return
		end
		local running = state.phase == "Running"
		local onDesk = running and state.parcelSeq > 0
		local atScanner = desk.desk == "Scanner"

		strikesLabel.Text = `Mistakes: {state.strikes} / {state.maxStrikes}`
		correctLabel.Text = `Parcels: {state.correct}`
		if not running then
			timerLabel.Text = "--:--"
		end
		roleLabel.Text = ROLE_TEXT[desk.desk]
		hintLabel.Visible = running
		hintLabel.Text = hintFor(desk, onDesk)

		-- Each desk shows only its own half. A lone player holds both halves but
		-- still sees one at a time.
		scannerPanel.Visible = atScanner
		clerkPanel.Visible = not atScanner
		drawRules(ShiftClient.getRuleIds())

		local contents = ShiftClient.getContents()
		contentsFrame.Visible = contents ~= nil
		emptyLabel.Visible = contents == nil
		if contents then
			local item = ParcelDefs.ItemsById[contents.item]
			itemLabel.Text = if item then item.name else contents.item
			shapeLabel.Text = contents.shape
			handlesLabel.Text = ParcelDefs.HandleText[contents.handles]
				or `{contents.handles} handles`
			colourLabel.Text = contents.colour
			colourSwatch.BackgroundColor3 = ParcelDefs.ColourSwatches[contents.colour]
		elseif state.phase == "Waiting" then
			emptyLabel.Text = "Shift starting..."
		else
			emptyLabel.Text = "Next parcel on its way..."
		end

		verdictBar.Visible = state.phase ~= "Ended" and desk.canStamp
		shipButton.Active = onDesk
		returnButton.Active = onDesk
		shipButton.AutoButtonColor = onDesk
		returnButton.AutoButtonColor = onDesk

		switchPanel.Visible = desk.solo and running
		local canOpen = peekSecondsLeft(desk) > 0
		switchButton.Active = not atScanner or canOpen
		switchButton.AutoButtonColor = switchButton.Active
		if not atScanner then
			switchButton.Text = "Back to X-ray  [Q]"
		elseif canOpen then
			switchButton.Text = "Open rulebook  [Q]"
		else
			switchButton.Text = "Rulebook shut until the next parcel"
		end

		endPanel.Visible = state.phase == "Ended"
		if state.phase == "Ended" then
			endTitle.Text = if state.endReason == "StruckOut"
				then "Shift over"
				else "Shift complete!"
			endSummary.Text =
				`Parcels handled correctly: {state.correct}\nMistakes: {state.strikes}`
		end
	end
	ShiftClient.onChanged(render)

	-- Activated fires for mouse clicks, screen taps, and gamepad presses alike.
	-- There is no guard against double presses: the server rejects a second
	-- verdict for the same parcel.
	shipButton.Activated:Connect(function()
		ShiftClient.submit("Ship")
	end)
	returnButton.Activated:Connect(function()
		ShiftClient.submit("Return")
	end)
	playAgainButton.Activated:Connect(ShiftClient.requestShift)
	switchButton.Activated:Connect(ShiftClient.requestSwitch)

	-- Q is a shortcut for the on-screen switch button, never the only way.
	ContextActionService:BindAction(
		"SwitchDesk",
		function(_name: string, inputState: Enum.UserInputState)
			if inputState == Enum.UserInputState.Begin then
				ShiftClient.requestSwitch()
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
			local state = ShiftClient.getState()
			local desk = ShiftClient.getDesk()
			if state and state.phase == "Running" then
				local left = math.max(0, math.ceil(state.endsAt - workspace:GetServerTimeNow()))
				timerLabel.Text = string.format("%d:%02d", left // 60, left % 60)
				if desk and desk.solo then
					peekLabel.Text = `Rulebook time: {math.ceil(peekSecondsLeft(desk))}s`
				end
			end
			task.wait(0.25)
		end
	end)
end

return DeskUi
