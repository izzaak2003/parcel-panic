--!strict
-- The stamps on the ping board. To add a stamp, add a row here.
--
-- A stamp is a ready-made message, so two players can work together without
-- typing or chat. What a stamp says depends on who sends it: a desk states what
-- it knows and asks about what it does not.
--
--   trait stamp   from the Scanner: "Colour: Red" (the server fills in the true value)
--                 from the Clerk:   "Colour?"
--   rule stamp    from the Clerk:   one rule from the rulebook
--                 from the Scanner: "Which rule?"
--   plain stamp   says the same thing from either desk
local Types = require(script.Parent.Types)

export type StampKind = "plain" | "trait" | "rule"

export type StampDef = {
	id: string,
	label: string, -- the text on the button
	kind: StampKind,
	trait: Types.Trait?, -- for trait stamps, which trait
}

local all: { StampDef } = {
	{ id = "check", label = "Yes", kind = "plain" },
	{ id = "cross", label = "No", kind = "plain" },
	{ id = "handle", label = "Handles", kind = "trait", trait = "handles" },
	{ id = "colour", label = "Colour", kind = "trait", trait = "colour" },
	{ id = "shape", label = "Shape", kind = "trait", trait = "shape" },
	{ id = "rule", label = "Rule says", kind = "rule" },
	{ id = "question", label = "?", kind = "plain" },
	{ id = "hurry", label = "Hurry!", kind = "plain" },
}

local byId: { [string]: StampDef } = {}
local ruleStampId = ""
for _, stamp in all do
	byId[stamp.id] = stamp
	if stamp.kind == "rule" then
		ruleStampId = stamp.id
	end
end

return table.freeze({
	All = all,
	ById = byId,
	RuleStampId = ruleStampId, -- the stamp a rule row in the rulebook sends
})
