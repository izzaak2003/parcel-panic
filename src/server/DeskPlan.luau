--!strict
-- Works out who should be at which desk. Pure logic with no Roblox services,
-- so it can be tested by calling it with made-up players.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)

local DeskPlan = {}

local function count<K>(roster: { K }, desks: { [K]: Types.Desk }, desk: Types.Desk): number
	local total = 0
	for _, who in roster do
		if desks[who] == desk then
			total += 1
		end
	end
	return total
end

-- `roster` is everyone present, oldest first. `desks` is who sits where now and
-- is updated in place. Returns the people whose desk changed.
--
-- Rules: nobody is moved without need; a newcomer goes to the desk with fewer
-- people; and with two or more present, neither desk is left empty.
function DeskPlan.rebalance<K>(roster: { K }, desks: { [K]: Types.Desk }): { K }
	local moved: { K } = {}

	for _, who in roster do
		if desks[who] == nil then
			local scanners = count(roster, desks, "Scanner")
			local clerks = count(roster, desks, "Clerk")
			desks[who] = if scanners <= clerks then "Scanner" else "Clerk"
			table.insert(moved, who)
		end
	end

	if #roster >= 2 then
		local empty: Types.Desk? = nil
		if count(roster, desks, "Scanner") == 0 then
			empty = "Scanner"
		elseif count(roster, desks, "Clerk") == 0 then
			empty = "Clerk"
		end
		if empty then
			-- Everyone is at the other desk, so move whoever arrived last.
			local newest = roster[#roster]
			desks[newest] = empty
			if not table.find(moved, newest) then
				table.insert(moved, newest)
			end
		end
	end

	return moved
end

return DeskPlan
