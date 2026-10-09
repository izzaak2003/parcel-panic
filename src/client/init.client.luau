--!strict
-- Everything that exists when the server starts has arrived once the game
-- reports loaded, so the modules below can reach ReplicatedStorage by path.
if not game:IsLoaded() then
	game.Loaded:Wait()
end

local DeskCamera = require(script.DeskCamera)
local DeskUi = require(script.DeskUi)

DeskCamera.start()
DeskUi.start(DeskCamera.show)
