# Changelog

## 0.2.0-M02 — Remote Web Apps

- Added remote web applications that run from HTTPS URLs without downloading the website.
- Added optional website metadata discovery from HTML and Web App Manifest files.
- Added custom app name, description and icon selection.
- Added local/remote filtering and online/offline badges in the application library.
- Added per-app navigation policies: same host, declared domains or unrestricted.
- Added external-link handoff to the system browser when navigation is blocked.
- Added a persistent, isolated WebKit data store per remote app on iOS 17 and newer.
- Added connection-error banners and offline recovery UI.
- Added an application details screen with storage size, install/update dates and launch history.
- Added reliable `.3eweb` intake from the Files app, including pending imports before the 3E folder reconnects.
- Increased the internal build number to 5.

## 0.1.2

- Added compatibility with both historical `registry.json` app formats: array and dictionary.
- Preserves 3ELiDAR and 3ERoomElectrical records instead of replacing them when an older array registry is found.
- Canonicalizes the next write to an app-keyed dictionary and coordinates writes with `NSFileCoordinator`.
- Increased the internal build number to 3.

## 0.1.1

- Fixed the Swift actor-isolation build error in `ThreeEStorageManager`.
- Ensured the GitHub Actions `build` directory exists before writing `xcodebuild.log`.
- Added automatic upload of the build log when the workflow fails.
- Increased the internal build number to 2.
