--!strict
-- The parcel players see in the room. It is the same plain box every time:
-- what is inside never goes into the 3D world, where every client could read it.
local SPOT_NAME = "ParcelSpot"
local PARCEL_SIZE = Vector3.new(3, 2, 2)
local PARCEL_COLOUR = Color3.fromRGB(181, 137, 87)

local ParcelProp = {}

local current: Part? = nil
local spot: BasePart? = nil
local warned = false

-- Searches Workspace once and remembers the answer until that part is removed.
local function findSpot(): BasePart?
	if spot and spot:IsDescendantOf(workspace) then
		return spot
	end
	spot = nil
	local found = workspace:FindFirstChild(SPOT_NAME, true)
	if found and found:IsA("BasePart") then
		spot = found
		return found
	end
	if not warned then
		warned = true
		warn(`No part named "{SPOT_NAME}" in Workspace, so parcels will not appear in the room.`)
	end
	return nil
end

function ParcelProp.hide()
	if current then
		current:Destroy()
		current = nil
	end
end

function ParcelProp.show()
	ParcelProp.hide()
	local desk = findSpot()
	if not desk then
		return
	end

	local part = Instance.new("Part")
	part.Name = "Parcel"
	part.Size = PARCEL_SIZE
	part.Color = PARCEL_COLOUR
	part.Material = Enum.Material.Cardboard
	part.Anchored = true
	part.CanCollide = false
	part.CFrame = desk.CFrame * CFrame.new(0, (desk.Size.Y + PARCEL_SIZE.Y) / 2, 0)
	part.Parent = workspace
	current = part
end

return ParcelProp
