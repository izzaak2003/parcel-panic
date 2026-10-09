--!strict
-- Everything that exists when the server starts has arrived once the game
-- reports loaded, so the modules below can reach ReplicatedStorage by path.
if not game:IsLoaded() then
	game.Loaded:Wait()
end

local Belt = require(script.Belt)
local DeskCamera = require(script.DeskCamera)
local DeskUi = require(script.DeskUi)
local Feedback = require(script.Feedback)
local ParcelView = require(script.ParcelView)
local PingUi = require(script.PingUi)
local ShiftClient = require(script.ShiftClient)

-- One part failing to start, say because a piece of the layout was deleted in
-- Studio, must not take the rest of the game down with it.
local function start(name: string, begin: () -> ())
	xpcall(begin, function(problem)
		warn(`{name} could not start: {problem}`)
	end)
end

-- Each of these asks ShiftClient to tell it about changes. ShiftClient starts
-- listening to the server last, so none of them misses what was sent early.
start("Belt", Belt.start)
start("DeskCamera", DeskCamera.start)
start("DeskUi", DeskUi.start)
start("Feedback", Feedback.start)
start("PingUi", PingUi.start)
start("ParcelView", ParcelView.start)
ShiftClient.start()
