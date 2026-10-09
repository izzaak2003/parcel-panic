# Parcel Panic

A co-op Roblox game for 1-4 players, set in a bright post office for odd creatures. One player sees inside the parcel. The other knows today's rules. Together they decide: Ship or Return.

**Status:** milestone 1 of 6. A full solo shift is playable: parcels arrive, the server judges each Ship or Return, and three mistakes or the timer ends the shift. The two desks, the ping board, and saving are not built yet.

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
