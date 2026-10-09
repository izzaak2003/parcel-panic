# Parcel Panic: how it works

Plain-language notes on every system, kept current as the game is built.

## Status

Setup. No game code yet.

## The toolchain

Roblox games are normally written inside Roblox Studio, where scripts are stored inside the game file. That makes version control and outside tools hard to use. This project keeps the code as ordinary files on disk instead.

| Tool | Version | What it does |
|---|---|---|
| Roblox Studio | current | The editor and engine. The 3D room, the UI layout, and playtesting live here. |
| Rokit | 1.2.0 | Installs the exact tool versions listed in `rokit.toml`, so every machine uses the same ones. |
| Rojo | 7.7.1 | Copies the `.luau` files in `src/` into the open Studio place and keeps them in sync as they change. Two halves: a command-line server (`rojo serve`) and a Studio plugin that connects to it. |
| Selene | 0.32.0 | Linter. Reads the code without running it and flags likely mistakes, such as unused variables or deprecated Roblox calls. |
| StyLua | 2.5.2 | Formatter. Rewrites code into one consistent layout so diffs show only real changes. |
| Studio MCP server | built in | Lets Claude Code look at the open place, start and stop playtests, and read the console, so changes are tested and not just written. |
| git and GitHub | git 2.47 | History and the public portfolio. |

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

## Systems

None yet. Each system is added here when it is built.

## Names the code depends on

None yet. Any part, UI element, or tag in the Studio place that a script looks up by name is listed here.
