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

## Safety rules

- Deep links only contain relative paths.
- Absolute paths, `..`, `.`, null bytes, and paths outside the selected root are rejected.
- Registry updates preserve unknown application entries.
- Registry writes are atomic.
- The HTTP server resolves symlinks and verifies that the final file remains under the selected project root.

## Web application runtime

`Apps/LocalWeb/InstalledApps/<app-id>/` contains the installed application record and its persistent data.

### Local `.3eweb` applications

- Application files are stored under `Versions/<version>/`.
- `Data`, `Documents`, `Cache` and `Backups` remain outside the version folder.
- Each local app uses a stable loopback port derived from its identifier, preserving its browser origin during updates.

### Remote HTTPS applications

- The record stores the HTTPS start URL, custom metadata and navigation policy.
- No website source files are downloaded during installation.
- The start host is always allowed; optional declared domains may also remain inside the web view.
- Disallowed user-activated links are handed to the system browser.
- On iOS 17 and newer, each remote app uses a deterministic persistent `WKWebsiteDataStore` identifier.
- On iOS 16, normal web-origin isolation applies through the default persistent data store.
