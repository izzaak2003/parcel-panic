--!strict
-- Finds the marker parts in the Studio place that say where things go: where
-- the camera sits, where a parcel comes in, where it leaves. docs/NOTES.md
-- lists them. A marker may not have reached this player yet, so a miss is
-- never remembered: asking again later can succeed.
local Markers = {}

local found: { [string]: BasePart } = {}

function Markers.find(name: string): BasePart?
	local cached = found[name]
	if cached and cached:IsDescendantOf(workspace) then
		return cached
	end
	found[name] = nil
	local part = workspace:FindFirstChild(name, true)
	if part and part:IsA("BasePart") then
		found[name] = part
		return part
	end
	return nil
end

return Markers
