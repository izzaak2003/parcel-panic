--!strict
-- The small reactions that make an action feel as if it landed: the verdict
-- stamp popping up, a counter ticking, a short sound, and a notice when the
-- rulebook changes. Nothing here shakes the screen or flashes.
--
-- Sounds are Sound instances in SoundService.Sfx in the Studio place, found by
-- name. A missing sound is skipped without complaint, so sounds can be swapped
-- or removed in Studio freely.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Gui = require(script.Parent.Gui)
local ShiftClient = require(script.Parent.ShiftClient)
local Types = require(ReplicatedStorage.Shared.Types)

local POP = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FEEDBACK_SECONDS = 1.2
local NOTICE_SECONDS = 2.5
local RIGHT = Color3.fromRGB(76, 187, 106)
local WRONG = Color3.fromRGB(226, 76, 68)

local Feedback = {}

function Feedback.play(name: string)
	local folder = SoundService:FindFirstChild("Sfx")
	local sound = folder and folder:FindFirstChild(name)
	if sound and sound:IsA("Sound") then
		SoundService:PlayLocalSound(sound)
	end
end

-- Starts the element a little too big or too small and lets it settle to its real size.
local function scaleOf(target: GuiObject): UIScale
	local existing = target:FindFirstChildOfClass("UIScale")
	if existing then
		return existing
	end
	local made = Instance.new("UIScale")
	made.Parent = target
	return made
end

local function pop(target: GuiObject, from: number)
	local scale = scaleOf(target)
	scale.Scale = from
	TweenService:Create(scale, POP, { Scale = 1 }):Play()
end

-- Shows the element for a while. A later call for the same element takes over.
local showCount: { [GuiObject]: number } = {}
local function showFor(target: GuiObject, seconds: number)
	local mine = (showCount[target] or 0) + 1
	showCount[target] = mine
	target.Visible = true
	task.delay(seconds, function()
		if showCount[target] == mine then
			target.Visible = false
		end
	end)
end

function Feedback.start()
	local gui = Gui.root()
	local topBar = Gui.element(gui, "TopBar")
	local strikesLabel = Gui.label(topBar, "StrikesLabel")
	local correctLabel = Gui.label(topBar, "CorrectLabel")
	local feedbackLabel = Gui.label(gui, "FeedbackLabel")
	local noticeLabel = Gui.label(gui, "NoticeLabel")

	ShiftClient.onVerdict(function(_seq: number, _verdict: Types.Verdict, wasCorrect: boolean)
		feedbackLabel.Text = if wasCorrect then "Correct!" else "Mistake!"
		feedbackLabel.BackgroundColor3 = if wasCorrect then RIGHT else WRONG
		pop(feedbackLabel, 1.5)
		showFor(feedbackLabel, FEEDBACK_SECONDS)
		Feedback.play("Stamp")
		Feedback.play(if wasCorrect then "Correct" else "Mistake")
	end)

	local before: Types.PublicShiftState? = nil
	ShiftClient.onChanged(function()
		local state = ShiftClient.getState()
		local previous = before
		before = state
		if not state or not previous or not ShiftClient.isLive() then
			return
		end
		if state.strikes > previous.strikes then
			pop(strikesLabel, 1.35)
		end
		if state.correct > previous.correct then
			pop(correctLabel, 1.35)
		end
		if
			state.phase == "Running"
			and state.parcelSeq > 0
			and state.parcelSeq ~= previous.parcelSeq
		then
			Feedback.play("Arrive")
		end
		-- New rules in the middle of a shift mean someone joined or left.
		if
			state.phase == "Running"
			and previous.phase == "Running"
			and state.deal ~= previous.deal
		then
			noticeLabel.Text = "Team changed: new rulebook!"
			pop(noticeLabel, 0.7)
			showFor(noticeLabel, NOTICE_SECONDS)
			Feedback.play("NewRules")
		end
	end)
end

return Feedback
