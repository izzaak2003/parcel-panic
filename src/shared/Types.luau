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
	endReason: EndReason?,
}

return {}
