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
