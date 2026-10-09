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
