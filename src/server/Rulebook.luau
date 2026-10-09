--!strict
-- Chooses the rules for a shift and decides the right verdict for a parcel.
-- Server only: a client that could run this would know every answer.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RuleDefs = require(ReplicatedStorage.Shared.RuleDefs)
local Types = require(ReplicatedStorage.Shared.Types)

local Rulebook = {}

local function matches(rule: RuleDefs.Rule, contents: Types.Contents): boolean
	local match = rule.match
	return (match.colour == nil or match.colour == contents.colour)
		and (match.shape == nil or match.shape == contents.shape)
		and (match.handles == nil or match.handles == contents.handles)
end

-- A parcel goes back if any rule matches it. Otherwise it ships.
function Rulebook.judge(rules: { RuleDefs.Rule }, contents: Types.Contents): Types.Verdict
	for _, rule in rules do
		if matches(rule, contents) then
			return "Return"
		end
	end
	return "Ship"
end

function Rulebook.pick(rng: Random, count: number): { RuleDefs.Rule }
	local pool = table.clone(RuleDefs.All)
	rng:Shuffle(pool)
	return table.move(pool, 1, math.min(count, #pool), 1, {})
end

return Rulebook
