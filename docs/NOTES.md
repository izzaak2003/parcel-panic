# Parcel Panic: how it works

Plain-language notes on every system, kept current as the game is built.

## Status

Milestones 3 and 4 of 6 are built and waiting for a playtest, along with the first part of milestone 5. Milestone 3 is the ping board, the parcel moving through the room, and feedback on every verdict. Milestone 4 is the rule of the day, the odd parcel, the postal licence, the collection book, and saving. From milestone 5, the no-menu start and the first-time prompts are built; the invite button, the game pass, and analytics are not. Milestone 2 (the two desks) is built and its solo side is approved.

Two things are checked only by simulation so far. Nothing has been played by two real people yet, and saving has not run against Roblox's real data store, which needs the place to be published.

## The toolchain

Roblox games are normally written inside Roblox Studio, where scripts are stored inside the game file. That makes version control and outside tools hard to use. This project keeps the code as ordinary files on disk instead.

| Tool | Version | What it does |
|---|---|---|
| Roblox Studio | current | The editor and engine. The 3D room, the UI layout, and playtesting live here. |
| Rokit | 1.2.0 | Installs the exact tool versions listed in `rokit.toml`, so every machine uses the same ones. |
| Rojo | 7.7.1 | Copies the `.luau` files in `src/` into the open Studio place and keeps them in sync as they change. Two halves: a command-line server (`rojo serve`) and a Studio plugin that connects to it. |
| Selene | 0.32.0 | Linter. Reads the code without running it and flags likely mistakes, such as unused variables or deprecated Roblox calls. |
| StyLua | 2.5.2 | Formatter. Rewrites code into one consistent layout so diffs show only real changes. |
| luau-lsp | 1.70.1 | Type checker. Every file is in strict mode, and this is what reports a type error before the game runs. |
| Studio MCP server | built in | Lets Claude Code look at the open place, start and stop playtests, and read the console, so changes are tested and not just written. |
| git and GitHub | git 2.47 | History and the public portfolio. |

`scripts/check.ps1` runs Selene, StyLua, and luau-lsp in one go.

## How code gets into the game

1. A file is edited in `src/`.
2. `rojo serve` notices and sends the change to the Rojo plugin in Studio.
3. The plugin updates the matching script inside the place.
4. A playtest runs the new code.

The file name decides what kind of script it becomes:

| File | Script type | Where it runs |
|---|---|---|
| `Name.server.luau` | Script | On Roblox's server. Players cannot read or change it. |
| `Name.client.luau` | LocalScript | On each player's own device. A cheating player can read and change it. |
| `Name.luau` | ModuleScript | Wherever it is `require`d from. A library of functions or data. |

The folder decides where it sits in the game:

| Folder | Location in Studio | Who can see it |
|---|---|---|
| `src/server/` | `ServerScriptService.Server` | Server only |
| `src/client/` | `StarterPlayer.StarterPlayerScripts.Client` | Copied to each player when they join |
| `src/shared/` | `ReplicatedStorage.Shared` | Server and every player |

## Terms

- **Place**: one level or scene. Studio opens and saves places.
- **Experience**: what Roblox calls a published game. It contains one or more places.
- **Instance**: any object in a place, such as a part, a script, a sound, or a button.
- **DataModel**: the tree that holds every instance in a place. In code it is the global `game`.
- **Service**: a top-level branch of the DataModel with a fixed job, such as `Workspace` (the 3D world) or `ReplicatedStorage` (things shared between server and players).
- **Server and client**: Roblox runs the game on its own machine (the server) and a copy on each player's device (a client). The server's version is the real one.
- **Replication**: Roblox copying instances from the server to the clients automatically. Anything in `Workspace` or `ReplicatedStorage` is replicated, so every player can read it.
- **RemoteEvent**: a named one-way message between server and client. It is the only way the two sides talk.
- **ScreenGui**: a container for 2D interface elements drawn over the 3D view.
- **Attribute**: a named value attached to an instance, editable in Studio's Properties panel.

## Systems

### The shift (`src/server/ShiftService.luau`)

The server runs one shift at a time for everyone in it. A shift is always in one of three phases:

| Phase | Meaning | Leaves when |
|---|---|---|
| Waiting | Nobody has played yet. | The first player arrives; the shift starts 2 seconds later. |
| Running | Parcels arrive one at a time. | The timer runs out ("TimeUp") or mistakes reach the limit ("StruckOut"). |
| Ended | The results are on screen. | A player presses Play again, or a new player arrives. |

While a shift is running, the desk is either empty or holds exactly one parcel waiting for a verdict. When a verdict arrives, the server clears the desk first, then scores it, then schedules the next parcel 1.5 seconds later. Clearing first is what makes a second request for the same parcel fail.

The server splits what it knows in two:

- **Public state**: phase, time the shift ends, mistakes, correct count, the number of the parcel on the desk, a number that goes up each time the rules are picked, and the rule of the day. Sent to every player whenever it changes.
- **Hidden state**: the rules and what is inside the parcel. Sent only through two dedicated messages, and only to players entitled to them: the rulebook to the Clerk desk, the contents to the Scanner desk.

### The desks (`src/server/DeskService.luau`, `src/server/DeskPlan.luau`)

There are two desks. The Scanner desk shows what is inside the parcel. The Clerk desk shows the rulebook.

**Two or more players.** The desks are split and nobody can switch. A newcomer goes to the desk with fewer people, and if someone leaving empties a desk, the newest player moves across to fill it. Only the Clerk desk can stamp Ship or Return, so the Scanner has to tell the Clerk what is inside. Extra players double up: three players is two Scanners and a Clerk.

**One player.** A player alone works both desks, one at a time, and can stamp from either. They start at the X-ray and can open the rulebook, but only for 15 seconds per parcel. Closing it early saves the unused time. When it runs out the server sends them back to the X-ray and the rulebook stays shut until the next parcel. So solo play is: look, check the rules while they are still needed, then work from memory.

`DeskPlan` is the seating logic on its own, with no Roblox calls in it, which is why it could be tested with made-up players. `DeskService` holds who sits where, stands each character at their desk and freezes them there, and runs the rulebook timer.

**When the team changes.** Someone who was alone has seen both halves, and someone moved across to fill an empty desk has seen the other side. So whenever a player joins or leaves and two or more remain, the server picks new rules and replaces the parcel on the desk, at no cost to the team. Whatever anyone saw before is then out of date, which also makes leaving and rejoining pointless. The alternative was to track who had been sent what; dealing again is simpler and cannot miss a case.

This is checked by `tests/Simulate.luau`. Studio's automated playtest has only one player, so the simulation loads the real server code with made-up players and fake messages, walks them through joining, leaving, and rejoining, and checks after every step that no Scanner holds the rulebook in force and no Clerk holds the parcel on the desk. With the re-deal switched off it reports exactly that leak.

A lone player is sent both halves of the hidden information, because they are entitled to both. The 15-second limit is therefore a rule the game shows, not a secret the server keeps, and a modified client could keep the rules on screen. The split that the server does enforce is between different players.

### Parcels and rules as data (`src/shared/ParcelDefs.luau`, `src/shared/RuleDefs.luau`)

A parcel holds one of six ordinary items, or now and then the odd one, in one of four colours. Each item has a fixed shape and number of handles. A rule is a row that names a trait value, such as "two handles" or "red", and sends anything matching it back. A parcel that matches no rule is shipped.

Adding an item, a colour, or a rule means adding a row to a table. No logic changes.

### Choosing rules and parcels (`src/server/Rulebook.luau`, `src/server/ParcelGenerator.luau`)

At the start of a shift the server takes the rule of the day and picks two more at random. It then lists every ordinary parcel there could be (six items in four colours, so 24) and sorts them into two piles: those the rules ship and those the rules send back. If either pile is empty it picks different rules.

For each new parcel the server first decides whether it should be a "send back" (half the time), then picks a random parcel from that pile. This keeps the game balanced whatever the rules are.

Both files are server-only. If the client could run them, it could work out the answer.

### Messages (`src/shared/Remotes.luau`, declared in `default.project.json`)

| Message | Direction | Carries |
|---|---|---|
| `ShiftSync` | server to all | The public state |
| `RulebookShown` | server to a player | The ids of this shift's rules |
| `ParcelScanned` | server to a player | Parcel number and contents |
| `VerdictJudged` | server to all | Parcel number, the verdict given, whether it was right |
| `DeskSync` | server to a player | That player's desk, whether they are alone, whether they may stamp, and their rulebook time |
| `PingShown` | server to all | One stamp on the ping board: who sent it, which stamp, and whatever the server attached |
| `ProgressSync` | server to a player | That player's licence and collection book, and whether they are being saved |
| `SubmitVerdict` | client to server | Parcel number and "Ship" or "Return" |
| `RequestShift` | client to server | Nothing; asks for a new shift |
| `RequestSwitch` | client to server | Nothing; a lone player asks to move to the other desk |
| `SendPing` | client to server | A stamp id, the rulebook and parcel the player was looking at, and, for the rule stamp, which rule |

The server treats the four client messages as untrusted. `src/server/RateLimit.luau` limits each kind of request separately, so a stamp does not swallow a desk switch made just after: verdicts, shift requests, and desk switches are one per 0.25 seconds, and pings are four in a row and then one a second. Before acting on a verdict the server checks, in order: the player is within that limit; the player is allowed to stamp; the parcel number is a number and the verdict is exactly "Ship" or "Return"; a shift is running; there is a parcel on the desk; the number matches that parcel. Anything else is ignored. The client never says whether the verdict was right; the server works that out itself.

### The ping board (`src/shared/StampDefs.luau`, `src/server/PingService.luau`, `src/client/PingUi.luau`)

Most young players on Roblox cannot use chat, so the game has its own way to talk: eight stamps. A stamp is a ready-made message, and nobody types anything.

| Stamp | From the Scanner desk | From the Clerk desk |
|---|---|---|
| Handles, Colour, Shape | States it: "Colour: Red" | Asks: "Colour?" |
| Rule says | Asks: "Which rule?" | Shows one rule from the rulebook |
| Yes, No, ?, Hurry! | Says just that | Says just that |

A desk states what it knows and asks about what it does not. So the Scanner can tell the Clerk what is inside, the Clerk can teach the Scanner the rules, and either can answer the other with Yes or No.

The client says which stamp was pressed and what it was looking at. The server builds the message. For "Colour" from the Scanner it looks up the colour of the parcel on the desk itself, so a stamp cannot say anything untrue and a player cannot send a value for a parcel they were never shown. For "Rule says" from the Clerk the client sends a place in the rulebook (1, 2, or 3) and the server checks that such a rule exists.

A player may send four stamps in a row and then one a second, which is enough for the Scanner's three traits and stops anyone burying the board. Sending a stamp that is already showing moves it to the bottom without a sound. Stamps about a parcel are cleared when that parcel is judged; a rule stays up until the rulebook changes. Each request also says which rulebook and parcel the player was looking at, and the server drops it if either has moved on.

The stamps are rows in a data module. Adding one is adding a row.

This design was built without the paper test the design report asked for (two friends who stay silent, to see whether they can solve a rule in 20 seconds). It still needs that test with real people.

### The rule of the day and the odd parcel (`src/server/Rulebook.luau`, `src/server/Calendar.luau`, `src/server/ParcelGenerator.luau`)

Every shift has three rules. The first is the rule of the day: it is worked out from the date alone, so it is the same for every player in the world that day and different tomorrow. Unlike the other two rules it is shown to both desks. It could not have been kept secret anyway, because this code is public and anyone could work it out from the date; so the game makes it something everyone knows, and a reason to look in each day. The other two rules are picked at random and stay with the Clerk.

"Today" is always the server's clock in UTC, never a player's device, and it is fixed when the shift starts.

About one parcel in 25 holds the odd item, a Singing Snow Globe. It is judged by the rules like anything else. It is a small surprise that is earned in play and costs nothing.

### Saved progress (`src/server/PlayerData.luau`)

Two things are kept between visits.

- **The postal licence.** A card with six stamp slots. A new player's first stamp is a gift, so the card never starts empty. One more is earned on any day the player is at a desk for ten correctly handled parcels in one shift. It arrives the moment the tenth is handled, not at the end, so leaving early does not lose it and joining at the last second does not win it. Missing a day loses nothing; there are no streaks. A seventh stamp starts a new card.
- **The collection book.** One slot for each kind of item, filled the first time the player's team handles that item correctly.

Roblox stores this in a DataStore, its key-value save system, and a call to it can fail or be slow at any time. The rules the code follows:

- If a player's data cannot be loaded after four tries, the player still plays, on a fresh card that lasts only for that visit, and is told it is not being saved. That player is never saved. Writing a fresh card over real progress is the one mistake that cannot be undone.
- A save never replaces what is stored. It reads the stored copy and adds to it: the licence that is further along wins, the collections are joined, and finished shifts are added on. So if a player has already hopped to another server and earned something there, neither server can undo the other.
- Only one save runs at a time for a player. A second request made meanwhile waits and then runs once.
- A failed save is tried again, waiting longer each time.
- Progress is saved when a stamp is earned, when the player leaves, and once a minute if anything has changed. A stamp earned within 15 seconds of the last save waits for the next of those, so a burst of rewards is not a burst of writes.
- If the save made when a player leaves fails every try, their progress is kept on the server and tried again each minute and at shutdown.
- When the server shuts down it saves everyone at once, including those players, and keeps trying whatever fails until a deadline.
- Data saved by a newer version of the game is shown but never written, and item ids this version does not know are kept in what it writes. So during an update, a server still running old code cannot erase what a new one saved.
- Studio playtests use a separate store, so test settings can never change real players' progress.
- Whatever comes back from the store is checked field by field before it is used, so damaged or out-of-date data is repaired instead of trusted.

All of this is tested in the simulation against a stand-in store that can be told to fail or be slow. It has not yet run against Roblox's real store, because that needs the place to be published.

### What the player's device keeps (`src/client/ShiftClient.luau`)

One module on the client holds the latest of everything the server has sent and is the only one that talks to the server. The screen, the camera, the parcel in the room, and the sounds all read from it and are told when something changes. That keeps every server message handled in exactly one place.

For the first half second after joining it updates what is shown but does not announce verdicts or pings. Messages that built up while the game was loading all arrive at once then, and without this a new player would get a burst of old stamps and sounds.

### The desk screen (`src/client/DeskUi.luau`)

The layout lives in the Studio place as `StarterGui.DeskGui`. The code redraws from what `ShiftClient` holds. It decides nothing: pressing Ship sends a request and the screen changes only when the server answers.

It shows only the half that belongs to the player's desk: the X-ray panel at the Scanner desk, the rules panel at the Clerk desk. The stamp buttons appear only for a player allowed to stamp, and the switch button only for a player who is alone. One line of text above the buttons says what to do next.

The countdowns are the one thing worked out on the client. The server sends each deadline once, and the client subtracts the shared server clock from it four times a second.

### The first minute (`src/client/Tutorial.luau`, and `onRosterChanged` in `src/server/ShiftService.luau`)

There is no menu. A shift starts two seconds after a player arrives and the first parcel comes three seconds after that, so a new player has something to do within about six seconds of joining. If they arrive while an earlier shift's results are showing, the next shift starts by itself.

A player whose collection book is empty is treated as new and gets three short prompts on their first parcel: what the X-ray is, to open the rulebook, and to stamp. Each one moves on when the player does it, or after a few seconds, and the first verdict ends them. They never block the game. There is a different set of three for each desk when the desks are split.

Using the empty collection book as the sign of a new player means nothing extra has to be saved to remember that the prompts were shown.

### The camera (`src/client/DeskCamera.luau`)

The camera does not follow the character. Each desk has an invisible marker part in the room, and the camera sits exactly where that part is, facing the way it faces. Moving or turning the part in Studio changes the view. When a lone player switches desks the camera glides to the other marker.

### Tuning (`src/server/Config.luau`)

Shift length, mistake limit, delays, rulebook time, and the share of parcels that go back are numbers in one file. In Studio only, adding a number attribute named `Test_<Key>` to `ServerScriptService` overrides one for the next playtest. For example `Test_ShiftSeconds = 30` gives a 30-second shift. Published servers ignore these.

### The parcel in the room (`src/client/ParcelView.luau`, `src/client/Belt.luau`)

The box on the conveyor is drawn by each player's own device, from the public state. When the server says a parcel is on the desk, the box rides in from the IN hatch and stops under the scanner. When the verdict comes, it gets a SHIP or RETURN stamp and leaves: along the belt to the Ship hatch, or off the back and down the red chute. If the parcel is taken away without a verdict (the shift ended or the team changed) it shrinks away.

Drawing it on the client keeps the movement smooth and costs the server nothing. The belt's stripes slide along for as long as a parcel is travelling, which is what makes the belt look as if it runs.

The box is the same plain box every time. What is inside is never put in the 3D world, because every client can read the 3D world.

### Feedback (`src/client/Feedback.luau`)

Every verdict gets a small reaction: the "Correct!" or "Mistake!" label pops in, the counter that changed ticks, and a short sound plays. A change of rulebook in the middle of a shift gets a notice and a bell. Nothing shakes or flashes.

Sounds are `Sound` objects in `SoundService.Sfx` in the Studio place, found by name. A missing one is skipped, so they can be swapped or deleted in Studio freely. The five there now came from the free Pro Sound Effects library on the Creator Store and were chosen from their descriptions without being heard. There is no sound for a correct verdict yet, because nothing suitable could be picked blind.

### The room (`Workspace.PostOffice` in the Studio place)

The post office is one room built from about 340 plain parts, grouped into one Model per area so an area can be rebuilt without touching the others.

| Model | What it is |
|---|---|
| `Shell` | Floor, two-tone walls, two wide windows, timber beams, glass roof |
| `Conveyor` | The belt across the room, the yellow IN hatch on the left wall, the green SHIP hatch on the right |
| `ScanStation` | The yellow plate parcels stop on (`ParcelSpot`) and the X-ray head hanging over it |
| `ReturnChute` | The red slide off the back of the belt into the RETURN bin |
| `ScannerDesk`, `ClerkDesk` | The two desks, each with a nameplate and props; the rules board stands beside the Clerk's |
| `Markers` | Invisible parts: where each desk's player stands, where each desk's camera sits, and the points on the parcel's path |
| `Rug`, `Decor`, `Lights`, `Outside` | Rug, shelves, doors, pigeonholes, sacks, trolley, clock, posters, lamps, and the trees seen through the windows |

The layout answers a problem from the first playtest, where the parcel looked like something to pick up. It now arrives on a belt and stops under a scanner, with the two places it can go in view, so it reads as an object being inspected.

The code depends on `ParcelSpot` and the markers, and uses the conveyor's stripes if they are there. Everything else is scenery.

## Names the code depends on

The code looks these up by name in the Studio place. Renaming or deleting one breaks the game; moving, resizing, recolouring, and restyling are all safe.

Where the type says "any element", the code only shows, hides, or recolours it, so a Frame can be swapped for an ImageLabel or a ScrollingFrame. A TextLabel must stay a TextLabel and a TextButton must stay a TextButton.

`Workspace`:

| Name | Type | Used for |
|---|---|---|
| `ParcelSpot` | any part, anywhere in Workspace (currently in `PostOffice.ScanStation`) | Parcels appear on top of it. Keep only one: if there are two, the first one found is used. |
| `ScannerSpot`, `ClerkSpot` | any part (in `PostOffice.Markers`, invisible) | Where a player at that desk stands. The part's front is the way they face. |
| `ScannerCamera`, `ClerkCamera` | any part (in `PostOffice.Markers`, invisible) | The camera for that desk: it sits at the part and looks the way the part's front points. |
| `ParcelIn`, `ParcelShip` | any part (in `PostOffice.Markers`, invisible) | Where the middle of a parcel is when it enters, and when it leaves by the Ship hatch. Optional: without them the parcel appears and disappears in place. |
| `ReturnTop`, `ReturnBin` | any part (in `PostOffice.Markers`, invisible) | The top of the Return chute and the bin at the bottom. Optional. |
| `Conveyor` holding `Belt` and `Stripe` parts | a Model, one part, and any number of parts | The stripes slide along the belt while a parcel travels. `Belt` and the stripes must be direct children of `Conveyor`. The belt's length is its X size, and its right side points the way parcels travel. Optional: without them the belt stays still. |

`StarterGui.DeskGui` (a ScreenGui with `ResetOnSpawn` off):

| Path | Type | Shows |
|---|---|---|
| `TopBar` | any element | Holds the three labels below |
| `TopBar.TimerLabel` | TextLabel | Time left |
| `TopBar.StrikesLabel` | TextLabel | Mistakes so far |
| `TopBar.CorrectLabel` | TextLabel | Parcels handled correctly |
| `ScannerPanel` | any element | Holds the X-ray |
| `ScannerPanel.EmptyLabel` | TextLabel | Text shown when there is no parcel |
| `ScannerPanel.Contents` | any element | Shown only while a parcel is on the desk |
| `ScannerPanel.Contents.ItemLabel` | TextLabel | Item name |
| `ScannerPanel.Contents.ColourSwatch` | any element | Item colour, applied to its background, so keep the background visible |
| `ScannerPanel.Contents.ColourLabel` | TextLabel | Colour name |
| `ScannerPanel.Contents.ShapeLabel` | TextLabel | Shape |
| `ScannerPanel.Contents.HandlesLabel` | TextLabel | Handle count |
| `ClerkPanel` | any element | Holds the rule list |
| `ClerkPanel.RuleList` | any element with a layout sorted by LayoutOrder | Holds one row per rule. Put no other TextButton in it: every one except the template is cleared when the rulebook changes. |
| `ClerkPanel.RuleList.RuleTemplate` | TextButton, hidden | Copied once per rule. Pressing a copy shows that rule on the ping board. |
| `RoleLabel` | TextLabel | Which desk the player is at |
| `HintLabel` | TextLabel | One line saying what to do next |
| `SwitchPanel` | any element | Shown only to a player who is alone |
| `SwitchPanel.SwitchButton` | TextButton | Opens or closes the rulebook |
| `SwitchPanel.PeekLabel` | TextLabel | Rulebook time left for this parcel |
| `VerdictBar` | any element | Holds the two buttons; shown only to a player who may stamp |
| `VerdictBar.ShipButton` | TextButton | Ship |
| `VerdictBar.ReturnButton` | TextButton | Return |
| `FeedbackLabel` | TextLabel | "Correct!" or "Mistake!" after a verdict; its background is coloured by code |
| `NoticeLabel` | TextLabel | A short notice, such as a change of rulebook |
| `TutorialLabel` | TextLabel | The first-time prompts; it sits over the hint line while they run |
| `PingBar` | any element with a layout | Holds one button per stamp; shown only when the desks are split |
| `PingBar.StampTemplate` | TextButton, hidden | Copied once per stamp |
| `PingFeed` | any element with a layout sorted by LayoutOrder | Holds the most recent pings. Put no other TextLabel in it. |
| `PingFeed.PingTemplate` | TextLabel, hidden | Copied once per ping |
| `EndPanel` | any element | Shown when the shift ends |
| `EndPanel.EndTitle` | TextLabel | Result heading |
| `EndPanel.EndSummary` | TextLabel | Score |
| `EndPanel.PlayAgainButton` | TextButton | Starts a new shift |
| `EndPanel.LicenceLabel` | TextLabel | How many stamps are on the licence card |
| `EndPanel.LicenceCard` | any element with a layout sorted by LayoutOrder | Holds one slot per stamp |
| `EndPanel.LicenceCard.SlotTemplate` | TextLabel, hidden | Copied once per slot; a stamped slot gets a tick and its background is coloured by code |
| `EndPanel.CollectionBook` | any element with a layout sorted by LayoutOrder | Holds one label per kind of item |
| `EndPanel.CollectionBook.ItemTemplate` | TextLabel, hidden | Copied once per item; shows its name once found, and its background is coloured by code |
| `EndPanel.SaveNotice` | TextLabel | Shown when this visit's progress is not being saved |
| `DailyLabel` | TextLabel | The rule of the day, shown to both desks while a shift runs |

`ServerScriptService` attributes (Studio only, all optional):

| Name | Type | Used for |
|---|---|---|
| `Test_<Key>` | number | Overrides the setting `<Key>` from `src/server/Config.luau` for playtests, for example `Test_ShiftSeconds`. Ignored on live servers. |

`SoundService.Sfx` (a Folder of Sounds, all optional):

| Name | Plays when |
|---|---|
| `Arrive` | A parcel rides in |
| `Stamp` | Any verdict is given, and when a licence stamp is earned |
| `Mistake` | The verdict was wrong |
| `Correct` | The verdict was right (not there yet) |
| `Ping` | Anyone sends a stamp |
| `NewRules` | The rulebook changes in the middle of a shift, and when the odd parcel arrives |
