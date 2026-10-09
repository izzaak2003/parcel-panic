--!strict
-- The ping board: one button for each stamp, and a short list of the stamps
-- most recently sent by anyone. It is shown only when the desks are split,
-- because a player alone has nobody to ping.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Feedback = require(script.Parent.Feedback)
local Gui = require(script.Parent.Gui)
local ParcelDefs = require(ReplicatedStorage.Shared.ParcelDefs)
local RuleDefs = require(ReplicatedStorage.Shared.RuleDefs)
local ShiftClient = require(script.Parent.ShiftClient)
local StampDefs = require(ReplicatedStorage.Shared.StampDefs)
local Types = require(ReplicatedStorage.Shared.Types)

local FEED_ROWS = 4
local ROW_SECONDS = 8
local DESK_NAMES: { [Types.Desk]: string } = { Scanner = "SCANNER", Clerk = "CLERK" }

type Row = { label: TextLabel, ping: Types.Ping }

local PingUi = {}

-- The words for a ping, worked out from the stamp and what the server attached.
local function describe(ping: Types.Ping): string
	local stamp = StampDefs.ById[ping.stamp]
	if not stamp then
		return ping.stamp
	end
	local ruleId = ping.ruleId
	local value = ping.value
	if ruleId then
		local rule = RuleDefs.ById[ruleId]
		return if rule then rule.text else stamp.label
	elseif value ~= nil then
		if stamp.trait == "handles" and typeof(value) == "number" then
			return ParcelDefs.HandleText[value] or `{value} handles`
		end
		return `{stamp.label}: {value}`
	elseif stamp.kind == "trait" then
		return `{stamp.label}?`
	elseif stamp.kind == "rule" then
		return "Which rule?"
	end
	return stamp.label
end

local function same(a: Types.Ping, b: Types.Ping): boolean
	return a.from == b.from and a.stamp == b.stamp and a.value == b.value and a.ruleId == b.ruleId
end

function PingUi.start()
	local gui = Gui.root()
	local bar = Gui.element(gui, "PingBar")
	local stampTemplate = Gui.button(bar, "StampTemplate")
	local feed = Gui.element(gui, "PingFeed")
	local pingTemplate = Gui.label(feed, "PingTemplate")

	-- One button per stamp, in the order the data lists them.
	local nextRule = 0
	for index, stamp in StampDefs.All do
		local stampButton = stampTemplate:Clone()
		stampButton.Name = stamp.id
		stampButton.Text = stamp.label
		stampButton.LayoutOrder = index
		stampButton.Visible = true
		stampButton.Parent = bar
		stampButton.Activated:Connect(function()
			if stamp.kind == "rule" then
				-- From the Clerk desk each press shows the next rule in the book.
				-- From the Scanner desk the server ignores the number and asks.
				local count = #ShiftClient.getRuleIds()
				nextRule = if count > 0 then nextRule % count + 1 else 1
				ShiftClient.ping(stamp.id, nextRule)
			else
				ShiftClient.ping(stamp.id)
			end
		end)
	end

	local rows: { Row } = {}
	local function removeAt(index: number)
		rows[index].label:Destroy()
		table.remove(rows, index)
	end
	-- Removes every row, or every row `keep` does not ask to keep.
	local function clear(keep: ((Types.Ping) -> boolean)?)
		for index = #rows, 1, -1 do
			if not keep or not keep(rows[index].ping) then
				removeAt(index)
			end
		end
	end

	-- A stamp is about the parcel and rulebook that were there when it was sent,
	-- so it goes when they do. Rules outlast a parcel; nothing outlasts a rulebook.
	local lastDeal = 0
	local lastSeq = 0
	ShiftClient.onChanged(function()
		local state = ShiftClient.getState()
		local desk = ShiftClient.getDesk()
		local shown = state ~= nil and desk ~= nil and state.phase == "Running" and not desk.solo
		bar.Visible = shown
		feed.Visible = shown
		if not state or not shown or state.deal ~= lastDeal then
			clear()
		elseif state.parcelSeq ~= lastSeq then
			clear(function(ping)
				return ping.ruleId ~= nil
			end)
		end
		if state then
			lastDeal = state.deal
			lastSeq = state.parcelSeq
		end
	end)

	ShiftClient.onPing(function(ping: Types.Ping)
		-- A stamp that arrives after its parcel or rulebook has gone is not shown.
		local state = ShiftClient.getState()
		if not state or ping.deal ~= state.deal then
			return
		end
		if ping.ruleId == nil and ping.parcelSeq ~= state.parcelSeq then
			return
		end

		-- A repeat of what is already showing moves to the bottom without a sound,
		-- so tapping one stamp over and over cannot push everything else off.
		local wasShowing = false
		for index = #rows, 1, -1 do
			if same(rows[index].ping, ping) then
				removeAt(index)
				wasShowing = true
			end
		end

		local label = pingTemplate:Clone()
		label.Name = "Ping"
		label.Text = `{DESK_NAMES[ping.from]}: {describe(ping)}`
		label.LayoutOrder = ping.seq
		label.Visible = true
		label.Parent = feed
		table.insert(rows, { label = label, ping = ping })
		if #rows > FEED_ROWS then
			-- Make room. A desk that already fills all but one row loses its own
			-- oldest, so one busy desk cannot push the other desk's last word off.
			local fromSameDesk = 0
			local oldestFromSameDesk = 1
			for index = #rows, 1, -1 do
				if rows[index].ping.from == ping.from then
					fromSameDesk += 1
					oldestFromSameDesk = index
				end
			end
			removeAt(if fromSameDesk >= FEED_ROWS then oldestFromSameDesk else 1)
		end
		if not wasShowing then
			Feedback.play("Ping")
		end

		task.delay(ROW_SECONDS, function()
			for index, row in rows do
				if row.label == label then
					removeAt(index)
					break
				end
			end
		end)
	end)
end

return PingUi
