# Eagle Map Loader for MTA:SA

Eagle Loader is a map and asset streaming resource for Multi Theft Auto: San Andreas.

- Current version: **4.0**
- Requires: **MTA:SA 1.6.0-9.22485 or newer**

## Features

- [x] Object and building placement
- [x] Custom model-ID assignment
- [x] Zone-based map loading
- [x] DFF, COL, TXD, and IMG support
- [x] LOD placement and linking
- [x] Day/night objects
- [x] GTA:SA map and interior compatibility
- [x] Static-building optimization
- [x] Dynamic and simulated physics objects
- [x] Per-placement physical properties
- [x] Stock-model overrides
- [x] Automatic resource cleanup

## Installation

1. Download or clone this repository.
2. Copy the `eagleLoader` folder into your server's `resources` directory.
3. Start `eagleLoader` before starting map resources that use it.

```text
start eagleLoader
start your_map_resource
```

## Documentation

Configuration, map formats, physics attributes, IMG archives, exports, and troubleshooting are documented in the [project wiki](https://github.com/BlueEagle12/MTA-Eagle-Loader/wiki).

## Exports

Eagle Loader provides client and server exports for:

- `loadMapDefinitions`
- `unloadMapDefinitions`
- `streamObject`
- `streamBuilding`
- `setElementStream`
- `getMaps` (server)

See the [wiki](https://github.com/BlueEagle12/MTA-Eagle-Loader/wiki) for signatures and examples.

## Radar support

Eagle Loader maps use [BlueEagle12/Radar-Core](https://github.com/BlueEagle12/Radar-Core) as their shared radar backend.

## Map creation tools

- [Eagle Blender scripts](https://github.com/BlueEagle12/Eagle-Map-Proccessor---Blender-Scripts)
- [Eagle map processor](https://github.com/BlueEagle12/MTA-SA-Eagle-Map-Proccessor)

## Community

Join the [Black Bear Studios Discord](https://discord.gg/q8ZTfGqRXj) for support, project updates, and community discussion.
