# Parcel Panic: how it works

Plain-language notes on every system, kept current as the game is built.

## Status

Milestone 2 of 6 is built and waiting for a playtest: the two desks. A player alone works both desks one at a time with limited rulebook time; two or more players are split between them. Saving and the ping board are not built yet, and nothing with two players has been tested.

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
| Ended | The results are on screen. | A player presses Play again. |

While a shift is running, the desk is either empty or holds exactly one parcel waiting for a verdict. When a verdict arrives, the server clears the desk first, then scores it, then schedules the next parcel 1.5 seconds later. Clearing first is what makes a second request for the same parcel fail.

The server splits what it knows in two:

- **Public state**: phase, time the shift ends, mistakes, correct count, and the number of the parcel on the desk. Sent to every player whenever it changes.
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

A parcel holds one of six items in one of four colours. Each item has a fixed shape and number of handles. A rule is a row that names a trait value, such as "two handles" or "red", and sends anything matching it back. A parcel that matches no rule is shipped.

Adding an item, a colour, or a rule means adding a row to a table. No logic changes.

### Choosing rules and parcels (`src/server/Rulebook.luau`, `src/server/ParcelGenerator.luau`)

At the start of a shift the server picks three rules at random. It then lists all 24 possible parcels and sorts them into two piles: those the rules ship and those the rules send back. If either pile is empty it picks different rules.

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
| `SubmitVerdict` | client to server | Parcel number and "Ship" or "Return" |
| `RequestShift` | client to server | Nothing; asks for a new shift |
| `RequestSwitch` | client to server | Nothing; a lone player asks to move to the other desk |

The server treats the three client messages as untrusted. Before acting on a verdict it checks, in order: the player has not sent a request in the last 0.25 seconds (`src/server/RateLimit.luau`, which keeps a separate clock for each kind of request, so a stamp does not swallow a desk switch made just after); the player is allowed to stamp; the parcel number is a number and the verdict is exactly "Ship" or "Return"; a shift is running; there is a parcel on the desk; the number matches that parcel. Anything else is ignored. The client never says whether the verdict was right; the server works that out itself.

### The desk screen (`src/client/DeskUi.luau`)

The layout lives in the Studio place as `StarterGui.DeskGui`. The code keeps the latest copy of each server message and redraws from those. It decides nothing: pressing Ship sends a request and the screen changes only when the server answers.

It shows only the half that belongs to the player's desk: the X-ray panel at the Scanner desk, the rules panel at the Clerk desk. The stamp buttons appear only for a player allowed to stamp, and the switch button only for a player who is alone. One line of text above the buttons says what to do next.

The countdowns are the one thing worked out on the client. The server sends each deadline once, and the client subtracts the shared server clock from it four times a second.

### The camera (`src/client/DeskCamera.luau`)

The camera does not follow the character. Each desk has an invisible marker part in the room, and the camera sits exactly where that part is, facing the way it faces. Moving or turning the part in Studio changes the view. When a lone player switches desks the camera glides to the other marker.

### Tuning (`src/server/Config.luau`)

Shift length, mistake limit, delays, rulebook time, and the share of parcels that go back are numbers in one file. In Studio only, adding a number attribute named `Test_<Key>` to `ServerScriptService` overrides one for the next playtest. For example `Test_ShiftSeconds = 30` gives a 30-second shift. Published servers ignore these.

### The parcel in the room (`src/server/ParcelProp.luau`)

When a parcel arrives, the server puts a plain cardboard box on top of the part named `ParcelSpot`. The box looks the same every time. What is inside is never put in the 3D world, because every client can read the 3D world.

### The room (`Workspace.PostOffice` in the Studio place)

The post office is one room built from about 340 plain parts, grouped into one Model per area so an area can be rebuilt without touching the others.

| Model | What it is |
|---|---|
| `Shell` | Floor, two-tone walls, two wide windows, timber beams, glass roof |
| `Conveyor` | The belt across the room, the yellow IN hatch on the left wall, the green SHIP hatch on the right |
| `ScanStation` | The yellow plate parcels stop on (`ParcelSpot`) and the X-ray head hanging over it |
| `ReturnChute` | The red slide off the back of the belt into the RETURN bin |
| `ScannerDesk`, `ClerkDesk` | The two desks, each with a nameplate and props; the rules board stands beside the Clerk's |
| `Markers` | Four invisible parts: where each desk's player stands and where each desk's camera sits |
| `Rug`, `Decor`, `Lights`, `Outside` | Rug, shelves, doors, pigeonholes, sacks, trolley, clock, posters, lamps, and the trees seen through the windows |

The layout answers a problem from the first playtest, where the parcel looked like something to pick up. It now arrives on a belt and stops under a scanner, with the two places it can go in view, so it reads as an object being inspected.

The code depends on five parts here: `ParcelSpot` and the four markers. Everything else is scenery.

## Names the code depends on

The code looks these up by name in the Studio place. Renaming or deleting one breaks the game; moving, resizing, recolouring, and restyling are all safe.

Where the type says "any element", the code only shows, hides, or recolours it, so a Frame can be swapped for an ImageLabel or a ScrollingFrame. A TextLabel must stay a TextLabel and a TextButton must stay a TextButton.

`Workspace`:

| Name | Type | Used for |
|---|---|---|
| `ParcelSpot` | any part, anywhere in Workspace (currently in `PostOffice.ScanStation`) | Parcels appear on top of it. Keep only one: if there are two, the first one found is used. |
| `ScannerSpot`, `ClerkSpot` | any part (in `PostOffice.Markers`, invisible) | Where a player at that desk stands. The part's front is the way they face. |
| `ScannerCamera`, `ClerkCamera` | any part (in `PostOffice.Markers`, invisible) | The camera for that desk: it sits at the part and looks the way the part's front points. |

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
| `ClerkPanel.RuleList` | any element | Holds one row per rule |
| `ClerkPanel.RuleList.RuleTemplate` | TextLabel, hidden | Copied once per rule |
| `RoleLabel` | TextLabel | Which desk the player is at |
| `HintLabel` | TextLabel | One line saying what to do next |
| `SwitchPanel` | any element | Shown only to a player who is alone |
| `SwitchPanel.SwitchButton` | TextButton | Opens or closes the rulebook |
| `SwitchPanel.PeekLabel` | TextLabel | Rulebook time left for this parcel |
| `VerdictBar` | any element | Holds the two buttons; shown only to a player who may stamp |
| `VerdictBar.ShipButton` | TextButton | Ship |
| `VerdictBar.ReturnButton` | TextButton | Return |
| `FeedbackLabel` | TextLabel | "Correct!" or "Mistake!" after a verdict |
| `EndPanel` | any element | Shown when the shift ends |
| `EndPanel.EndTitle` | TextLabel | Result heading |
| `EndPanel.EndSummary` | TextLabel | Score |
| `EndPanel.PlayAgainButton` | TextButton | Starts a new shift |
