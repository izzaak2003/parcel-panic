--!strict
-- Everything that exists when the server starts has arrived once the game
-- reports loaded, so the modules below can reach ReplicatedStorage by path.
if not game:IsLoaded() then
	game.Loaded:Wait()
end

local DeskUi = require(script.DeskUi)

DeskUi.start()
