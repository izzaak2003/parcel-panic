--!strict
-- Makes the conveyor look as if it is moving, by sliding its stripes along it
-- for a moment whenever a parcel travels. The stripes are ordinary parts in the
-- Studio place; moving them here changes them for this player only.
local RunService = game:GetService("RunService")

local SPEED = 24 -- studs per second
local MARGIN = 1.5 -- how far from each end of the belt the stripes turn round

local Belt = {}

local runUntil = 0
local belt: BasePart? = nil
local stripes: { BasePart } = {}

-- Looks the belt up when it is first needed, and again if it has gone.
local function findBelt(): BasePart?
	local current = belt
	if current and current:IsDescendantOf(workspace) then
		return current
	end
	belt = nil
	table.clear(stripes)
	local conveyor = workspace:FindFirstChild("Conveyor", true)
	local surface = conveyor and conveyor:FindFirstChild("Belt")
	if not conveyor or not surface or not surface:IsA("BasePart") then
		return nil
	end
	for _, child in conveyor:GetChildren() do
		if child.Name == "Stripe" and child:IsA("BasePart") then
			table.insert(stripes, child)
		end
	end
	belt = surface
	return surface
end

local function step(dt: number)
	if os.clock() >= runUntil then
		return
	end
	local surface = findBelt()
	if not surface then
		return
	end
	local along = surface.CFrame.RightVector
	local turn = surface.Size.X / 2 - MARGIN
	for _, stripe in stripes do
		local moved = stripe.CFrame + along * (SPEED * dt)
		-- A stripe that runs off the far end comes back in at the near end.
		if surface.CFrame:PointToObjectSpace(moved.Position).X > turn then
			moved -= along * (turn * 2)
		end
		stripe.CFrame = moved
	end
end

-- Runs the belt for this many seconds from now.
function Belt.run(seconds: number)
	-- Look the stripes up afresh each time: some may have reached this player
	-- since the last parcel.
	belt = nil
	runUntil = math.max(runUntil, os.clock() + seconds)
end

function Belt.start()
	RunService.Heartbeat:Connect(step)
end

return Belt
