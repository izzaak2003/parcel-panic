# Parcel Panic

Co-op Roblox game, version one. A bright daytime post office for odd creatures, 1-4 players. The Scanner sees inside each parcel; the Clerk holds a rulebook that changes daily. Together they Ship or Return each parcel. Shifts last 8-10 minutes and three mistakes end the shift.

## Spec

Read both reports before any design or scope decision.

- `docs/compass_artifact_wf-47397798-09c6-52c8-874f-9e88fede7a97_text_markdown(1).md` is report 1: stack, setup order, and known failure modes of AI-written Roblox code. Its game concept (Night Desk) is superseded.
- `docs/compass_artifact_wf-b4cadeeb-a484-50e7-b0a9-439e3d270a05_text_markdown.md` is report 2: the Parcel Panic design. Where the reports conflict, report 2 wins.

## Roles

Claude is lead engineer: writes the code and builds the room, the map, and the UI layout through MCP. Isaac is product owner: playtests, decides, and polishes at the end. Isaac is a CS student, comfortable with the command line and git, with about 10 hours a week for 6 weeks. Isaac likes the technical detail and does not want to do the visual building.

Isaac dropped the tutoring part of the original brief on 2026-10-09: no walkthroughs, comprehension questions, or assigned Studio exercises.

## Scope

Version one is section 6 of report 2 and nothing else:

1. No-menu cold open: first parcel within 10 seconds of spawning, tutorial is three prompts.
2. Ping board: eight stamps (check, cross, handle, colour, shape, "rule says", "?", "hurry") shown on the partner's screen.
3. Solo as a real mode: desk-switch key and a 15-second rule peek per parcel.
4. Moderate juice on every verdict: stamp thud, parcel tween, short sound, counter tick. No screen shake, no flashing.
5. Endowed progress: postal licence card with 6 stamp slots, the first given free on day 1.
6. Daily rule of the day (date-seeded, no penalty for missing a day) plus one rare odd parcel earned in play.
7. Post-shift "invite a partner" button plus a 6-slot collection book of parcel types.

Plus one cosmetic game pass at about 99 Robux.

- Anything outside this list goes in `docs/LATER.md`, then work continues on the current milestone. A small finished game beats a large unfinished one.
- Most young players cannot use chat. Every feature must work through the ping board alone; chat is a bonus, never a requirement.
- One milestone at a time, stopping at each boundary for Isaac to playtest and approve.

## Milestones

Approved by Isaac. Each ends with something playable.

| Week | Builds | Playable at the end |
|---|---|---|
| 1 | Server shift loop, parcels and rules as data | A full solo shift where you see everything |
| 2 | Scanner and Clerk desks, each sent only its own information; solo desk switch and 15-second rule peek | A solo shift switching desks; a duo shift if you talk out loud |
| 3 | Ping board with eight stamps; verdict feedback | Two players finish a shift with chat off |
| 4 | Saving with retries, licence card, collection book, daily rule, odd parcel | Earn a stamp, rejoin, and it is still there |
| 5 | Cold open with three prompts, results screen with invite button, the game pass, analytics events from section 6 | A new player reaches a first verdict with no menu |
| 6 | Full parcel and rule set, fixes from friend sessions, icon and thumbnail | The public game |

If the schedule slips, cut the collection book first, then the odd parcel.

Open design questions, to settle in the milestone named:

- Week 2: how three and four players share two desks. Proposal: extra players double up on a desk.
- Week 2: there is one shift per server, so a player who joins late inherits its mistakes and remaining time, or lands on someone else's results panel. Decide this together with desk assignment. Desk assignment must be held on the server per UserId for the whole shift, or a player can rejoin and collect both halves.
- Before week 3: the eight stamps carry no values, so a "colour" stamp cannot say "red". Isaac tests the board on paper with two silent friends before it is built.
- Week 3: in the room a shipped parcel leaves to the right and a returned one goes back down the chute, but the Ship button is on the left of the screen. Line the two up when verdicts start moving the parcel.
- Week 3: verdict feedback must ignore verdicts that were judged while a joining player was still loading; those replay all at once when the client connects.
- Week 4: the repo is public, so anything seeded only from the date can be worked out by anyone. Date-seed only the rule of the day, which every player learns anyway, and keep the other rules and the parcels on a separate unseeded generator.

## Monetization

One cosmetic game pass. No purchase prompt at the moment of failure, no paid random items, no selling undo, no developer products, no ads.

## Where things live

- `src/` is the source of truth for all code. Rojo syncs it from disk into Studio, one way. Never edit these scripts in Studio or through MCP `multi_edit`; the next sync overwrites them.
- Everything that is not a script (the room, parts, UI layout, sounds, lighting) lives in the Studio place, not in `src/`. Claude builds it through MCP and says what changed; Isaac polishes it at the end. MCP cannot save the place, so after changing it ask Isaac to press Ctrl+S, then commit `ParcelPanic.rbxl`.
- Build with parts first. Studio's mesh, material, and texture generation count against Isaac's Assistant quota, so ask before using them.
- The room is `Workspace.PostOffice`, a Model with one child Model per area. Rebuild an area by replacing its Model, not by editing parts one at a time.
- The place is saved as `ParcelPanic.rbxl` in the repo root and committed at each milestone, so the room and UI are in version control too.
- Scripts find place instances by name, tag, or attribute. Record every name the code depends on in `docs/NOTES.md`.

Rojo mapping (`default.project.json`):

| On disk | In Studio |
|---|---|
| `src/shared/` | `ReplicatedStorage.Shared` (visible to server and clients) |
| `src/server/` | `ServerScriptService.Server` (server only, never sent to clients) |
| `src/client/` | `StarterPlayer.StarterPlayerScripts.Client` (runs on each player's device) |

| File name | Becomes |
|---|---|
| `Name.server.luau` | Script (runs on the server) |
| `Name.client.luau` | LocalScript (runs on the client) |
| `Name.luau` | ModuleScript (a library that other scripts `require`) |
| `init.server.luau`, `init.client.luau`, `init.luau` | the containing folder becomes that script, with the folder's other files as its children |
| a folder | Folder |

## Engineering rules

- Luau only. Every file starts with `--!strict`. Use `task.*`, never `wait`, `spawn`, or `delay`. No deprecated APIs.
- The server is authoritative for all game state. Never trust RemoteEvent arguments: check their types, check that the sender holds the right desk, and judge every Ship or Return on the server against server-held parcel data. The client never reports a score, a result, or whether a verdict was correct.
- Hidden information stays on the server until its owner needs it. Parcel contents go only to the Scanner, the rulebook only to the Clerk, and the correct answer to nobody before the verdict. Code that produces hidden information lives in `src/server/`.
- Every control has an on-screen button connected through `Activated`, so it works with mouse, touch, and gamepad. Keys are shortcuts, never the only way.
- Tunable numbers live in `src/server/Config.luau`.
- Saving handles failures, retries, and players leaving mid-save. Never overwrite saved data when the load failed.
- Parcels, rules, and stamps are data in modules, not hard-coded logic.
- Inspect the existing game structure through MCP before editing anything.
- Disconnect connections, clear per-player tables on `PlayerRemoving`, and destroy instances that are no longer used.

## After every change

1. `stylua src`, then `./scripts/check.ps1` (Selene, StyLua, and the luau-lsp strict type check).
2. Start a playtest through MCP, read the console, stop the playtest.
3. Fix errors before reporting back.
4. Say plainly which behaviours the playtest verified and which it did not.

## Before every commit

Run the `luau-reviewer` subagent on the changed files and fix what it finds. Commit small and often with clear messages; the public repo is Isaac's portfolio.

## Documentation

Keep `docs/NOTES.md` current: what each system does, in plain language, good enough to explain the project to an employer, plus every name the code depends on in the Studio place.

## Milestone self-check

A milestone is done only when all of these hold:

- the playtest ran and the console is clean;
- `luau-reviewer` passed the code;
- `docs/NOTES.md` is current;
- nothing outside version-one scope was added;
- Isaac has playtested and approved it.

## Playtest feedback so far

Milestone 1, Isaac, 2026-10-09: approved. The loop of speeding up, slipping, slowing down, and ramping up again works. Three problems to design against:

- It was not clear at first what to do. The cold open and its three prompts (week 5) have to carry this.
- The parcel in the room looked like something to interact with. The room must make it read as an object being scanned, and verdicts should visibly move it (week 3).
- It felt like only clicking and reading. Watch whether the desk split (week 2) and the ping board (week 3) fix this, especially in solo.

## Communication

- Push back when Isaac is wrong, including on design. Do not agree by default.
- Say plainly when unsure, when something failed, or when a playtest did not verify a feature.
- Be direct. No filler.
- One question at a time during setup.

## Commands

Tools are pinned in `rokit.toml`; on a fresh clone run `rokit install`.

```powershell
rojo serve                 # live-sync src/ into the open Studio place (port 34872)
stylua src                 # format
./scripts/check.ps1        # lint, format check, and strict type check
rojo build -o build.rbxl   # confirm the project file is valid
```

## Environment notes (Windows)

- Rokit's tools are in `~/.rokit/bin`. A shell started before Rokit was installed does not have it on PATH; prefix commands with `$env:Path = "$env:USERPROFILE\.rokit\bin;$env:Path"`.
- `rokit add` cannot ask for trust in a non-interactive shell. Run `rokit trust <owner/repo>` first.
- `rojo plugin install` fails on this machine ("Couldn't find registry keys"). Install or update the plugin by copying `Rojo.rbxm` from the matching Rojo GitHub release into `%LOCALAPPDATA%\Roblox\Plugins`, then restart Studio.
- Studio MCP: call `list_roblox_studios` first; every other call needs that `studio_id`. Use `datamodel_type` "Edit" outside a playtest and "Server" or "Client" during one.
- luau-lsp widens a loop variable that iterates a list of string literals to `string`. Annotate it: `for _, colour: Types.Colour in ParcelDefs.Colours do`.

## Playtesting through MCP

- Shorten a shift by setting number attributes named `Test_<Key>` on `ServerScriptService` in Edit mode (for example `Test_ShiftSeconds`). `Config.luau` reads them in Studio only. Remove them after the playtest so Isaac's own playtests run at real length.
- `execute_luau` on the Client datamodel can fire the remotes and read `PlayerGui`. Use it to send forged requests and to read what the player sees.
- The gap between starting a playtest and the next tool call is long and unpredictable. Attach listeners first, then trigger the thing under test; do not rely on catching an event that fires at startup.
- `user_mouse_input` with an `instance_path` clicks a real button, which checks the UI wiring that firing a remote directly skips.
- `screen_capture` returns a black 3D view whenever the Studio window is minimized, in Edit and Play alike. Check with `IsIconic` before trusting a dark screenshot. Take captures one at a time; two at once can hang.
- In Edit mode `StarterGui.DeskGui` draws over the viewport. Set `Enabled = false` for room screenshots and set it back to `true` before anything else.
- One MCP playtest is one player. Anything that needs two clients has to be tested by Isaac with a two-player local test or a friend, and reported as unverified until then.
