--!strict
-- Types used on both sides of the network. This module holds no data.

export type Verdict = "Ship" | "Return"

export type Colour = "Red" | "Blue" | "Green" | "Yellow"
export type Shape = "Round" | "Square" | "Tall"

-- What an X-ray of a parcel shows.
export type Contents = {
	item: string, -- an id from ParcelDefs.Items
	colour: Colour,
	shape: Shape,
	handles: number,
}

-- The Scanner desk shows what is inside the parcel. The Clerk desk shows the rulebook.
export type Desk = "Scanner" | "Clerk"

-- What one player needs to know about their own desk. Sent only to that player.
export type DeskState = {
	desk: Desk,
	solo: boolean, -- alone in the server, so this player works both desks and may switch
	canStamp: boolean, -- whether this player may give the verdict
	peekLeft: number, -- solo: seconds of rulebook time left for this parcel
	peekEndsAt: number, -- solo: server clock time the rulebook closes, or 0 while it is shut
}

export type Trait = "colour" | "shape" | "handles"

-- One message on the ping board. The server builds it; a client only picks the stamp.
-- A trait or rule stamp with neither `value` nor `ruleId` is a question.
export type Ping = {
	seq: number, -- counts every ping since the server started
	deal: number, -- the rulebook in force when it was sent
	parcelSeq: number, -- the parcel on the desk when it was sent, or 0
	from: Desk,
	stamp: string, -- an id from StampDefs
	value: (string | number)?, -- the Scanner stating a trait of the parcel on the desk
	ruleId: string?, -- the Clerk showing a rule
}

-- The postal licence: a card of stamps, one earned per day played. Nothing is
-- lost by missing a day.
export type Licence = {
	stamps: number, -- on the current card
	cards: number, -- cards already filled
	lastStampDay: number, -- the day the last stamp was earned, counted in days since 1970 (UTC)
}

-- What is saved for a player.
export type PlayerSave = {
	version: number,
	licence: Licence,
	collection: { [string]: boolean }, -- ids from ParcelDefs.Items the player has handled correctly
}

-- What a player is told about their own progress. Sent only to that player.
export type Progress = {
	licence: Licence,
	licenceSlots: number, -- stamps on a full card
	collection: { [string]: boolean },
	saving: boolean, -- false when this session's progress cannot be saved
}

export type Phase = "Waiting" | "Running" | "Ended"
export type EndReason = "TimeUp" | "StruckOut"

-- The part of a shift every player may know. The server sends it whenever it changes.
export type PublicShiftState = {
	phase: Phase,
	endsAt: number, -- server clock time (workspace:GetServerTimeNow) at which the shift ends
	maxStrikes: number,
	strikes: number,
	correct: number,
	parcelSeq: number, -- number of the parcel on the desk, or 0 when the desk is empty
	deal: number, -- goes up each time the rules are picked: a new shift, or a change of team
	dailyRuleId: string, -- the rule of the day, which everyone may see; "" outside a shift
	endReason: EndReason?,
}

return {}
