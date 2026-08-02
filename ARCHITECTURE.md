# 3E shared storage architecture

## Current experimental mode

The user selects the same `3E` directory in each app through Files. Each app stores a security-scoped bookmark and owns a subdirectory under `Apps/`.

## Future App Group mode

Identifier: `group.com.essam.3e`

Storage resolution order planned for all three apps:

1. App Group container when the entitlement is present and `containerURL` succeeds.
2. User-selected Files directory restored from a security-scoped bookmark.
3. Private app storage only as a temporary fallback.

## Application identities

| App | Bundle ID | Scheme | Folder |
|---|---|---|---|
| 3ELiDAR | `com.essam.3E.LiDARLab` | `lidar` | `Apps/LiDARLab` |
| 3ERoomElectrical | `com.essam.3E.roomelectrical` | `electrical` | `Apps/RoomElectrical` |
| 3ELocal | `com.essam.3E.localweb` | `localweb` | `Apps/LocalWeb` |

## 3E Web App runtime

`3ELocal 0.2.0-M01` supports installable local HTML5/JavaScript packages with the `.3eweb` extension.

```text
Apps/LocalWeb/
├── Projects/          # Editable development folders
├── InstalledApps/     # Versioned installed packages
├── Packages/          # Optional package storage
├── Downloads/         # Future online downloads
├── Imports/
├── Exports/
├── Cache/
└── Settings/
```

Each installed app receives a stable loopback port derived from its package identifier. This keeps its WebKit origin stable across launches and package updates, allowing `localStorage`, IndexedDB and cookies to remain associated with that app instead of a random server port.

## Package safety rules

- Only `.3eweb` and manually selected `.zip` archives are accepted by the importer.
- Package size, expanded size and entry count are bounded.
- Absolute paths, traversal components, null bytes and unsafe archive paths are rejected.
- Symbolic links are rejected.
- Native executable and installable file types are rejected.
- `manifest.json` must use schema version 1 and a safe package identifier/version.
- The entry page must be an existing `.html` or `.htm` file inside the package.
- The package runtime requirement must not exceed the installed 3ELocal runtime.
- Installation is staged before an active version is replaced.
- App code versions are separated from persistent `Data` and `Documents` folders.

## Existing safety rules

- Deep links only contain relative paths.
- Absolute paths, `..`, `.`, null bytes, and paths outside the selected root are rejected.
- Registry updates preserve unknown application entries.
- Registry writes are atomic.
- The HTTP server resolves symlinks and verifies that the final file remains under the selected project root.
