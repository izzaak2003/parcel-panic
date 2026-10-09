# Parcel Panic

Co-op Roblox game, version one. A bright daytime post office for odd creatures, 1-4 players. The Scanner sees inside each parcel; the Clerk holds a rulebook that changes daily. Together they Ship or Return each parcel. Shifts last 8-10 minutes and three mistakes end the shift.

## Spec

Read both reports before any design or scope decision.

- `docs/compass_artifact_wf-47397798-09c6-52c8-874f-9e88fede7a97_text_markdown(1).md` is report 1: stack, setup order, and known failure modes of AI-written Roblox code. Its game concept (Night Desk) is superseded.
- `docs/compass_artifact_wf-b4cadeeb-a484-50e7-b0a9-439e3d270a05_text_markdown.md` is report 2: the Parcel Panic design. Where the reports conflict, report 2 wins.

## Roles

Claude is lead engineer and tutor: writes the code and teaches enough that Isaac can understand, debug, and explain every part. Isaac is product owner and polishes by hand. Isaac is a CS student, comfortable with the command line and git, new to Roblox Studio and Luau, with about 10 hours a week for 6 weeks.

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
- Game code starts only after Isaac confirms the milestone plan. One milestone at a time, stopping at each boundary for Isaac to playtest and approve.

## Monetization

One cosmetic game pass. No purchase prompt at the moment of failure, no paid random items, no selling undo, no developer products, no ads.

## Where things live

- `src/` is the source of truth for all code. Rojo syncs it from disk into Studio, one way. Never edit these scripts in Studio or through MCP `multi_edit`; the next sync overwrites them.
- Everything that is not a script (the room, parts, UI layout, sounds, lighting) lives in the Studio place, not in `src/`. Isaac builds and polishes it by hand. Claude changes it through MCP only when a milestone needs it, and says so when it does.
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
- Hidden information stays on the server until its owner needs it. Parcel contents go only to the Scanner, the rulebook only to the Clerk, and the correct answer to nobody before the verdict.
- Saving handles failures, retries, and players leaving mid-save. Never overwrite saved data when the load failed.
- Parcels, rules, and stamps are data in modules, not hard-coded logic.
- Inspect the existing game structure through MCP before editing anything.
- Disconnect connections, clear per-player tables on `PlayerRemoving`, and destroy instances that are no longer used.

## After every change

1. `selene src` and `stylua src`.
2. Start a playtest through MCP, read the console, stop the playtest.
3. Fix errors before reporting back.
4. Say plainly which behaviours the playtest verified and which it did not.

## Before every commit

Run the `luau-reviewer` subagent on the changed files and fix what it finds. Commit small and often with clear messages; the public repo is Isaac's portfolio.

## Tutoring

- Before each new system, explain in a few sentences what it is and why Roblox does it this way. Define every Roblox term the first time it appears.
- After writing a system, give a short walkthrough of the code and ask one question that checks understanding. If the answer is wrong, explain again differently.
- Give small hands-on Studio tasks (placing parts, adjusting UI, tuning values) so Isaac learns the editor.
- Keep `docs/NOTES.md` current: what each system does, in plain language, good enough to explain the project to an employer.

## Milestone self-check

A milestone is done only when all of these hold:

- the playtest ran and the console is clean;
- `luau-reviewer` passed the code;
- `docs/NOTES.md` is current;
- Isaac answered the comprehension question;
- nothing outside version-one scope was added.

## Communication

- Push back when Isaac is wrong, including on design. Do not agree by default.
- Say plainly when unsure, when something failed, or when a playtest did not verify a feature.
- Be direct. No filler.
- One question at a time during setup.

## Commands

Tools are pinned in `rokit.toml`; on a fresh clone run `rokit install`.

```powershell
rojo serve                 # live-sync src/ into the open Studio place (port 34872)
selene src                 # lint
stylua src                 # format; add --check to verify without writing
rojo build -o build.rbxl   # confirm the project file is valid
```

## Environment notes (Windows)

- Rokit's tools are in `~/.rokit/bin`. A shell started before Rokit was installed does not have it on PATH; prefix commands with `$env:Path = "$env:USERPROFILE\.rokit\bin;$env:Path"`.
- `rokit add` cannot ask for trust in a non-interactive shell. Run `rokit trust <owner/repo>` first.
- `rojo plugin install` fails on this machine ("Couldn't find registry keys"). Install or update the plugin by copying `Rojo.rbxm` from the matching Rojo GitHub release into `%LOCALAPPDATA%\Roblox\Plugins`, then restart Studio.
- Studio MCP: call `list_roblox_studios` first; every other call needs that `studio_id`. Use `datamodel_type` "Edit" outside a playtest and "Server" or "Client" during one.
