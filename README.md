# Parcel Panic

A co-op Roblox game for 1-4 players, set in a bright post office for odd creatures. One player sees inside the parcel. The other knows today's rules. Together they decide: Ship or Return.

**Status:** milestone 4 of 6. A shift is playable in the post office room: parcels arrive under the scanner, the server judges each Ship or Return, and three mistakes or the timer ends the shift. The two desks work: a player alone switches between them with limited rulebook time, and two or more players are split so that one sees the X-ray and the other the rules. Players talk through a ping board of eight ready-made stamps, with no chat needed, and the parcel rides the conveyor in and out. Each day has its own rule that every player shares, and a postal licence card and a collection book carry over between visits.

Two things are checked only by a simulation so far (`tests/Simulate.luau`, about 100 checks): play by two or more people at once, and saving, which is tested against a stand-in data store with injected failures and has not yet run against Roblox's real one.

## How it is built

- Luau in strict mode, kept as files on disk and synced into Roblox Studio with [Rojo](https://rojo.space).
- The server decides everything that matters. Clients send requests; the server checks each one against its own data.
- Parcels, rules, and stamps are data in modules.
- Linted with Selene, formatted with StyLua, type-checked with luau-lsp. `scripts/check.ps1` runs all three.

## Running it

Requires Roblox Studio and [Rokit](https://github.com/rojo-rbx/rokit).

```sh
rokit install   # installs the pinned Rojo, Selene, StyLua, and luau-lsp
rojo serve      # then connect from the Rojo plugin in Studio
```

## Layout

| Path | Contents |
|---|---|
| `src/server/` | Server-only code |
| `src/client/` | Code that runs on each player's device |
| `src/shared/` | Code and data both sides use |
| `docs/NOTES.md` | Plain-language notes on every system |
