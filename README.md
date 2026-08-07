# Eagle Loader

**A map and asset streaming runtime for Multi Theft Auto: San Andreas.**

[![Version](https://img.shields.io/badge/version-4.0-2563eb)](eagleLoader/meta.xml)
[![MTA:SA](https://img.shields.io/badge/MTA%3ASA-1.6.0--9.22485%2B-f97316)](#requirements)
[![Documentation](https://img.shields.io/badge/docs-Wiki-4b5563)](https://github.com/BlueEagle12/MTA-Eagle-Loader/wiki)

Eagle Loader turns an MTA resource into a streamed custom world. It assigns
model IDs, loads DFF/COL/TXD assets from files or IMG archives, creates map
placements, manages LODs and physics, and releases map-owned resources cleanly
when a resource stops.

## Highlights

- Zone-based map loading with `.definition` and `.map` files.
- Automatic custom model-ID allocation with optional stock-ID fallback.
- DFF, COL, TXD, and IMG archive support.
- Object and building placement with static-building optimization.
- High-detail/LOD linking, draw-distance scaling, and moving LOD attachments.
- Day/night objects, timed models, dimensions, interiors, and world offsets.
- Dynamic and simulated physics with definition defaults and per-placement
  overrides.
- Stock-model behavior, native flags, breakability, and physical properties.
- Optional stock San Andreas map and interior removal.
- Water loading, foliage alpha-fix shaders, crash diagnostics, and streaming
  logs.
- Client and server exports for spawning and retargeting streamed elements.
- Resource-scoped model ownership, caching, unloading, and cleanup.

## Requirements

- **MTA:SA client 1.6.0-9.22485 or newer**.
- An MTA server capable of running the included `eagleLoader` resource.
- Map resources following Eagle's zone, definition, and placement format.

## Installation

1. Download or clone this repository.
2. Copy the `eagleLoader` folder into the server's `resources` directory.
3. Review `eagleLoader/config.xml` before starting the resource.
4. Start `eagleLoader` before every map resource that depends on it.

```text
start eagleLoader
start your_map_resource
```

The active configuration file is `eagleLoader/config.xml`. The older
`config.lua` file is retained for reference but is not loaded by `meta.xml`.

## Creating a map resource

An Eagle map is an ordinary MTA resource with a zone list, definitions,
placements, and registered client assets:

```text
your_map_resource/
├── meta.xml
├── eagleZones.txt
├── textures/
│   └── shared.txd
├── imgs/                         # Optional
│   ├── dff.img
│   ├── col.img
│   └── txd.img
└── zones/
    └── downtown/
        ├── downtown.definition
        ├── downtown.map
        ├── dff/                  # Optional with IMG archives
        └── col/                  # Optional with IMG archives
```

List each zone in `eagleZones.txt`:

```text
downtown
industrial
airport
```

A definition connects a logical model ID to its assets:

```xml
<zoneDefinitions>
    <definition
        id="custom_building"
        dff="custom_building"
        col="custom_building"
        txd="shared"
        lodDistance="250" />
</zoneDefinitions>
```

The matching map file places that logical model in the world:

```xml
<map>
    <building
        id="custom_building"
        posX="100"
        posY="200"
        posZ="20"
        rotX="0"
        rotY="0"
        rotZ="90" />
</map>
```

Every client-side file must also be registered in the map resource's
`meta.xml`. See the Wiki's
[Creating a Map](https://github.com/BlueEagle12/MTA-Eagle-Loader/wiki/Creating-a-map)
guide for the complete layout and start order.

## Configuration

`eagleLoader/config.xml` controls:

- IMG archive names and numbered archive scanning.
- Stock map/interior removal and model-ID allocation.
- Static-building preference and building-pool headroom.
- Streaming memory, buffer size, and draw-distance scaling.
- LOD behavior and models whose LODs follow moving parents.
- Alpha-fix texture patterns.
- Debug output, crash-finder behavior, and crash-zone exclusions.

Restart `eagleLoader` and active map resources after changing the file. The
[Configuration guide](https://github.com/BlueEagle12/MTA-Eagle-Loader/wiki/Config)
documents every setting and its shipped default.

## IMG archives

Large maps can keep DFF, COL, and TXD assets in IMG v2 archives under `imgs/`
instead of registering thousands of individual files. Standard archive names
are `dff`, `col`, `txd`, and `custom`, with numbered variants such as
`dff_1.img`.

A map can override the global scan list with `eagleLoader-imgs.xml`. See
[IMG Archives](https://github.com/BlueEagle12/MTA-Eagle-Loader/wiki/IMG-archives)
for naming, registration, and custom archive examples.

## Physics and runtime behavior

Definitions can provide shared physics defaults while individual placements
override only the values they need. Supported controls include simulation,
stock physics roots, mass, turn mass, air resistance, elasticity, buoyancy,
center of mass, breakability, respawn behavior, freezing, collision, alpha,
scale, and streaming.

Anything that requests simulation or object-only physical behavior is routed
through MTA's object path even if the placement was authored as a building. See
the [Physics guide](https://github.com/BlueEagle12/MTA-Eagle-Loader/wiki/Physics)
for attributes and examples.

## Exports

Eagle Loader exposes these functions through MTA's resource export system:

| Export | Client | Server | Purpose |
| --- | :---: | :---: | --- |
| `streamObject` | Yes | Yes | Create a streamed object from a logical or stock model ID |
| `streamBuilding` | Yes | Yes | Create a streamed building |
| `setElementStream` | Yes | Yes | Assign another streamed model to an element |
| `loadMapDefinitions` | Yes | — | Register a definition table asynchronously |
| `unloadMapDefinitions` | Yes | — | Unload a resource's definitions and owned state |
| `getMaps` | — | Yes | List running resources containing `eagleZones.txt` |

Signatures and Lua examples are available on the
[Exports Wiki page](https://github.com/BlueEagle12/MTA-Eagle-Loader/wiki/Exports).

## Radar support

Eagle maps use [BlueEagle12/Radar-Core](https://github.com/BlueEagle12/Radar-Core)
as their shared radar backend. Radar artwork and configuration normally live in
a separate `Radar_Files` resource so multiple maps can use the same system.

## Map authoring tools

- [MTA Tool Kit](https://github.com/BlueEagle12/MTA-Tool-Kit) — Blender add-on
  for generating Eagle resources, models, collisions, definitions, and maps.
- [Eagle Editor](https://github.com/BlueEagle12/MTA-Eagle-Editor) — native 3D
  project, map, and RenderWare asset editor.

## Documentation

The [Eagle Loader Wiki](https://github.com/BlueEagle12/MTA-Eagle-Loader/wiki)
contains detailed guides for:

- [Creating a map](https://github.com/BlueEagle12/MTA-Eagle-Loader/wiki/Creating-a-map)
- [Definition files](https://github.com/BlueEagle12/MTA-Eagle-Loader/wiki/.definition-Files)
  and [map files](https://github.com/BlueEagle12/MTA-Eagle-Loader/wiki/.map-Files)
- [Physics](https://github.com/BlueEagle12/MTA-Eagle-Loader/wiki/Physics)
- [IMG archives](https://github.com/BlueEagle12/MTA-Eagle-Loader/wiki/IMG-archives)
- [Configuration](https://github.com/BlueEagle12/MTA-Eagle-Loader/wiki/Config)
  and [exports](https://github.com/BlueEagle12/MTA-Eagle-Loader/wiki/Exports)
- [Object flags](https://github.com/BlueEagle12/MTA-Eagle-Loader/wiki/Flag-reference)
- [Debugging](https://github.com/BlueEagle12/MTA-Eagle-Loader/wiki/Debugging)

## Troubleshooting

- **An asset cannot be found:** confirm its capitalization, resource path, and
  `meta.xml` registration, or check the configured IMG archive names.
- **A placement uses the wrong model:** run `/findid <id>` and verify its loaded
  definition and resource owner.
- **LOD behavior looks wrong:** temporarily set `disableLOD="true"` in
  `config.xml` to isolate the relationship.
- **A model crashes the client:** use the built-in model crash finder and review
  the final attempted model in its log.

For a complete diagnostic workflow, see
[Debugging](https://github.com/BlueEagle12/MTA-Eagle-Loader/wiki/Debugging).

## Community

Join the [Black Bear Studios Discord](https://discord.gg/q8ZTfGqRXj) for
support, project updates, and community discussion. Reproducible problems can
also be filed on the
[GitHub issue tracker](https://github.com/BlueEagle12/MTA-Eagle-Loader/issues).
