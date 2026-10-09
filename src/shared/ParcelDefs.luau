--!strict
-- Everything a parcel can contain. To add content, add rows here.
local Types = require(script.Parent.Types)

export type ItemDef = {
	id: string, -- never change an id once the game is live: saved data will refer to it
	name: string,
	shape: Types.Shape,
	handles: number,
}

-- Each shape and each handle count appears on exactly two items, so no rule is
-- much easier or harder to hit than another.
local items: { ItemDef } = {
	{ id = "ball", name = "Bouncy Ball", shape = "Round", handles = 0 },
	{ id = "teapot", name = "Teapot", shape = "Round", handles = 1 },
	{ id = "lantern", name = "Lantern", shape = "Square", handles = 1 },
	{ id = "basket", name = "Picnic Basket", shape = "Square", handles = 2 },
	{ id = "trophy", name = "Trophy", shape = "Tall", handles = 2 },
	{ id = "candle", name = "Candle", shape = "Tall", handles = 0 },
}

local colours: { Types.Colour } = { "Red", "Blue", "Green", "Yellow" }

local colourSwatches: { [Types.Colour]: Color3 } = {
	Red = Color3.fromRGB(226, 76, 68),
	Blue = Color3.fromRGB(66, 135, 245),
	Green = Color3.fromRGB(76, 187, 106),
	Yellow = Color3.fromRGB(245, 205, 66),
}

-- How a number of handles is written on screen.
local handleText: { [number]: string } =
	{ [0] = "No handles", [1] = "One handle", [2] = "Two handles" }

local itemsById: { [string]: ItemDef } = {}
for _, item in items do
	itemsById[item.id] = item
end

return table.freeze({
	Items = items,
	ItemsById = itemsById,
	Colours = colours,
	ColourSwatches = colourSwatches,
	HandleText = handleText,
})
