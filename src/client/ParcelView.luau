--!strict
-- The parcel in the room. It rides in on the belt, waits under the scanner, and
-- leaves by the Ship hatch or the Return chute when the verdict comes.
--
-- It is drawn on each player's own device from the public state, so it moves
-- smoothly and the server sends nothing extra. It is the same plain box every
-- time: what is inside is never in the 3D world.
local TweenService = game:GetService("TweenService")

local Belt = require(script.Parent.Belt)
local Markers = require(script.Parent.Markers)
local ShiftClient = require(script.Parent.ShiftClient)
local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local SIZE = Vector3.new(3, 2, 2)
local COLOUR = Color3.fromRGB(181, 137, 87)
local ARRIVE_SECONDS = 0.9
local SHIP_SECONDS = 0.9
local PUSH_SECONDS = 0.3
local SLIDE_SECONDS = 0.6
local VANISH_SECONDS = 0.25

local STAMPS: { [Types.Verdict]: { text: string, colour: Color3 } } = {
	Ship = { text = "SHIP", colour = Color3.fromRGB(76, 187, 106) },
	Return = { text = "RETURN", colour = Color3.fromRGB(226, 76, 68) },
}

local ParcelView = {}

local box: Part? = nil -- the parcel waiting on the desk, if one is shown
local shownSeq = 0 -- the number of the last parcel shown
local warned = false

local function tween(
	part: Part,
	seconds: number,
	style: Enum.EasingDirection,
	goal: { [string]: any }
): Tween
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Quad, style)
	local made = TweenService:Create(part, info, goal)
	made:Play()
	return made
end

local function restingPlace(spot: BasePart): CFrame
	return spot.CFrame * CFrame.new(0, (spot.Size.Y + SIZE.Y) / 2, 0)
end

local function arrive(seq: number)
	local old = box
	if old then
		old:Destroy()
	end
	box = nil

	local spot = Markers.find("ParcelSpot")
	if not spot then
		-- Not remembered as shown, so the next change tries again.
		if not warned then
			warned = true
			warn('No part named "ParcelSpot" in Workspace, so parcels are not drawn in the room.')
		end
		return
	end
	shownSeq = seq
	local part = Instance.new("Part")
	part.Name = "Parcel"
	part.Size = SIZE
	part.Color = COLOUR
	part.Material = Enum.Material.Cardboard
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false

	local rest = restingPlace(spot)
	local entry = Markers.find("ParcelIn")
	-- A parcel already on the desk when this player joined is simply there.
	if entry and ShiftClient.isLive() then
		part.CFrame = entry.CFrame
		tween(part, ARRIVE_SECONDS, Enum.EasingDirection.Out, { CFrame = rest })
		Belt.run(ARRIVE_SECONDS)
	else
		part.CFrame = rest
	end
	part.Parent = workspace
	box = part
end

-- A stamp that sits on the parcel and rides out with it.
local function stampOnto(part: Part, verdict: Types.Verdict)
	local look = STAMPS[verdict]
	local board = Instance.new("BillboardGui")
	board.Size = UDim2.fromScale(4, 1.5)
	board.StudsOffset = Vector3.new(0, 2.2, 0)
	board.AlwaysOnTop = true
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundColor3 = look.colour
	text.TextColor3 = Color3.new(1, 1, 1)
	text.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
	text.TextScaled = true
	text.Text = look.text
	text.Parent = board
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.2, 0)
	corner.Parent = text
	board.Parent = part
end

local function depart(seq: number, verdict: Types.Verdict)
	local part = box
	if not part or seq ~= shownSeq then
		return
	end
	box = nil
	stampOnto(part, verdict)

	local last: Tween? = nil
	if verdict == "Ship" then
		local hatch = Markers.find("ParcelShip")
		if hatch then
			last = tween(part, SHIP_SECONDS, Enum.EasingDirection.In, { CFrame = hatch.CFrame })
			Belt.run(SHIP_SECONDS)
		end
	else
		local top = Markers.find("ReturnTop")
		local bin = Markers.find("ReturnBin")
		if top and bin then
			local push =
				tween(part, PUSH_SECONDS, Enum.EasingDirection.Out, { CFrame = top.CFrame })
			push.Completed:Wait()
			last = tween(part, SLIDE_SECONDS, Enum.EasingDirection.In, { CFrame = bin.CFrame })
		end
	end
	if last then
		last.Completed:Wait()
	end
	part:Destroy()
end

-- The parcel was taken away without a verdict: the shift ended, or the team changed.
local function vanish()
	local part = box
	if not part then
		return
	end
	box = nil
	local fade = tween(
		part,
		VANISH_SECONDS,
		Enum.EasingDirection.In,
		{ Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1 }
	)
	fade.Completed:Wait()
	part:Destroy()
end

function ParcelView.start()
	ShiftClient.onChanged(function()
		local state = ShiftClient.getState()
		if not state then
			return
		end
		local seq = if state.phase == "Running" then state.parcelSeq else 0
		if seq > 0 and seq ~= shownSeq then
			arrive(seq)
		elseif seq == 0 and box then
			task.spawn(vanish)
		end
	end)

	ShiftClient.onVerdict(function(seq: number, verdict: Types.Verdict)
		task.spawn(depart, seq, verdict)
	end)
end

return ParcelView
