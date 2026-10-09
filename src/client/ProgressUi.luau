--!strict
-- Shows what a player keeps between visits, on the end-of-shift panel: the
-- postal licence card and the collection book. Also shows the rule of the day,
-- which everyone at either desk may see.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Gui = require(script.Parent.Gui)
local ParcelDefs = require(ReplicatedStorage.Shared.ParcelDefs)
local RuleDefs = require(ReplicatedStorage.Shared.RuleDefs)
local ShiftClient = require(script.Parent.ShiftClient)

local STAMPED = Color3.fromRGB(245, 205, 66)
local EMPTY = Color3.fromRGB(70, 76, 96)
local FOUND = Color3.fromRGB(76, 187, 106)

local ProgressUi = {}

function ProgressUi.start()
	local gui = Gui.root()
	local dailyLabel = Gui.label(gui, "DailyLabel")
	local endPanel = Gui.element(gui, "EndPanel")
	local licenceLabel = Gui.label(endPanel, "LicenceLabel")
	local licenceCard = Gui.element(endPanel, "LicenceCard")
	local slotTemplate = Gui.label(licenceCard, "SlotTemplate")
	local collectionBook = Gui.element(endPanel, "CollectionBook")
	local itemTemplate = Gui.label(collectionBook, "ItemTemplate")
	local saveNotice = Gui.label(endPanel, "SaveNotice")

	-- One label per item, in the order the data lists them. An item not yet
	-- handled shows as a question mark.
	local itemLabels: { [string]: TextLabel } = {}
	for index, item in ParcelDefs.Items do
		local label = itemTemplate:Clone()
		label.Name = item.id
		label.LayoutOrder = index
		label.Visible = true
		label.Parent = collectionBook
		itemLabels[item.id] = label
	end

	local slots: { TextLabel } = {}
	local function slot(index: number): TextLabel
		while #slots < index do
			local made = slotTemplate:Clone()
			made.Name = "Slot"
			made.LayoutOrder = #slots + 1
			made.Parent = licenceCard
			table.insert(slots, made)
		end
		return slots[index]
	end

	ShiftClient.onChanged(function()
		local state = ShiftClient.getState()
		local daily = if state then RuleDefs.ById[state.dailyRuleId] else nil
		dailyLabel.Visible = daily ~= nil
		if daily then
			dailyLabel.Text = `Rule of the day: {daily.text}`
		end

		local progress = ShiftClient.getProgress()
		if not progress then
			return
		end
		local licence = progress.licence
		licenceLabel.Text = if licence.cards > 0
			then `Postal licence: {licence.stamps} of {progress.licenceSlots} stamps. Cards filled: {licence.cards}`
			else `Postal licence: {licence.stamps} of {progress.licenceSlots} stamps`
		for index = 1, math.max(progress.licenceSlots, #slots) do
			local label = slot(index)
			local stamped = index <= licence.stamps
			label.Visible = index <= progress.licenceSlots
			label.Text = if stamped then "✓" else ""
			label.BackgroundColor3 = if stamped then STAMPED else EMPTY
		end

		for _, item in ParcelDefs.Items do
			local label = itemLabels[item.id]
			local found = progress.collection[item.id] == true
			label.Text = if found then item.name else "?"
			label.BackgroundColor3 = if found then FOUND else EMPTY
		end

		saveNotice.Visible = not progress.saving
	end)
end

return ProgressUi
