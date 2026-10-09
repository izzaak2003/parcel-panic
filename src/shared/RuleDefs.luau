--!strict
-- Every rule a rulebook can contain. To add a rule, add a row here.
--
-- A rule sends parcels back. A parcel matches a rule when every trait listed
-- in `match` is the same as the parcel's. A parcel that matches no rule ships.
local Types = require(script.Parent.Types)

export type Match = {
	colour: Types.Colour?,
	shape: Types.Shape?,
	handles: number?,
}

export type Rule = {
	id: string,
	text: string,
	match: Match,
}

local all: { Rule } = {
	{ id = "handles-0", text = "Anything with no handles goes back", match = { handles = 0 } },
	{ id = "handles-1", text = "Anything with one handle goes back", match = { handles = 1 } },
	{ id = "handles-2", text = "Anything with two handles goes back", match = { handles = 2 } },
	{ id = "colour-red", text = "Anything red goes back", match = { colour = "Red" } },
	{ id = "colour-blue", text = "Anything blue goes back", match = { colour = "Blue" } },
	{ id = "colour-green", text = "Anything green goes back", match = { colour = "Green" } },
	{ id = "colour-yellow", text = "Anything yellow goes back", match = { colour = "Yellow" } },
	{ id = "shape-round", text = "Anything round goes back", match = { shape = "Round" } },
	{ id = "shape-square", text = "Anything square goes back", match = { shape = "Square" } },
	{ id = "shape-tall", text = "Anything tall goes back", match = { shape = "Tall" } },
}

local byId: { [string]: Rule } = {}
for _, rule in all do
	byId[rule.id] = rule
end

return table.freeze({
	All = all,
	ById = byId,
})
