--!strict
-- Decides what is inside each parcel. Server only.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ParcelDefs = require(ReplicatedStorage.Shared.ParcelDefs)
local RuleDefs = require(ReplicatedStorage.Shared.RuleDefs)
local Rulebook = require(script.Parent.Rulebook)
local Types = require(ReplicatedStorage.Shared.Types)

-- Every possible parcel, sorted by what the shift's rules say about it.
export type Deck = {
	ship: { Types.Contents },
	back: { Types.Contents },
}

local ParcelGenerator = {}

function ParcelGenerator.deal(rules: { RuleDefs.Rule }): Deck
	local deck: Deck = { ship = {}, back = {} }
	for _, item in ParcelDefs.Items do
		for _, colour: Types.Colour in ParcelDefs.Colours do
			local contents: Types.Contents = {
				item = item.id,
				colour = colour,
				shape = item.shape,
				handles = item.handles,
			}
			table.freeze(contents)
			local pile = if Rulebook.judge(rules, contents) == "Return"
				then deck.back
				else deck.ship
			table.insert(pile, contents)
		end
	end
	return deck
end

-- Picks the verdict first and the parcel second, so the share of parcels that
-- go back stays at returnChance whatever the rules are.
function ParcelGenerator.draw(deck: Deck, rng: Random, returnChance: number): Types.Contents
	local pile = if rng:NextNumber() < returnChance then deck.back else deck.ship
	return pile[rng:NextInteger(1, #pile)]
end

return ParcelGenerator
