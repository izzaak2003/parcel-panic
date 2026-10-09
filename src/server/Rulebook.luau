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

-- The rule of the day: the same for every player on a given day, and shown to
-- everyone. It is worked out from the date alone, so it is not a secret and is
-- not treated as one.
function Rulebook.daily(day: number): RuleDefs.Rule
	return RuleDefs.All[Random.new(day):NextInteger(1, #RuleDefs.All)]
end

-- The rulebook for a shift: the rule of the day first, then others picked at
-- random with `rng`, which must not be seeded from anything a player could know.
function Rulebook.pick(rng: Random, count: number, day: number): { RuleDefs.Rule }
	local daily = Rulebook.daily(day)
	local others = {}
	for _, rule in RuleDefs.All do
		if rule ~= daily then
			table.insert(others, rule)
		end
	end
	rng:Shuffle(others)

	local rules = { daily }
	for index = 1, math.min(count - 1, #others) do
		table.insert(rules, others[index])
	end
	return rules
end

return Rulebook
