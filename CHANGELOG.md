# Changelog

## 0.2.0-M01

- Added the first installable 3E Web Apps runtime while preserving the existing local project launcher.
- Added `.3eweb` package import through the Files picker and document opening.
- Added package validation for safe paths, archive size, entry count, symlinks, native executable types, manifest schema, app identity, runtime compatibility, entry page and icon.
- Added versioned installation storage under `Apps/LocalWeb/InstalledApps`.
- Added install, reinstall, update, uninstall and rollback operations.
- App code versions are separated from persistent `Data` and `Documents` folders.
- Added a dedicated Applications tab alongside the existing Projects tab.
- Added stable per-app local HTTP ports so WebKit storage origins remain consistent across launches and updates.
- Added ZIPFoundation 0.9.20 through Swift Package Manager.
- Declared the custom `.3eweb` document type.
- Added two Hello3E test packages for install/update/rollback and localStorage persistence tests.
- Increased the app version to `0.2.0` and build number to `4`.

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
