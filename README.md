# Parcel Panic

A co-op Roblox game for 1-4 players, set in a bright post office for odd creatures. One player sees inside the parcel. The other knows today's rules. Together they decide: Ship or Return.

**Status:** project setup. No gameplay yet.

## How it is built

- Luau in strict mode, kept as files on disk and synced into Roblox Studio with [Rojo](https://rojo.space).
- The server decides everything that matters. Clients send requests; the server checks each one against its own data.
- Parcels, rules, and stamps are data in modules.
- Linted with Selene, formatted with StyLua.

## Running it

Requires Roblox Studio and [Rokit](https://github.com/rojo-rbx/rokit).

```sh
rokit install   # installs the pinned Rojo, Selene, and StyLua
rojo serve      # then connect from the Rojo plugin in Studio
```

## Layout

| Path | Contents |
|---|---|
| `src/server/` | Server-only code |
| `src/client/` | Code that runs on each player's device |
| `src/shared/` | Code and data both sides use |
| `docs/NOTES.md` | Plain-language notes on every system |
