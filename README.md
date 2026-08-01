# Eagle Map Loader for MTA:SA

Eagle Loader is a map and asset streaming resource for Multi Theft Auto: San Andreas.

- Current version: **4.0**
- Requires: **MTA:SA 1.6.0-9.22485 or newer**

## Features

- Object and building placement
- Custom model-ID assignment
- Zone-based map loading
- DFF, COL, TXD, and IMG support
- LOD placement and linking
- Day/night objects
- GTA:SA map and interior compatibility
- Static-building optimization
- Dynamic and simulated physics objects
- Per-placement physical properties
- Stock-model overrides
- Automatic resource cleanup

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

## Map creation tools

- [Eagle Blender scripts](https://github.com/BlueEagle12/Eagle-Map-Proccessor---Blender-Scripts)
- [Eagle map processor](https://github.com/BlueEagle12/MTA-SA-Eagle-Map-Proccessor)

## Community

[Discord](https://discord.gg/q8ZTfGqRXj)
