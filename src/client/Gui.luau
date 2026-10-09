--!strict
-- Finds the pieces of the on-screen layout, StarterGui.DeskGui, which is built
-- in Studio. The names are a contract with the place: docs/NOTES.md lists them.
local Players = game:GetService("Players")

local Gui = {}

local LAYOUT_WAIT = 30 -- for the layout itself, which appears when the character first spawns
local PIECE_WAIT = 5 -- for a piece of it, which arrives with the layout or not at all

function Gui.child(parent: Instance, name: string, seconds: number?): Instance
	local found = parent:WaitForChild(name, seconds or PIECE_WAIT)
	if not found then
		error(`{parent:GetFullName()} has no child named "{name}". See docs/NOTES.md.`)
	end
	return found
end

-- Anything the code only shows, hides, or recolours can be any kind of GUI
-- element, so a Frame can be swapped for an ImageLabel or a ScrollingFrame in Studio.
function Gui.element(parent: Instance, name: string): GuiObject
	local found = Gui.child(parent, name)
	assert(found:IsA("GuiObject"), `{found:GetFullName()} must be a GUI element`)
	return found
end

function Gui.label(parent: Instance, name: string): TextLabel
	local found = Gui.child(parent, name)
	assert(found:IsA("TextLabel"), `{found:GetFullName()} must be a TextLabel`)
	return found
end

function Gui.button(parent: Instance, name: string): TextButton
	local found = Gui.child(parent, name)
	assert(found:IsA("TextButton"), `{found:GetFullName()} must be a TextButton`)
	return found
end

local root: Instance? = nil
local rootMissing = false

function Gui.root(): Instance
	local existing = root
	if existing then
		return existing
	end
	-- Having waited for the layout once, do not make every screen wait again.
	if rootMissing then
		error("StarterGui.DeskGui never arrived")
	end
	rootMissing = true
	local playerGui = Gui.child(Players.LocalPlayer, "PlayerGui", LAYOUT_WAIT)
	local gui = Gui.child(playerGui, "DeskGui", LAYOUT_WAIT)
	if gui:IsA("ScreenGui") and gui.ResetOnSpawn then
		warn(
			"DeskGui.ResetOnSpawn is on, so the desk will stop updating after a respawn. Turn it off."
		)
	end
	root = gui
	rootMissing = false
	return gui
end

-- Removes every copy made from `template` inside `list`, leaving the template.
function Gui.clearCopies(list: Instance, template: Instance)
	for _, item in list:GetChildren() do
		if item ~= template and item.ClassName == template.ClassName then
			item:Destroy()
		end
	end
end

return Gui
