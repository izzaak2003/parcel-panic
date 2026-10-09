--!strict
-- Holds the camera at the player's desk. Each desk has a marker part in the
-- Studio place whose position and facing are the camera's. Move the part in
-- Studio to change the view.
local RunService = game:GetService("RunService")

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local MARKER_NAMES: { [Types.Desk]: string } = { Scanner = "ScannerCamera", Clerk = "ClerkCamera" }
local GLIDE = 9 -- higher reaches the new desk sooner
local RETRY_SECONDS = 0.5
local GIVE_UP_SECONDS = 15

local DeskCamera = {}

local wanted: Types.Desk? = nil
local goal: CFrame? = nil
local arrived = false
local askedAt = 0
local nextLookAt = 0
local warned = false

-- The marker may not have reached this client yet when the desk is first known,
-- so keep looking for a while instead of giving up at once.
local function findGoal(desk: Types.Desk)
	local now = os.clock()
	if now < nextLookAt then
		return
	end
	nextLookAt = now + RETRY_SECONDS
	local marker = workspace:FindFirstChild(MARKER_NAMES[desk], true)
	if marker and marker:IsA("BasePart") then
		goal = marker.CFrame
	elseif not warned and now - askedAt > GIVE_UP_SECONDS then
		warned = true
		warn(`No part named "{MARKER_NAMES[desk]}" in Workspace, so the camera stays where it is.`)
	end
end

-- Runs every frame after the default camera, so nothing else can move the view.
local function step(dt: number)
	local camera = workspace.CurrentCamera
	local desk: Types.Desk? = wanted
	if not camera or not desk then
		return
	end
	if not goal then
		findGoal(desk)
	end
	local target = goal
	if not target then
		return
	end
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	if arrived then
		camera.CFrame = camera.CFrame:Lerp(target, 1 - math.exp(-GLIDE * dt))
	else
		camera.CFrame = target
		arrived = true
	end
end

function DeskCamera.show(desk: Types.Desk)
	wanted = desk
	goal = nil
	askedAt = os.clock()
	nextLookAt = 0
end

function DeskCamera.start()
	RunService:BindToRenderStep("DeskCamera", Enum.RenderPriority.Camera.Value + 1, step)
end

return DeskCamera
